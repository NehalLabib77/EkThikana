from fastapi import HTTPException

from app.core.auth import CurrentUser
from app.core.firebase import get_firestore


def get_material_for_user(material_id: str, user: CurrentUser) -> dict:
    snap = get_firestore().collection("materials").document(material_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Material not found")

    data = snap.to_dict() or {}
    data["id"] = snap.id

    if data.get("ownerId") == user.uid:
        return data

    if user.role != "student":
        raise HTTPException(status_code=403, detail="Student account required")

    visibility = data.get("visibility", "private")
    if visibility == "public":
        return data

    if visibility == "group":
        group_id = data.get("groupId")
        if group_id:
            group = get_firestore().collection("groups").document(group_id).get()
            if group.exists and user.uid in (group.to_dict() or {}).get("memberIds", []):
                return data

    raise HTTPException(status_code=403, detail="You do not have access to this material")


def get_note_for_user(note_id: str, user: CurrentUser) -> dict:
    snap = get_firestore().collection("notes").document(note_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Note not found")

    data = snap.to_dict() or {}
    data["id"] = snap.id

    if data.get("ownerId") == user.uid:
        return data

    if user.role != "student":
        raise HTTPException(status_code=403, detail="Student account required")

    visibility = data.get("visibility", "private")
    if visibility == "public":
        return data

    if visibility == "group":
        group_id = data.get("groupId")
        if group_id:
            group = get_firestore().collection("groups").document(group_id).get()
            if group.exists and user.uid in (group.to_dict() or {}).get("memberIds", []):
                return data

    raise HTTPException(status_code=403, detail="You do not have access to this note")
