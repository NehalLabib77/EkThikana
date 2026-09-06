"""Telecom auth exchange — mints a Firebase custom token.

SECURITY CONTRACT:
  The client-supplied `already_subscribed`, `subscription_status`, and
  `reference_no` are IGNORED. This endpoint independently verifies the
  phone's subscription status with bdApps (the carrier) server-to-server
  BEFORE minting any Firebase custom token.

  Only phones whose subscriptionStatus is REGISTERED or INITIAL CHARGING
  PENDING (as confirmed by bdApps) receive a token. All other statuses
  are rejected with 403.

Flow:
  Flutter → POST /v1/auth/telecom/exchange {"phone": "018..."}
  → Render independently calls bdApps check_subscription.php
  → REGISTERED / INITIAL CHARGING PENDING confirmed
  → deterministic Firebase UID telecom:<phone>
  → Firebase custom token with email_verified=true
  → Flutter signInWithCustomToken() → Home
"""

import logging
import re

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.firebase import _ensure_firebase

logger = logging.getLogger("gochano.telecom")

router = APIRouter()

BDAPPS_BASE_URL = "https://www.bdappsdigitalapps.com/NADB26122_Final"
CHECK_SUBSCRIPTION_URL = f"{BDAPPS_BASE_URL}/check_subscription.php"
CHECK_SUBSCRIPTION_TIMEOUT = 10  # seconds

# Phone normalization: must match Flutter's TelecomAuthService.normalize()
_PHONE_RE = re.compile(r"^01(?:6|8)\d{8}$")


def _normalize_phone(raw: str) -> str:
    """Strip spaces, dashes, and country code to produce a bare 11-digit
    Bangladeshi number (016xxxxxxx or 018xxxxxxx)."""
    p = raw.strip().replace(" ", "").replace("-", "")
    if p.startswith("+880"):
        p = "0" + p[4:]
    elif p.startswith("880"):
        p = "0" + p[3:]
    return p


def _is_supported_phone(phone: str) -> bool:
    return bool(_PHONE_RE.match(phone))


class ExchangeRequest(BaseModel):
    phone: str
    # The following fields are accepted for API compatibility but are
    # NEVER trusted or used. The backend independently verifies the
    # subscription status with bdApps.
    already_subscribed: bool | None = None
    subscription_status: str | None = None
    reference_no: str | None = None


class ExchangeResponse(BaseModel):
    firebase_custom_token: str
    uid: str


async def _verify_subscription_with_bdapps(phone: str) -> str | None:
    """Call bdApps check_subscription.php server-to-server.

    Returns the normalised subscriptionStatus if the call succeeds,
    or None on any error. Never raises — errors are logged and
    treated as "not subscribed" (safe default).
    """
    try:
        async with httpx.AsyncClient(timeout=CHECK_SUBSCRIPTION_TIMEOUT) as client:
            resp = await client.post(
                CHECK_SUBSCRIPTION_URL,
                data={"user_mobile": phone},
            )
            if resp.status_code < 200 or resp.status_code >= 300:
                logger.warning(
                    "bdApps check_subscription returned HTTP %d for phone=%s",
                    resp.status_code,
                    phone,
                )
                return None
            body = resp.json()
            status = (
                body.get("subscriptionStatus", "")
                if isinstance(body, dict)
                else ""
            )
            return status.strip() if isinstance(status, str) else ""
    except Exception:
        logger.exception("Failed to reach bdApps for phone=%s", phone)
        return None


def _normalise_status(raw: str) -> str:
    """Collapse whitespace/hyphens/underscores, trim, uppercase —
    matching the Flutter client's _normalizeSubscriptionStatus()."""
    return re.sub(r"[\s\-_]+", " ", raw).strip().upper()


@router.post("/exchange", response_model=ExchangeResponse)
async def exchange(req: ExchangeRequest):
    """Verify subscription with bdApps, then mint a Firebase custom token.

    SECURITY: client-supplied already_subscribed / subscription_status /
    reference_no are ignored. The backend calls bdApps directly to
    confirm the phone's subscription status.
    """
    phone = _normalize_phone(req.phone or "")
    if not _is_supported_phone(phone):
        raise HTTPException(
            status_code=400,
            detail="Only Robi (016) and Cirkle (018) numbers are supported",
        )

    logger.info("telecom exchange: phone=%s — verifying with bdApps", phone)

    # --- Server-to-server verification with bdApps ---
    raw_status = await _verify_subscription_with_bdapps(phone)
    if raw_status is None:
        logger.warning("telecom exchange: bdApps unreachable for phone=%s", phone)
        raise HTTPException(
            status_code=502,
            detail="Could not verify subscription with carrier. Please try again.",
        )

    normalised = _normalise_status(raw_status)
    logger.info(
        "telecom exchange: phone=%s bdApps subscriptionStatus=%r (normalised=%r)",
        phone,
        raw_status,
        normalised,
    )

    if normalised != "REGISTERED" and "INITIAL CHARGING PENDING" not in normalised:
        logger.warning(
            "telecom exchange: REJECTED phone=%s status=%r — not REGISTERED/PENDING",
            phone,
            normalised,
        )
        raise HTTPException(
            status_code=403,
            detail="Subscription not active. Please subscribe or contact support.",
        )

    # --- bdApps confirmed active subscription — mint Firebase token ---
    _ensure_firebase()
    from firebase_admin import auth as firebase_auth

    uid = f"telecom:{phone}"

    # Ensure the Firebase Auth user exists (create if missing).
    try:
        firebase_auth.get_user(uid)
    except firebase_auth.UserNotFoundError:
        firebase_auth.create_user(uid=uid)
        logger.info("Created Firebase Auth user uid=%s", uid)

    custom_token = firebase_auth.create_custom_token(
        uid,
        developer_claims={"email_verified": True},
    )
    if isinstance(custom_token, bytes):
        custom_token = custom_token.decode("utf-8")

    logger.info(
        "telecom exchange: SUCCESS phone=%s uid=%s token_len=%d",
        phone,
        uid,
        len(custom_token),
    )

    return ExchangeResponse(
        firebase_custom_token=custom_token,
        uid=uid,
    )
