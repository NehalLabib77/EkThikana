import base64

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.core.auth import CurrentUser, require_student
from app.core.config import get_settings
from app.schemas import AiNoteRequest, PdfQuestionRequest
from app.services.ai_service import generate, generate_multimodal
from app.services.pdf_service import extract_pdf_text
from app.services.ocr_service import extract_text as ocr_extract_text
from app.services.permission_service import get_material_for_user
from app.services import storage_provider
from app.services.storage_service import download_bytes

router = APIRouter()


# ---------------------------------------------------------------------------
# Image question (Gemini Vision). Supports PNG / JPEG / JPG / WEBP images.
# Accepts an existing material id so that we keep the same auth + storage
# download path as the PDF flow, and the same daily-quota gate.
# ---------------------------------------------------------------------------
_ALLOWED_IMAGE_MIME = {
    "image/png",
    "image/jpeg",
    "image/jpg",
    "image/webp",
}
_ALLOWED_IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp"}


class ImageQuestionRequest(BaseModel):
    material_id: str = Field(..., min_length=1)
    question: str = Field(..., min_length=1, max_length=2000)


def _is_image(material: dict) -> bool:
    mime = (material.get("mimeType") or "").lower()
    if mime in _ALLOWED_IMAGE_MIME:
        return True
    name = (material.get("fileName") or "").lower()
    return any(name.endswith(ext) for ext in _ALLOWED_IMAGE_EXT)


@router.post("/note")
async def process_note(
    body: AiNoteRequest,
    user: CurrentUser = Depends(require_student),
):
    instructions = {
        "cleanup": "Clean up the following study note. Preserve meaning. Improve structure and clarity. Do not invent facts.",
        "summary": "Summarize the following study note concisely while preserving the key concepts.",
        "explain": "Explain the following study note clearly for a university student. Do not create quiz questions.",
        "key_topics": "Extract the key study topics from the following note as a concise structured list. Do not create questions or MCQs.",
    }
    prompt = f"{instructions[body.action]}\n\nNOTE:\n{body.text}"
    result = await generate(user.uid, prompt)
    return {"result": result}


@router.post("/pdf-question")
async def pdf_question(
    body: PdfQuestionRequest,
    user: CurrentUser = Depends(require_student),
):
    material = get_material_for_user(body.material_id, user)
    if "pdf" not in (material.get("mimeType") or "").lower() and not material.get("fileName", "").lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Material is not a PDF")

    raw = _material_bytes(material)
    mime_type = material.get("mimeType") or "application/pdf"
    try:
        text = extract_pdf_text(raw, page=body.page)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # Scanned PDF fallback: if the digital extractor returned nothing useful,
    # delegate to the OCR pipeline (already shared with /api/prescriptions/extract).
    if len(text.strip()) < 40:
        try:
            text = ocr_extract_text(raw, mime_type)
        except Exception:
            # OCR failures should not mask a usable digital extract; if both
            # paths produced nothing, surface a 422 below.
            text = text or ""

    if not text.strip():
        raise HTTPException(status_code=422, detail="No extractable PDF text was found")

    scope = f"page {body.page}" if body.page else "the supplied PDF text"
    prompt = (
        f"Answer the user's study question using only {scope}. "
        "If the answer is not supported by the text, say that clearly. "
        "Do not generate practice questions or MCQs.\n\n"
        f"QUESTION:\n{body.question}\n\n"
        f"PDF TEXT:\n{text}"
    )
    answer = await generate(user.uid, prompt)
    return {"answer": answer}


@router.post("/image-question")
async def image_question(
    body: ImageQuestionRequest,
    user: CurrentUser = Depends(require_student),
):
    material = get_material_for_user(body.material_id, user)
    if not _is_image(material):
        raise HTTPException(
            status_code=400,
            detail="Material is not a supported image (PNG, JPEG, WEBP)",
        )

    # Defensive size cap. Inline data is sent in the JSON body to Gemini, and
    # an oversized image both wastes quota and risks 413 from the upstream.
    settings = get_settings()
    max_bytes = max(1, int(getattr(settings, "ai_image_max_bytes", 6 * 1024 * 1024)))
    raw = _material_bytes(material)
    if not raw:
        raise HTTPException(status_code=422, detail="Empty image")
    if len(raw) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"Image is too large ({len(raw)} bytes). Max {max_bytes}.",
        )

    mime = (material.get("mimeType") or "").lower()
    if mime not in _ALLOWED_IMAGE_MIME:
        # Fall back to extension when the upload did not record a MIME.
        name = (material.get("fileName") or "").lower()
        if name.endswith(".png"):
            mime = "image/png"
        elif name.endswith(".webp"):
            mime = "image/webp"
        else:
            mime = "image/jpeg"

    parts = [
        {
            "inline_data": {
                "mime_type": mime,
                "data": base64.b64encode(raw).decode("ascii"),
            }
        },
        {
            "text": (
                "You are a study assistant. Read the supplied image and answer "
                "the user's question using only what is visible in the image. "
                "If the answer cannot be determined from the image, say that "
                "clearly. Do not invent values.\n\n"
                f"QUESTION:\n{body.question}"
            )
        },
    ]
    answer = await generate_multimodal(user.uid, parts)
    return {"answer": answer}


def _material_bytes(material: dict) -> bytes:
    """Fetch a material's bytes from whichever bucket the record names.

    Raises rather than returning empty bytes: an unreadable file must not
    reach the model as an empty document, which would produce a confident
    answer about nothing.
    """
    resolved = storage_provider.resolve(material)
    if resolved.missing:
        raise HTTPException(status_code=404, detail="This file is no longer available")
    data = storage_provider.download_for(resolved)
    if data is None:
        raise HTTPException(status_code=502, detail="Could not read this file")
    return data
