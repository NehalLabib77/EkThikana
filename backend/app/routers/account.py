from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from firebase_admin import auth, firestore

from app.core.auth import AuthenticatedIdentity, get_verified_identity
from app.core.config import get_settings
from app.core.firebase import _ensure_firebase, get_firestore
from app.database.repositories.fare_report_repository import (
    delete_fare_reports_for_user,
)
from app.services.storage_service import (
    create_signed_url,
    delete_file,
    upload_bytes,
)

router = APIRouter()


OWNER_COLLECTIONS = [
    "semesters",
    "subjects",
    "notes",
    "tasks",
    "medicines",
    "medicine_doses",
    "bazar_items",
    "daily_expenses",
    "commute_trips",
    "financial_transactions",
]

# Legacy collections are deleted during account deletion only so old user data
# is not stranded after the LifeHub redesign. They are no longer exported or
# reachable from current Firestore rules/UI.
LEGACY_OWNER_COLLECTIONS = [
    "grocery_items",
    "family_records",
    "rent_records",
    "saved_locations",
    "wellness_records",
    "savings",  # legacy cleanup only; Gochano no longer tracks savings
]

# Collections surfaced in §29 data export. We expose owned material
# *metadata* only — never the binary file body, never any secret.
EXPORT_OWNER_COLLECTIONS = [
    "semesters",
    "subjects",
    "notes",
    "tasks",
    "medicines",
    "medicine_doses",
    "bazar_items",
    "daily_expenses",
    "commute_trips",
    "financial_transactions",
]

# Fields stripped from exported material metadata so that the JSON contains
# no signed-URL material, no file paths only the backend should know, and
# no internal counters the user could tamper with.
MATERIAL_PUBLIC_FIELDS = (
    "id",
    "title",
    "fileName",
    "mimeType",
    "sizeBytes",
    "visibility",
    "groupId",
    "university",
    "department",
    "semester",
    "subject",
    "saveCount",
    "downloadCount",
    "createdAt",
    "updatedAt",
)


def _export_value(value):
    """Convert Firestore values into JSON-serialisable primitives."""
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, (str, int, float)):
        return value
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    if isinstance(firestore.ServerTimestamp, type(None)):
        return None
    # Map
    if hasattr(value, "items"):
        return {str(k): _export_value(v) for k, v in value.items()}
    # Iterable (list / array union result)
    if hasattr(value, "__iter__") and not isinstance(value, (str, bytes)):
        return [_export_value(v) for v in value]
    return str(value)


def _delete_subcollections(doc_ref):
    for collection in doc_ref.collections():
        for snap in collection.stream():
            _delete_subcollections(snap.reference)
            snap.reference.delete()


def _remove_group_membership(uid: str):
    db = get_firestore()
    groups = db.collection("groups").where("memberIds", "array_contains", uid).stream()

    for snap in groups:
        data = snap.to_dict() or {}
        members = [x for x in data.get("memberIds", []) if x != uid]
        admins = [x for x in data.get("adminIds", []) if x != uid]

        if not members:
            snap.reference.delete()
            continue

        update = {
            "memberIds": members,
            "memberCount": len(members),
            "adminIds": admins,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }

        if data.get("ownerId") == uid:
            new_owner = admins[0] if admins else members[0]
            if new_owner not in admins:
                admins.append(new_owner)
            update["ownerId"] = new_owner
            update["adminIds"] = admins

        snap.reference.update(update)


def _delete_owned_materials(uid: str):
    db = get_firestore()
    material_ids = []

    for snap in db.collection("materials").where("ownerId", "==", uid).stream():
        data = snap.to_dict() or {}
        path = data.get("filePath")
        if path:
            try:
                delete_file(path)
            except Exception:
                # Account deletion continues so metadata/auth are not left behind
                # because of one storage-provider failure.
                pass
        material_ids.append(snap.id)
        snap.reference.delete()

    # Remove other users' saved references to files that no longer exist.
    for material_id in material_ids:
        try:
            for saved in (
                db.collection_group("saved_materials")
                .where("materialId", "==", material_id)
                .stream()
            ):
                saved.reference.delete()
        except Exception:
            pass


@router.delete("/account")
def delete_account(
    user: AuthenticatedIdentity = Depends(get_verified_identity),
):
    db = get_firestore()

    _delete_owned_materials(user.uid)
    _remove_group_membership(user.uid)

    for collection in OWNER_COLLECTIONS + LEGACY_OWNER_COLLECTIONS:
        for snap in db.collection(collection).where("ownerId", "==", user.uid).stream():
            _delete_subcollections(snap.reference)
            snap.reference.delete()

    user_ref = db.collection("users").document(user.uid)
    _delete_subcollections(user_ref)
    user_ref.delete()

    # Clean private metering/report records where practical.
    for collection in ["ai_usage", "upload_usage"]:
        for snap in db.collection(collection).where("uid", "==", user.uid).stream():
            snap.reference.delete()

    for snap in db.collection("reports").where("reporterId", "==", user.uid).stream():
        snap.reference.delete()

    # P1-5 — Wipe Postgres-mirrored fare reports authored by this user.
    # Failures here MUST NOT block account deletion: Firestore + Auth
    # already represent the user's identity, and the Postgres mirror is
    # only a community-data store. We log the failure for ops visibility.
    try:
        delete_fare_reports_for_user(user.uid)
    except Exception as exc:  # pragma: no cover - defensive
        # Use FastAPI logger when available; fall back silently so the
        # route still returns 200 with the rest of the cleanup.
        try:
            from fastapi import logger as _logger

            _logger.warning(
                "delete_fare_reports_for_user failed for uid=%s: %s",
                user.uid,
                exc,
            )
        except Exception:
            pass

    _ensure_firebase()
    auth.delete_user(user.uid)

    return {"deleted": True}


