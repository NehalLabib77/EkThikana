"""Tests for the OSRM/Nominatim routing provider.

These tests pin the meters→km conversion contract so that a future
refactor cannot silently re-introduce the distance-in-meters bug. The
existing ``test_commute_postgres`` suite uses a ``_FakeRouting`` that
returns ``distanceKm`` directly, so it never exercises the real
provider's unit conversion.
"""

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


from app.services.commute.routing import (  # noqa: E402
    Coordinate,
    OsrmNominatimProvider,
)


def _fake_httpx_response(payload: dict[str, Any], status_code: int = 200):
    """Build a stand-in for httpx.Response that the provider can consume."""
    return SimpleNamespace(
        status_code=status_code,
        json=lambda: payload,
        text=str(payload),
    )


def _fake_httpx_client(response: Any):
    """Build an async context manager that yields a fake httpx.AsyncClient."""

    class _Client:
        def __init__(self, *_args, **_kwargs):
            pass

        async def __aenter__(self):
            self._client = SimpleNamespace(get=AsyncMock(return_value=response))
            return self._client

        async def __aexit__(self, *_args):
            return None

    return _Client


# ---------------------------------------------------------------------------
# meters → km conversion
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_route_converts_meters_to_kilometers():
    """OSRM returns distance in METERS. The provider must divide by 1000.

    Regression test for the user-visible bug: a 5,400 m trip should
    display as 5.4 km, not 5,400 km or 0.0054 km.
    """
    payload = {
        "routes": [
            {
                "distance": 5400.0,  # 5.4 km, in meters per OSRM API contract
                "duration": 720.0,   # 12 minutes
                "geometry": {"coordinates": [[90.4, 23.8], [90.41, 23.81]]},
            }
        ]
    }
    response = _fake_httpx_response(payload)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        result = await provider.route(
            Coordinate(lat=23.8, lon=90.4),
            Coordinate(lat=23.81, lon=90.41),
        )

    # The whole reason this test exists: 5,400 m must become 5.4 km.
    assert result["distanceKm"] == 5.4
    # 720 seconds must become 12 minutes, with a floor of 1.
    assert result["durationMinutes"] == 12
    # Provider label is preserved so the UI can show "OSRM" in the
    # "By road" caption.
    assert result["provider"] == "OSRM"


@pytest.mark.asyncio
async def test_route_rounds_to_two_decimal_places():
    """The contract is to round distanceKm to 2dp — not truncate, not 1dp."""
    payload = {
        "routes": [
            {
                "distance": 1234.0,   # 1.234 km
                "duration": 300.0,    # 5 minutes
                "geometry": {"coordinates": []},
            }
        ]
    }
    response = _fake_httpx_response(payload)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        result = await provider.route(
            Coordinate(lat=23.8, lon=90.4),
            Coordinate(lat=23.81, lon=90.41),
        )

    # 1.234 km must round to 1.23 km, not stay 1.234 and not truncate to 1.2.
    assert result["distanceKm"] == 1.23


@pytest.mark.asyncio
async def test_route_treats_zero_meters_as_zero_km():
    """Zero meters must become zero km — never negative, never None."""
    payload = {
        "routes": [
            {
                "distance": 0,
                "duration": 0,
                "geometry": {"coordinates": []},
            }
        ]
    }
    response = _fake_httpx_response(payload)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        result = await provider.route(
            Coordinate(lat=23.8, lon=90.4),
            Coordinate(lat=23.8, lon=90.4),
        )

    assert result["distanceKm"] == 0.0
    # durationMinutes has a floor of 1: "0 minutes" is unhelpful for the user.
    assert result["durationMinutes"] == 1


@pytest.mark.asyncio
async def test_route_handles_missing_distance_field_gracefully():
    """OSRM responses without a 'distance' field must default to 0 km.

    We never want to crash the commute screen on a partial response.
    """
    payload = {
        "routes": [
            {
                # No 'distance' key at all.
                "duration": 60.0,
                "geometry": {"coordinates": []},
            }
        ]
    }
    response = _fake_httpx_response(payload)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        result = await provider.route(
            Coordinate(lat=23.8, lon=90.4),
            Coordinate(lat=23.81, lon=90.41),
        )

    assert result["distanceKm"] == 0.0


