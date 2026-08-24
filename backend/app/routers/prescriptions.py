from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.core.auth import CurrentUser, get_current_user
from app.core.config import get_settings
from app.services.ocr_service import candidate_lines, extract_text

router = APIRouter()


@router.post("/extract")
async def extract_prescription(
    file: UploadFile = File(...),
    user: CurrentUser = Depends(get_current_user),
):
    raw = await file.read()
    max_bytes = get_settings().max_upload_mb * 1024 * 1024
    if not raw:
        raise HTTPException(status_code=400, detail="File is empty")
    if len(raw) > max_bytes:
        raise HTTPException(status_code=413, detail="File is too large")

    content_type = file.content_type or ""
    try:
        text = extract_text(raw, content_type)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"OCR could not read this file: {exc}")

    return {
        "rawText": text,
        "candidateLines": candidate_lines(text),
        "warning": "OCR can be wrong. Confirm medicine name, dose/instructions and schedule before saving.",
    }
