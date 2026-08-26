import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from firebase_admin import firestore

from app.core.auth import CurrentUser, require_student
from app.core.config import get_settings
from app.core.firebase import get_firestore
from app.core.utils import detect_supported_file_type, keywords, safe_filename
from app.services.permission_service import get_material_for_user
from app.services.storage_service import create_signed_url, delete_file, upload_bytes

router = APIRouter()


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
    url = create_signed_url(data["filePath"], download=download)
    if not url:
        raise HTTPException(status_code=502, detail="Could not create signed URL")

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
