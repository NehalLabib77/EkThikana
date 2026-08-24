from dataclasses import dataclass
from typing import Optional

from fastapi import Depends, Header, HTTPException, status
from firebase_admin import auth

from app.core.firebase import _ensure_firebase, get_firestore


@dataclass(frozen=True)
class AuthenticatedIdentity:
    uid: str
    email: str


@dataclass(frozen=True)
class CurrentUser:
    uid: str
    email: str
    role: str
    display_name: str = ""


async def get_verified_identity(
    authorization: Optional[str] = Header(default=None),
) -> AuthenticatedIdentity:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Firebase ID token",
        )

    token = authorization.split(" ", 1)[1].strip()
    try:
        _ensure_firebase()
        decoded = auth.verify_id_token(token, check_revoked=True)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase ID token",
        )

    if not decoded.get("email_verified", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email verification is required",
        )

    return AuthenticatedIdentity(
        uid=decoded["uid"],
        email=decoded.get("email", ""),
    )


async def get_current_user(
    identity: AuthenticatedIdentity = Depends(get_verified_identity),
) -> CurrentUser:
    profile = get_firestore().collection("users").document(identity.uid).get()
    if not profile.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User profile is missing",
        )

    data = profile.to_dict() or {}
    role = data.get("role")
    if role not in {"student", "general"}:
        raise HTTPException(status_code=403, detail="Invalid user role")

    return CurrentUser(
        uid=identity.uid,
        email=identity.email,
        role=role,
        display_name=data.get("displayName", ""),
    )


async def require_student(
    user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    if user.role != "student":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Student account required",
        )
    return user
