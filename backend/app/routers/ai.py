from fastapi import APIRouter, Depends, HTTPException

from app.core.auth import CurrentUser, require_student
from app.schemas import AiNoteRequest, PdfQuestionRequest
from app.services.ai_service import generate
from app.services.pdf_service import extract_pdf_text
from app.services.permission_service import get_material_for_user
from app.services.storage_service import download_bytes

router = APIRouter()


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

    raw = download_bytes(material["filePath"])
    try:
        text = extract_pdf_text(raw, page=body.page)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

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
