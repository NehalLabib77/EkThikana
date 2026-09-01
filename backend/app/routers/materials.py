import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from firebase_admin import firestore
from pydantic import BaseModel, Field

from app.core.auth import CurrentUser, require_student
from app.core.config import get_settings
from app.core.firebase import get_firestore
from app.core.utils import detect_supported_file_type, keywords, safe_filename
from app.services.permission_service import get_material_for_user
from app.services import storage_provider
from app.services.storage_service import delete_file, upload_bytes

router = APIRouter()


class MaterialUpdate(BaseModel):
    """Owner-only metadata edit payload.

    `description` follows a three-state sentinel: omitted (no change),
    empty-string (clear), non-empty (replace). This matches the Flutter
    `ApiService.updateMaterial` contract where ``null`` means "clear".
    """

    title: str | None = Field(default=None, max_length=200)
    subject: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=1000)


class MaterialReplaceResult(BaseModel):
    id: str
    version: int
    filePath: str
    fileName: str
    mimeType: str
    sizeBytes: int


def _get_material_owned_by(material_id: str, user: CurrentUser) -> dict:
    """Owner-only material lookup. Returns the doc data or raises 404/403.

    Distinct from `get_material_for_user`, which lets group members read a
    material. Mutations (edit metadata, replace file, delete) are stricter.
    """
    snap = get_firestore().collection("materials").document(material_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Material not found")
    data = snap.to_dict() or {}
    if data.get("ownerId") != user.uid:
        raise HTTPException(
            status_code=403,
            detail="Only the owner can modify this material",
        )
    data["id"] = snap.id
    return data


def _check_storage_quota(uid: str, new_size: int):
    settings = get_settings()
    limit = settings.user_storage_limit_mb * 1024 * 1024
    current = 0
    for snap in (
        get_firestore()
        .collection("materials")
        .where("ownerId", "==", uid)
        .stream()
    ):
        current += int((snap.to_dict() or {}).get("sizeBytes", 0) or 0)

    if current + new_size > limit:
        raise HTTPException(
            status_code=413,
            detail=f"Your Gochano file quota is {settings.user_storage_limit_mb} MB",
        )


def _consume_upload_quota(uid: str):
    settings = get_settings()
    if settings.upload_daily_limit <= 0:
        return

    day = datetime.now(timezone.utc).strftime("%Y%m%d")
    ref = get_firestore().collection("upload_usage").document(f"{uid}_{day}")
    tx = get_firestore().transaction()

    @firestore.transactional
    def bump(transaction):
        snap = ref.get(transaction=transaction)
        count = int((snap.to_dict() or {}).get("count", 0)) if snap.exists else 0
        if count >= settings.upload_daily_limit:
            raise HTTPException(
                status_code=429,
                detail="Daily upload limit reached",
            )
        transaction.set(
            ref,
            {
                "uid": uid,
                "day": day,
                "count": count + 1,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    bump(tx)


@router.post("/upload")
async def upload_material(
    file: UploadFile = File(...),
    title: str = Form(...),
    visibility: str = Form("private"),
    group_id: str = Form(""),
    university: str = Form(""),
    department: str = Form(""),
    semester: str = Form(""),
    subject: str = Form(""),
    user: CurrentUser = Depends(require_student),
):
    if visibility not in {"private", "group", "public"}:
        raise HTTPException(status_code=400, detail="Invalid visibility")
    if visibility == "public":
        raise HTTPException(
            status_code=400,
            detail="Public materials are not supported in this build.",
        )
    if not title.strip() or len(title.strip()) > 200:
        raise HTTPException(status_code=400, detail="Title must be 1–200 characters")

    db = get_firestore()

    group_id = group_id.strip()
    if visibility == "group":
        if not group_id:
            raise HTTPException(status_code=400, detail="group_id is required")
        group = db.collection("groups").document(group_id).get()
        if not group.exists or user.uid not in (group.to_dict() or {}).get("memberIds", []):
            raise HTTPException(status_code=403, detail="You are not a group member")
    else:
        group_id = ""

    raw = await file.read()
    max_bytes = get_settings().max_upload_mb * 1024 * 1024
    if not raw:
        raise HTTPException(status_code=400, detail="File is empty")
    if len(raw) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"Maximum file size is {get_settings().max_upload_mb} MB",
        )

    try:
        mime, safe_ext = detect_supported_file_type(raw)
    except ValueError as exc:
        raise HTTPException(status_code=415, detail=str(exc))

    _check_storage_quota(user.uid, len(raw))
    _consume_upload_quota(user.uid)

    original = safe_filename(file.filename or "material")
    base = original.rsplit(".", 1)[0] if "." in original else original
    filename = f"{base}{safe_ext}"
    object_path = f"users/{user.uid}/{uuid.uuid4().hex}_{filename}"

    try:
        upload_bytes(object_path, raw, mime)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"File storage upload failed: {exc}")

    ref = db.collection("materials").document()
    try:
        ref.set(
            {
                "ownerId": user.uid,
                "ownerName": user.display_name,
                "title": title.strip(),
                "fileName": filename,
                "filePath": object_path,
                # Stated at write time so no read ever has to work it out.
                storage_provider.FIELD: storage_provider.B2,
                "mimeType": mime,
                "sizeBytes": len(raw),
                "visibility": visibility,
                "groupId": group_id or None,
                "university": university.strip()[:120],
                "department": department.strip()[:120],
                "semester": semester.strip()[:80],
                "subject": subject.strip()[:120],
                "keywords": keywords(
                    " ".join(
                        [
                            title,
                            filename,
                            university,
                            department,
                            semester,
                            subject,
                        ]
                    )
                ),
                "saveCount": 0,
                "downloadCount": 0,
                "createdAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }
        )
    except Exception:
        try:
            delete_file(object_path)
        except Exception:
            pass
        raise

    return {"id": ref.id}


@router.get("/{material_id}/url")
def material_url(
    material_id: str,
    download: bool = False,
    user: CurrentUser = Depends(require_student),
):
    data = get_material_for_user(material_id, user)

    # While the Firebase-to-B2 migration is in flight a file may be in either
    # bucket, so the record says which and that statement is honoured. Trying
    # B2 and silently falling back would hide a real B2 outage behind a slow
    # success, and hide an incomplete migration behind an apparent one.
    resolved = storage_provider.resolve(data)
    if resolved.missing:
        raise HTTPException(status_code=404, detail="This file is no longer available")

    url = storage_provider.signed_url_for(resolved, download=download)
    if not url:
        raise HTTPException(status_code=502, detail="Could not create signed URL")

    if resolved.should_persist:
        # Worked out by probing. Record it so no later read has to probe.
        try:
            get_firestore().collection("materials").document(material_id).update(
                {storage_provider.FIELD: resolved.provider}
            )
        except Exception:
            # Losing the label costs one probe next time, not correctness.
            pass

    if download:
        get_firestore().collection("materials").document(material_id).update(
            {"downloadCount": firestore.Increment(1)}
        )
    return {
        "url": url,
        "expiresIn": get_settings().signed_url_ttl_seconds,
    }


@router.post("/{material_id}/save")
def save_material(
    material_id: str,
    user: CurrentUser = Depends(require_student),
):
    data = get_material_for_user(material_id, user)
    ref = (
        get_firestore()
        .collection("users")
        .document(user.uid)
        .collection("saved_materials")
        .document(material_id)
    )

    existing = ref.get()
    if not existing.exists:
        ref.set(
            {
                "materialId": material_id,
                "title": data.get("title", ""),
                "fileName": data.get("fileName", ""),
                "ownerId": data.get("ownerId", ""),
                "savedAt": firestore.SERVER_TIMESTAMP,
            }
        )
        get_firestore().collection("materials").document(material_id).update(
            {"saveCount": firestore.Increment(1)}
        )
    return {"saved": True}


@router.delete("/{material_id}")
def delete_material(
    material_id: str,
    user: CurrentUser = Depends(require_student),
):
    db = get_firestore()
    snap = db.collection("materials").document(material_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Material not found")

    data = snap.to_dict() or {}
    if data.get("ownerId") != user.uid:
        raise HTTPException(
            status_code=403,
            detail="Only the owner can delete this material",
        )

    try:
        delete_file(data["filePath"])
    finally:
        snap.reference.delete()

    return {"deleted": True}


@router.patch("/{material_id}", response_model=MaterialUpdate)
def update_material(
    material_id: str,
    payload: MaterialUpdate,
    user: CurrentUser = Depends(require_student),
):
    """Owner-only metadata edit.

    `title` and `subject` follow standard "omitted = unchanged" semantics.
    `description` accepts an empty string to clear the field; null is treated
    as a no-op (so existing Flutter callers that pass `null` to clear see a
    concrete cleared value rather than a Pydantic coercion error).
    """
    data = _get_material_owned_by(material_id, user)

    updates: dict = {}
    if payload.title is not None:
        title = payload.title.strip()
        if not title or len(title) > 200:
            raise HTTPException(
                status_code=400,
                detail="Title must be 1–200 characters",
            )
        updates["title"] = title
        updates["keywords"] = keywords(
            " ".join(
                [
                    title,
                    data.get("fileName", ""),
                    data.get("university", ""),
                    data.get("department", ""),
                    data.get("semester", ""),
                    data.get("subject", ""),
                ]
            )
        )

    if payload.subject is not None:
        updates["subject"] = payload.subject.strip()[:120]

    if payload.description is not None:
        # empty string clears; non-empty replaces
        updates["description"] = payload.description.strip()[:1000]

    if not updates:
        # Nothing to write - return current values so the Flutter caller can
        # round-trip a no-op without forcing a re-render.
        return MaterialUpdate(
            title=data.get("title"),
            subject=data.get("subject"),
            description=data.get("description"),
        )

    updates["updatedAt"] = firestore.SERVER_TIMESTAMP
    get_firestore().collection("materials").document(material_id).update(updates)

    return MaterialUpdate(
        title=updates.get("title", data.get("title")),
        subject=updates.get("subject", data.get("subject")),
        description=updates.get("description", data.get("description")),
    )


@router.put("/{material_id}/file", response_model=MaterialReplaceResult)
async def replace_material_file(
    material_id: str,
    file: UploadFile = File(...),
    user: CurrentUser = Depends(require_student),
):
    """Owner-only file replacement. Same `material_id`; new object path.

    Behavioural contract (mirrored in Flutter `ApiService.replaceMaterialFile`):
      - The Firestore `id` does not change - saved references and share links
        survive.
      - The Storage object path rotates to a new uuid-prefixed filename so
        any in-flight downloads of the old object remain valid until their
        signed URL expires (15 min TTL).
      - `version` is incremented by 1 on success and persisted alongside the
        new `filePath`, `fileName`, `mimeType`, `sizeBytes`, and `updatedAt`.
      - If the Firestore metadata write fails after the new object is uploaded
        the new object is rolled back so storage does not leak.
    """
    data = _get_material_owned_by(material_id, user)

    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="File is empty")

    max_bytes = get_settings().max_upload_mb * 1024 * 1024
    if len(raw) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"Maximum file size is {get_settings().max_upload_mb} MB",
        )

    try:
        mime, safe_ext = detect_supported_file_type(raw)
    except ValueError as exc:
        raise HTTPException(status_code=415, detail=str(exc))

    # Quota check: replacing frees the old size and reserves the new size,
    # so the net delta is (new_size - old_size). The check already iterates
    # over the user's materials in Firestore.
    _check_storage_quota(user.uid, max(0, len(raw) - int(data.get("sizeBytes", 0) or 0)))
    _consume_upload_quota(user.uid)

    original = safe_filename(file.filename or data.get("fileName") or "material")
    base = original.rsplit(".", 1)[0] if "." in original else original
    filename = f"{base}{safe_ext}"
    new_path = f"users/{user.uid}/{uuid.uuid4().hex}_{filename}"
    old_path = data.get("filePath")

    try:
        upload_bytes(new_path, raw, mime)
    except Exception as exc:
        raise HTTPException(
            status_code=502, detail=f"File storage upload failed: {exc}"
        )

    new_version = int(data.get("version", 1) or 1) + 1
    try:
        get_firestore().collection("materials").document(material_id).update(
            {
                "filePath": new_path,
                storage_provider.FIELD: storage_provider.B2,
                "fileName": filename,
                "mimeType": mime,
                "sizeBytes": len(raw),
                "version": new_version,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }
        )
    except Exception:
        # Roll back the freshly uploaded object so storage does not leak.
        try:
            delete_file(new_path)
        except Exception:
            pass
        raise

    # Best-effort: drop the old object now that the metadata swap is durable.
    # A failure here is non-fatal - the old object just becomes orphaned and
    # is cleaned up by the storage janitor / account-delete path.
    if old_path and old_path != new_path:
        try:
            delete_file(old_path)
        except Exception:
            pass

    return MaterialReplaceResult(
        id=material_id,
        version=new_version,
        filePath=new_path,
        fileName=filename,
        mimeType=mime,
        sizeBytes=len(raw),
    )