@router.get("/account/export")
def export_account(
    user: AuthenticatedIdentity = Depends(get_verified_identity),
):
    """
    Build a §29 data export containing the requesting user's accessible
    personal records as plain JSON. Never includes binary file contents,
    storage paths, secrets, or other users' data.
    """
    db = get_firestore()

    profile_snap = db.collection("users").document(user.uid).get()
    profile = profile_snap.to_dict() if profile_snap.exists else {}
    # Drop any internal-only fields before returning the profile copy.
    profile_view = {
        "uid": user.uid,
        "email": user.email,
        "displayName": profile.get("displayName", ""),
        "role": profile.get("role", ""),
        "university": profile.get("university", ""),
        "department": profile.get("department", ""),
        "semester": profile.get("semester", ""),
        "createdAt": _export_value(profile.get("createdAt")),
        "updatedAt": _export_value(profile.get("updatedAt")),
    }

    payload = {
        "app": "Gochano",
        "schemaVersion": 2,
        "exportedAt": datetime.now(timezone.utc).isoformat(),
        "profile": profile_view,
    }

    # Owned collections.
    for collection in EXPORT_OWNER_COLLECTIONS:
        docs = (
            db.collection(collection)
            .where("ownerId", "==", user.uid)
            .limit(1000)
            .stream()
        )
        payload[collection] = [
            {"id": d.id, **_export_value(d.to_dict() or {})}
            for d in docs
        ]

    # Owned material metadata — never filePath, never signed URLs.
    materials = (
        db.collection("materials")
        .where("ownerId", "==", user.uid)
        .limit(1000)
        .stream()
    )
    payload["materials"] = []
    for snap in materials:
        data = snap.to_dict() or {}
        view = {
            "id": snap.id,
            "ownerId": data.get("ownerId", ""),
            "ownerName": data.get("ownerName", ""),
        }
        for field in MATERIAL_PUBLIC_FIELDS:
            if field in data:
                view[field] = _export_value(data.get(field))
        payload["materials"].append(view)

    # Saved-material references — references only, not the originals.
    saved = (
        db.collection("users")
        .document(user.uid)
        .collection("saved_materials")
        .limit(1000)
        .stream()
    )
    payload["saved_materials"] = [
        {"id": d.id, **_export_value(d.to_dict() or {})} for d in saved
    ]

    # Group membership snapshot (names + role only — no invite codes).
    groups = (
        db.collection("groups")
        .where("memberIds", "array_contains", user.uid)
        .limit(200)
        .stream()
    )
    payload["groups"] = [
        {
            "id": g.id,
            "name": (g.to_dict() or {}).get("name", ""),
            "role": (
                "owner"
                if (g.to_dict() or {}).get("ownerId") == user.uid
                else "admin"
                if user.uid in (g.to_dict() or {}).get("adminIds", [])
                else "member"
            ),
        }
        for g in groups
    ]

    return payload


# ---------------------------------------------------------------------------
# Profile photo upload
# ---------------------------------------------------------------------------

_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


@router.post("/account/profile-photo")
async def upload_profile_photo(
    file: UploadFile = File(...),
    user: AuthenticatedIdentity = Depends(get_verified_identity),
):
    """Upload a profile photo to B2 and update the user's Firestore profile.

    The previous photo (if any) is deleted from storage. The Firestore
    document stores only the B2 storage path — a fresh signed URL is
    returned to the client so it can render the image immediately.
    """
    content_type = (file.content_type or "").lower()
    if content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=415,
            detail="Only JPEG, PNG and WebP images are accepted.",
        )

    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="File is empty")
    max_bytes = 5 * 1024 * 1024  # 5 MB cap for profile photos
    if len(raw) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail="Profile photo must be under 5 MB.",
        )

    ext = _ALLOWED_IMAGE_TYPES[content_type]
    object_path = f"users/{user.uid}/profile/{uuid4().hex}{ext}"

    db = get_firestore()
    user_ref = db.collection("users").document(user.uid)

    # Delete previous photo if it exists.
    old_data = (user_ref.get().to_dict() or {})
    old_path = old_data.get("photoPath")
    if old_path:
        try:
            delete_file(old_path)
        except Exception:
            pass  # best-effort cleanup

    try:
        upload_bytes(object_path, raw, content_type)
    except Exception as exc:
        raise HTTPException(
            status_code=502, detail=f"Photo upload failed: {exc}"
        )

    # Store the path and generate a signed URL for immediate display.
    signed_url = create_signed_url(object_path)
    user_ref.set(
        {
            "photoPath": object_path,
            "photoURL": signed_url,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    return {"photoURL": signed_url, "photoPath": object_path}


@router.get("/account/profile-photo-url")
def get_profile_photo_url(
    user: AuthenticatedIdentity = Depends(get_verified_identity),
):
    """Return a fresh signed URL for the user's profile photo.

    B2 presigned URLs expire (default 15 min). The Flutter profile screen
    calls this endpoint when the stored URL has expired.
    """
    db = get_firestore()
    user_doc = db.collection("users").document(user.uid).get()
    data = user_doc.to_dict() or {}
    photo_path = data.get("photoPath")
    if not photo_path:
        raise HTTPException(status_code=404, detail="No profile photo")

    try:
        url = create_signed_url(photo_path)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Could not sign URL: {exc}")

    # Update the cached URL in Firestore so other clients pick it up.
    db.collection("users").document(user.uid).set(
        {"photoURL": url, "updatedAt": firestore.SERVER_TIMESTAMP},
        merge=True,
    )

    return {"photoURL": url}
