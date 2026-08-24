from fastapi import APIRouter, Depends, HTTPException
from firebase_admin import firestore

from app.core.auth import CurrentUser, require_student
from app.core.firebase import get_firestore
from app.schemas import ReportRequest
from app.services.permission_service import get_material_for_user, get_note_for_user

router = APIRouter()


@router.post("")
def report_content(
    body: ReportRequest,
    user: CurrentUser = Depends(require_student),
):
    if body.target_type == "material":
        target = get_material_for_user(body.target_id, user)
    else:
        target = get_note_for_user(body.target_id, user)

    if target.get("ownerId") == user.uid:
        raise HTTPException(status_code=400, detail="You cannot report your own content")

    ref = get_firestore().collection("reports").document(
        f"{user.uid}_{body.target_type}_{body.target_id}"
    )
    ref.set(
        {
            "reporterId": user.uid,
            "targetType": body.target_type,
            "targetId": body.target_id,
            "targetOwnerId": target.get("ownerId", ""),
            "reason": body.reason,
            "details": body.details.strip(),
            "status": "open",
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    return {"reported": True}
