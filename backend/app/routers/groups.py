import secrets
import string
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from firebase_admin import firestore

from app.core.auth import CurrentUser, require_student
from app.core.firebase import get_firestore
from app.schemas import (
    GroupChatMessageRequest,
    GroupChatToggleRequest,
    GroupCreate,
    GroupJoin,
)

router = APIRouter()


def _invite_code():
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(8))


def _is_member(data: dict, uid: str) -> bool:
    return uid in (data.get("memberIds") or [])


def _is_admin(data: dict, uid: str) -> bool:
    return uid in (data.get("adminIds") or [])


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


# ============================================================
# PART 3 — Group Chat (admin toggle + member-scoped messages)
# ============================================================
@router.post("/{group_id}/chat/toggle")
def toggle_chat(
    group_id: str,
    body: GroupChatToggleRequest,
    user: CurrentUser = Depends(require_student),
):
    """Admin-only. Flips chatEnabled. Denormalised to doc + admin audit log."""
    db = get_firestore()
    ref = db.collection("groups").document(group_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Group not found")
    data = snap.to_dict() or {}
    if not _is_admin(data, user.uid):
        raise HTTPException(status_code=403, detail="Group admin required")

    ref.update(
        {
            "chatEnabled": bool(body.chat_enabled),
            "chatToggledAt": firestore.SERVER_TIMESTAMP,
            "chatToggledBy": user.uid,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
    )
    return {
        "groupId": group_id,
        "chatEnabled": bool(body.chat_enabled),
        "toggledBy": user.uid,
    }


@router.get("/{group_id}/chat")
def list_chat_messages(
    group_id: str,
    limit: int = 50,
    user: CurrentUser = Depends(require_student),
):
    """Member-only read; paginated, latest first, restricted to members of the group."""
    if limit < 1 or limit > 100:
        raise HTTPException(status_code=400, detail="limit must be 1..100")
    db = get_firestore()
    group_ref = db.collection("groups").document(group_id)
    snap = group_ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Group not found")
    data = snap.to_dict() or {}
    if not _is_member(data, user.uid):
        raise HTTPException(status_code=403, detail="Members only")

    rows = (
        db.collection("group_messages")
        .where("groupId", "==", group_id)
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .limit(limit)
        .stream()
    )
    out = []
    for r in rows:
        d = r.to_dict() or {}
        out.append(
            {
                "id": r.id,
                "senderId": d.get("senderId"),
                "senderName": d.get("senderName"),
                "text": d.get("text", ""),
                "attachmentUrl": d.get("attachmentUrl"),
                "attachmentFilename": d.get("attachmentFilename"),
                "attachmentMime": d.get("attachmentMime"),
                "attachmentSize": d.get("attachmentSize"),
                "createdAt": (d.get("createdAt").isoformat()
                              if hasattr(d.get("createdAt"), "isoformat")
                              else None),
            }
        )
    return {"groupId": group_id, "chatEnabled": bool(data.get("chatEnabled", False)), "messages": out}


@router.post("/{group_id}/chat")
def post_chat_message(
    group_id: str,
    body: GroupChatMessageRequest,
    user: CurrentUser = Depends(require_student),
):
    """Member-only post; allowed ONLY when chatEnabled=true.

    Either text or attachment must be non-empty. Allowed attachment mime
    types are restricted to image/*, application/pdf, application/msword,
    application/vnd.openxmlformats-officedocument.wordprocessingml.document.
    """
    db = get_firestore()
    group_ref = db.collection("groups").document(group_id)
    snap = group_ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Group not found")
    data = snap.to_dict() or {}
    if not _is_member(data, user.uid):
        raise HTTPException(status_code=403, detail="Members only")
    if not bool(data.get("chatEnabled", False)):
        raise HTTPException(status_code=403, detail="Chat is disabled for this group")

    text = body.text.strip()
    has_attachment = bool(
        body.attachment_url and body.attachment_filename
    )

    # Validate attachment mime BEFORE the empty-payload check so callers get a
    # precise 415 rather than a misleading 400 when they attach the wrong type.
    if has_attachment:
        mime = (body.attachment_mime or "").lower()
        ok = (
            mime.startswith("image/")
            or mime in {"application/pdf", "application/msword"}
            or mime
            == "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        )
        if not ok:
            raise HTTPException(
                status_code=415,
                detail="Attachment type not allowed for group chat",
            )

    if not text and not has_attachment:
        raise HTTPException(status_code=400, detail="Message is empty")

    now = datetime.now(timezone.utc)
    msg_ref = db.collection("group_messages").document()
    msg_ref.set(
        {
            "groupId": group_id,
            "senderId": user.uid,
            "senderName": user.display_name or "",
            "text": text,
            "attachmentUrl": body.attachment_url if has_attachment else None,
            "attachmentFilename": body.attachment_filename if has_attachment else None,
            "attachmentMime": body.attachment_mime if has_attachment else None,
            "attachmentSize": body.attachment_size if has_attachment else None,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "createdAtIso": now.isoformat(),
        }
    )
    return {
        "id": msg_ref.id,
        "groupId": group_id,
        "senderId": user.uid,
        "senderName": user.display_name or "",
        "text": text,
        "attachment": {
            "url": body.attachment_url if has_attachment else None,
            "filename": body.attachment_filename if has_attachment else None,
            "mime": body.attachment_mime if has_attachment else None,
            "size": body.attachment_size if has_attachment else None,
        },
        "createdAtIso": now.isoformat(),
    }
