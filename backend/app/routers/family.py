# Phase 7 — family links (spec §7.7, architecture only: no UI exists).
#
# A student issues a one-time link code; a parent/guardian account
# (``role == "general"``) redeems it. The payload is deliberately thin —
# ids, names and status only. No scores, no exams, no mistakes: a parent
# view will request progress explicitly in a later phase, behind its own
# permission check.
#
# ``/api/family`` is intentionally NOT in STUDENT_ONLY_PREFIXES: the
# redeeming side is a parent, not a student. Both routes still require a
# verified Firebase identity, and the service enforces which role may
# create a code (student) versus redeem one (general).

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.core.auth import CurrentUser, get_current_user
from app.schemas import _CamelModel
from app.services import community_service as community
from app.services.community_service import CommunityError

router = APIRouter()


class FamilyRedeemRequest(_CamelModel):
    code: str = ""


def _raise(exc: CommunityError) -> None:
    raise HTTPException(status_code=exc.status, detail=exc.detail)


@router.post("/link-code")
def create_family_code(
    user: CurrentUser = Depends(get_current_user),
):
    """Student side: issue the one-time code a parent will redeem."""
    try:
        return community.create_family_code(
            user.uid, user.role, user.display_name
        )
    except CommunityError as exc:
        _raise(exc)


@router.post("/link/redeem")
def redeem_family_code(
    body: FamilyRedeemRequest,
    user: CurrentUser = Depends(get_current_user),
):
    """Parent side: redeem a student's code and create the link."""
    try:
        return community.redeem_family_code(
            user.uid, user.role, user.display_name, body.code
        )
    except CommunityError as exc:
        _raise(exc)


@router.get("/links")
def list_family_links(
    user: CurrentUser = Depends(get_current_user),
):
    """Both sides see the link — and nothing about the child's scores."""
    try:
        return community.list_family_links(user.uid)
    except CommunityError as exc:
        _raise(exc)
