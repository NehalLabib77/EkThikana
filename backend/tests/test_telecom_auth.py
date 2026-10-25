"""Unit tests for telecom router and bdApps subscription verification."""

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routers.telecom import (
    _extract_subscription_status,
    _normalise_status,
    _normalize_phone,
    _verify_subscription_with_bdapps,
    router,
)

app = FastAPI()
app.include_router(router, prefix="/v1/auth/telecom")
client = TestClient(app)


class TestExtractSubscriptionStatus:
    """Verify robust extraction of subscriptionStatus from bdApps responses."""

    def test_top_level_registered(self):
        assert _extract_subscription_status({"subscriptionStatus": "REGISTERED"}) == "REGISTERED"

    def test_nested_data_registered(self):
        body = {"statusCode": "S1000", "data": {"subscriptionStatus": "REGISTERED"}}
        assert _extract_subscription_status(body) == "REGISTERED"

    def test_nested_initial_charging_pending(self):
        body = {"data": {"subscriptionStatus": "INITIAL CHARGING PENDING"}}
        assert _extract_subscription_status(body) == "INITIAL CHARGING PENDING"

    def test_top_level_temporary_blocked(self):
        body = {"subscriptionStatus": "TEMPORARY BLOCKED"}
        assert _extract_subscription_status(body) == "TEMPORARY BLOCKED"

    def test_nested_data_temporary_blocked(self):
        body = {"data": {"subscriptionStatus": "TEMPORARY BLOCKED"}}
        assert _extract_subscription_status(body) == "TEMPORARY BLOCKED"

    def test_absent_status_returns_empty(self):
        assert _extract_subscription_status({}) == ""
        assert _extract_subscription_status({"statusCode": "S1000"}) == ""

    def test_null_status_and_null_data(self):
        assert _extract_subscription_status({"subscriptionStatus": None, "data": None}) == ""

    def test_non_dict_data_field(self):
        assert _extract_subscription_status({"data": "not-a-dict"}) == ""
        assert _extract_subscription_status({"data": [1, 2, 3]}) == ""

    def test_non_dict_body(self):
        assert _extract_subscription_status("raw string") == ""
        assert _extract_subscription_status(None) == ""
        assert _extract_subscription_status([{"subscriptionStatus": "REGISTERED"}]) == ""

    def test_whitespace_trimmed(self):
        assert _extract_subscription_status({"subscriptionStatus": "  REGISTERED  "}) == "REGISTERED"
        assert _extract_subscription_status({"data": {"subscriptionStatus": "  INITIAL CHARGING PENDING  "}}) == "INITIAL CHARGING PENDING"


