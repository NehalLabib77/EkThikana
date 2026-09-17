import base64

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.core.auth import CurrentUser, require_student
from app.core.config import get_settings
from app.schemas import AiNoteRequest, PdfQuestionRequest, CommuteGuideRequest
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


# ---------------------------------------------------------------------------
# Commute — Smart Journey Guide explanation.
#
# Accepts structured verified journey facts and returns a concise,
# human-readable explanation. AI must NOT invent any route, stop, bus,
# fare, or time data — it only explains what the facts already contain.
# ---------------------------------------------------------------------------

_SYSTEM_INSTRUCTION = """\
You are explaining a verified commute route for a student commute app in Dhaka, Bangladesh.

Use ONLY the supplied journey facts. Be concise — 2-3 short sentences maximum.

CRITICAL RULES — STRICT GROUNDING:
- You are explanation only. You do NOT generate routes, stops, or schedules.
- Every sentence you write must be directly supported by a fact in the JOURNEY FACTS section.
- If a fact is absent from the facts, you MUST NOT mention it. Omit entirely.
- NEVER invent: road names, bus names, bus numbers, routes, stops, stations, transfer points, fares, travel time, traffic conditions, route segments, schedules, distance, or service availability.

PROVENANCE PRESERVATION:
- If fare type is "official" or "brta", call it "Official BRTA fare".
- If fare type is "crowdsourced" or "community", call it "Community estimate".
- If fare type is "estimated", call it "Estimated fare".
- If duration_provenance is "osrm" or "google_routes", say "about X minutes without live traffic".
- If duration_provenance is "multimodal", describe it as the actual journey time.
- If a bus is selected, describe the board and exit stops from the facts.

If no bus is selected, do not suggest one. Do not fabricate alternatives.

Keep the explanation suitable for a Bangladeshi university student. \
Write in natural, clear English."""


@router.post("/commute-guide")
async def commute_guide(
    body: CommuteGuideRequest,
    user: CurrentUser = Depends(require_student),
):
    facts_lines = [
        f"Origin: {body.origin}",
        f"Destination: {body.destination}",
    ]
    if body.distance_km:
        facts_lines.append(f"Distance: {body.distance_km} km")
    if body.duration_minutes is not None:
        facts_lines.append(f"Duration: {body.duration_minutes} minutes")
    facts_lines.append(f"Duration provenance: {body.duration_provenance}")
    if body.selected_mode:
        facts_lines.append(f"Selected mode: {body.mode_label or body.selected_mode}")
    if body.fare:
        fare = body.fare
        if fare.get("available") and fare.get("low") and fare.get("high"):
            facts_lines.append(
                f"Fare: ৳{fare['low']}-{fare['high']} ({fare.get('type', 'estimated')})"
            )
            if fare.get("source"):
                facts_lines.append(f"Fare source: {fare['source']}")
        elif fare.get("available") is False:
            fare_type = fare.get("type", "none")
            mode = (body.selected_mode or "").lower()
            if fare_type == "none" and mode in ("walk", "walking"):
                facts_lines.append("Fare: Free (walking)")
            elif fare_type == "free":
                facts_lines.append("Fare: Free")
            else:
                facts_lines.append("Fare: Not available for this mode")
    if body.verified_waypoints:
        facts_lines.append(f"Verified route points: {' → '.join(body.verified_waypoints)}")
    if body.is_multimodal:
        facts_lines.append(f"Type: Multimodal journey with {body.transfers} transfer(s)")
    else:
        facts_lines.append("Type: Direct road route")

    if body.selected_bus_operator:
        bus_info = f"Selected bus: {body.selected_bus_operator}"
        if body.selected_bus_board_stop:
            bus_info += f", Board at: {body.selected_bus_board_stop}"
        if body.selected_bus_exit_stop:
            bus_info += f", Exit at: {body.selected_bus_exit_stop}"
        if body.selected_bus_stop_count is not None:
            bus_info += f" ({body.selected_bus_stop_count} stops)"
        facts_lines.append(bus_info)

    facts_text = "\n".join(facts_lines)

    prompt = (
        f"{_SYSTEM_INSTRUCTION}\n\n"
        f"JOURNEY FACTS:\n{facts_text}"
    )

    try:
        result = await generate(user.uid, prompt)
        return {"explanation": result}
    except Exception:
        # AI failure must not break the feature — return empty so the
        # client falls back to local deterministic rendering.
        return {"explanation": ""}


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