# ---------------------------------------------------------------------------
# coordinate order in the OSRM URL
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_route_uses_lon_lat_order_in_osrm_url():
    """OSRM expects 'lon,lat;lon,lat'. A swapped order silently returns
    routes on the wrong half of the planet (or no route at all).
    """
    captured: dict[str, Any] = {}

    payload = {
        "routes": [
            {
                "distance": 1000.0,
                "duration": 60.0,
                "geometry": {"coordinates": []},
            }
        ]
    }
    response = _fake_httpx_response(payload)

    async def _capture_get(url, params=None, headers=None):
        captured["url"] = url
        captured["params"] = params
        return response

    class _Client:
        def __init__(self, *_a, **_kw):
            pass

        async def __aenter__(self):
            return SimpleNamespace(get=_capture_get)

        async def __aexit__(self, *_a):
            return None

    with patch("app.services.commute.routing.httpx.AsyncClient", _Client):
        provider = OsrmNominatimProvider()
        await provider.route(
            Coordinate(lat=23.8, lon=90.4),
            Coordinate(lat=23.81, lon=90.41),
        )

    # The endpoint URL must put lon FIRST, then lat, for both endpoints.
    # 90.4 < 90.41 and 23.8 < 23.81, so we can assert the order directly.
    assert captured["url"].endswith("90.4,23.8;90.41,23.81"), (
        f"OSRM URL must use lon,lat;lon,lat order, got: {captured['url']}"
    )


# ---------------------------------------------------------------------------
# polyline coordinates — lon FIRST from OSRM, lat FIRST in the public API
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_route_polyline_swaps_lon_lat_to_lat_lon():
    """OSRM's geojson gives [lon, lat]; our public payload must expose
    {lat, lon}. The swap is easy to get backwards.
    """
    payload = {
        "routes": [
            {
                "distance": 1000.0,
                "duration": 60.0,
                "geometry": {
                    "coordinates": [
                        [90.400, 23.800],
                        [90.401, 23.801],
                    ]
                },
            }
        ]
    }
    response = _fake_httpx_response(payload)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        result = await provider.route(
            Coordinate(lat=23.8, lon=90.4),
            Coordinate(lat=23.81, lon=90.41),
        )

    assert len(result["polyline"]) == 2
    # First point: OSRM said [90.400, 23.800]; we expose lat first.
    assert result["polyline"][0]["lat"] == pytest.approx(23.800)
    assert result["polyline"][0]["lon"] == pytest.approx(90.400)
    assert result["polyline"][1]["lat"] == pytest.approx(23.801)
    assert result["polyline"][1]["lon"] == pytest.approx(90.401)


# ---------------------------------------------------------------------------
# error paths
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_route_raises_on_http_error():
    """An HTTP error must surface as a RuntimeError so the caller can
    show 'the map service is unavailable' rather than a silent zero."""
    response = _fake_httpx_response({}, status_code=500)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        with pytest.raises(RuntimeError, match="Routing provider error"):
            await provider.route(
                Coordinate(lat=23.8, lon=90.4),
                Coordinate(lat=23.81, lon=90.41),
            )


@pytest.mark.asyncio
async def test_route_raises_when_no_routes_returned():
    """An empty 'routes' list must surface as a RuntimeError, not return
    zero km — that would mislead the student into thinking the trip is
    free."""
    payload = {"routes": []}
    response = _fake_httpx_response(payload)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        with pytest.raises(RuntimeError, match="No route found"):
            await provider.route(
                Coordinate(lat=23.8, lon=90.4),
                Coordinate(lat=23.81, lon=90.41),
            )


@pytest.mark.asyncio
async def test_route_handles_missing_routes_key_gracefully():
    """A response missing the 'routes' key entirely must NOT crash.
    It should be treated like an empty list."""
    payload = {}  # no 'routes' key
    response = _fake_httpx_response(payload)
    client_cls = _fake_httpx_client(response)

    with patch("app.services.commute.routing.httpx.AsyncClient", client_cls):
        provider = OsrmNominatimProvider()
        with pytest.raises(RuntimeError, match="No route found"):
            await provider.route(
                Coordinate(lat=23.8, lon=90.4),
                Coordinate(lat=23.81, lon=90.41),
            )