class TestTelecomExchangeEndpoint:
    """Verify /v1/auth/telecom/exchange endpoint authorization and token issuance."""

    @pytest.mark.parametrize(
        "invalid_phone",
        [
            "01712345678",  # Grameenphone
            "01912345678",  # Banglalink
            "01512345678",  # Teletalk
            "01312345678",  # Skitto
            "01412345678",  # Banglalink
            "01812345",     # Too short
            "016123456789", # Too long
            "0181234567a",  # Non-digit
            "",             # Empty
        ],
    )
    def test_rejects_unsupported_prefix(self, invalid_phone):
        resp = client.post(
            "/v1/auth/telecom/exchange",
            json={"phone": invalid_phone},
        )
        assert resp.status_code == 400
        assert resp.json()["detail"] == "Only Robi (018) and Cirkle (016) numbers are supported"

    @patch("app.routers.telecom._verify_subscription_with_bdapps", new_callable=AsyncMock)
    def test_bdapps_unreachable_returns_502(self, mock_verify):
        mock_verify.return_value = None  # carrier call failed or timed out
        resp = client.post(
            "/v1/auth/telecom/exchange",
            json={"phone": "01812345678"},
        )
        assert resp.status_code == 502
        assert "Could not verify subscription with carrier" in resp.json()["detail"]

    @patch("app.routers.telecom._verify_subscription_with_bdapps", new_callable=AsyncMock)
    def test_temporary_blocked_status_returns_403(self, mock_verify):
        mock_verify.return_value = "TEMPORARY BLOCKED"
        resp = client.post(
            "/v1/auth/telecom/exchange",
            json={"phone": "01812345678", "already_subscribed": True},
        )
        assert resp.status_code == 403
        assert "Subscription not active" in resp.json()["detail"]

    @patch("app.routers.telecom._verify_subscription_with_bdapps", new_callable=AsyncMock)
    def test_unregistered_status_returns_403(self, mock_verify):
        mock_verify.return_value = "UNREGISTERED"
        resp = client.post(
            "/v1/auth/telecom/exchange",
            json={"phone": "01812345678"},
        )
        assert resp.status_code == 403
        assert "Subscription not active" in resp.json()["detail"]

    @patch("app.routers.telecom._verify_subscription_with_bdapps", new_callable=AsyncMock)
    def test_client_spoofed_fields_ignored_when_carrier_rejects(self, mock_verify):
        mock_verify.return_value = ""  # carrier reports not registered
        resp = client.post(
            "/v1/auth/telecom/exchange",
            json={
                "phone": "01812345678",
                "already_subscribed": True,
                "subscription_status": "REGISTERED",  # client tries to claim registered
            },
        )
        assert resp.status_code == 403
        assert "Subscription not active" in resp.json()["detail"]

    @patch("app.routers.telecom._ensure_firebase")
    @patch("app.routers.telecom._verify_subscription_with_bdapps", new_callable=AsyncMock)
    def test_successful_exchange_with_top_level_status(self, mock_verify, mock_fb):
        mock_verify.return_value = "REGISTERED"

        with patch("firebase_admin.auth") as mock_auth:
            mock_auth.get_user.return_value = MagicMock()
            mock_auth.create_custom_token.return_value = "mock_jwt_token_123"

            resp = client.post(
                "/v1/auth/telecom/exchange",
                json={"phone": "01812345678"},
            )
            assert resp.status_code == 200
            data = resp.json()
            assert data["uid"] == "telecom:01812345678"
            assert data["firebase_custom_token"] == "mock_jwt_token_123"
            mock_auth.update_user.assert_called_with("telecom:01812345678", email_verified=True)
            mock_auth.set_custom_user_claims.assert_called_with("telecom:01812345678", {"telecom_verified": True})
            mock_auth.create_custom_token.assert_called_with("telecom:01812345678", developer_claims={"telecom_verified": True})

    @patch("app.routers.telecom._ensure_firebase")
    @patch("app.routers.telecom._verify_subscription_with_bdapps", new_callable=AsyncMock)
    def test_successful_exchange_with_nested_data_status(self, mock_verify, mock_fb):
        mock_verify.return_value = "INITIAL CHARGING PENDING"

        with patch("firebase_admin.auth") as mock_auth:
            mock_auth.get_user.return_value = MagicMock()
            mock_auth.create_custom_token.return_value = "mock_jwt_token_456"

            resp = client.post(
                "/v1/auth/telecom/exchange",
                json={"phone": "01687654321"},
            )
            assert resp.status_code == 200
            data = resp.json()
            assert data["uid"] == "telecom:01687654321"
            assert data["firebase_custom_token"] == "mock_jwt_token_456"
            mock_auth.create_custom_token.assert_called_with("telecom:01687654321", developer_claims={"telecom_verified": True})


@pytest.mark.anyio
class TestVerifySubscriptionWithBdapps:
    """Verify carrier HTTP integration and error resilience."""

    async def test_returns_none_on_http_error(self):
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = MagicMock(status_code=500, json=lambda: {})
            result = await _verify_subscription_with_bdapps("01812345678")
            assert result is None

    async def test_returns_none_on_exception(self):
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.side_effect = httpx.ConnectTimeout("timeout connecting to bdApps")
            result = await _verify_subscription_with_bdapps("01812345678")
            assert result is None

    async def test_returns_extracted_status_on_200(self):
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = MagicMock(
                status_code=200,
                json=lambda: {"data": {"subscriptionStatus": "REGISTERED"}},
            )
            result = await _verify_subscription_with_bdapps("01812345678")
            assert result == "REGISTERED"

    async def test_retries_transient_connection_error_and_succeeds(self):
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.side_effect = [
                httpx.RemoteProtocolError("Server disconnected without sending a response"),
                MagicMock(
                    status_code=200,
                    json=lambda: {"data": {"subscriptionStatus": "REGISTERED"}},
                ),
            ]
            result = await _verify_subscription_with_bdapps("01812345678")
            assert result == "REGISTERED"
            assert mock_post.call_count == 2
