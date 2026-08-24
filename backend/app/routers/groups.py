import secrets
import string

from fastapi import APIRouter, Depends, HTTPException
from firebase_admin import firestore

from app.core.auth import CurrentUser, require_student
from app.core.firebase import get_firestore
from app.schemas import GroupCreate, GroupJoin

router = APIRouter()


def _invite_code():
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(8))


@router.post("")
def create_group(
    body: GroupCreate,
    user: CurrentUser = Depends(require_student),
):
    db = get_firestore()
    ref = db.collection("groups").document()
    code = _invite_code()

    ref.set(
        {
            "name": body.name.strip(),
            "description": body.description.strip(),
            "ownerId": user.uid,
            "adminIds": [user.uid],
            "memberIds": [user.uid],
            "memberCount": 1,
            "inviteCode": code,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
    )
    return {"id": ref.id, "inviteCode": code}


@router.post("/join")
def join_group(
    body: GroupJoin,
    user: CurrentUser = Depends(require_student),
):
    db = get_firestore()
    matches = list(
        db.collection("groups")
        .where("inviteCode", "==", body.invite_code.strip().upper())
        .limit(1)
        .stream()
    )
    if not matches:
        raise HTTPException(status_code=404, detail="Invite code not found")

    snap = matches[0]
    data = snap.to_dict() or {}
    if user.uid in data.get("memberIds", []):
        return {"id": snap.id, "alreadyMember": True}

    snap.reference.update(
        {
            "memberIds": firestore.ArrayUnion([user.uid]),
            "memberCount": firestore.Increment(1),
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
    )
    return {"id": snap.id, "alreadyMember": False}


def _make_group_content_private(group_id: str):
    db = get_firestore()
    for collection in ["materials", "notes"]:
        for snap in (
            db.collection(collection)
            .where("groupId", "==", group_id)
            .where("visibility", "==", "group")
            .stream()
        ):
            snap.reference.update(
                {
                    "visibility": "private",
                    "groupId": None,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                }
            )


@router.post("/{group_id}/leave")
def leave_group(
    group_id: str,
    user: CurrentUser = Depends(require_student),
):
    db = get_firestore()
    ref = db.collection("groups").document(group_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Group not found")

    data = snap.to_dict() or {}
    members = list(data.get("memberIds", []))
    if user.uid not in members:
        raise HTTPException(status_code=400, detail="You are not a group member")

    members = [uid for uid in members if uid != user.uid]
    admins = [uid for uid in data.get("adminIds", []) if uid != user.uid]

    if not members:
        _make_group_content_private(group_id)
        ref.delete()
        return {"left": True, "groupDeleted": True}

    update = {
        "memberIds": members,
        "memberCount": len(members),
        "adminIds": admins,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }

    if data.get("ownerId") == user.uid:
        new_owner = admins[0] if admins else members[0]
        if new_owner not in admins:
            admins.append(new_owner)
        update["ownerId"] = new_owner
        update["adminIds"] = admins

    ref.update(update)
    return {"left": True, "groupDeleted": False}


@router.post("/{group_id}/invite/reset")
def reset_invite_code(
    group_id: str,
    user: CurrentUser = Depends(require_student),
):
    ref = get_firestore().collection("groups").document(group_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Group not found")

    data = snap.to_dict() or {}
    if user.uid not in data.get("adminIds", []):
        raise HTTPException(status_code=403, detail="Group admin required")

    code = _invite_code()
    ref.update(
        {
            "inviteCode": code,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
    )
    return {"inviteCode": code}
