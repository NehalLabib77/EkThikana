from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.core.auth import CurrentUser, get_current_user
from app.core.config import get_settings
from app.core.utils import detect_supported_file_type
from app.services.ocr_service import candidate_lines, extract_text, parse_medicine_candidates

router = APIRouter()


@router.post("/extract")
async def extract_prescription(
    file: UploadFile = File(...),
    user: CurrentUser = Depends(get_current_user),
):
    raw = await file.read()
    max_bytes = min(get_settings().max_upload_mb, 10) * 1024 * 1024
    if not raw:
        raise HTTPException(status_code=400, detail="File is empty")
    if len(raw) > max_bytes:
        raise HTTPException(status_code=413, detail="Prescription file must be 10 MB or smaller")

    try:
        mime, _ = detect_supported_file_type(raw)
    except ValueError as exc:
        raise HTTPException(status_code=415, detail=str(exc)) from exc

    try:
        text = extract_text(raw, mime)
    except Exception as exc:
        # Keep the client response JSON so Flutter can show the real error.
        raise HTTPException(
            status_code=422,
            detail=f"OCR could not read this prescription. Try a clearer, well-lit image. ({type(exc).__name__})",
        ) from exc

    medicines = parse_medicine_candidates(text)
    return {
        "rawText": text,
        "candidateLines": candidate_lines(text),
        "medicines": medicines,
        "warning": (
            "OCR can be wrong. EkThikana does not prescribe or infer a medical schedule. "
            "Confirm medicine name, dose/instructions and actual reminder times before saving."
        ),
    }
