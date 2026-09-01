"""Prescription scanning.

The contract this endpoint keeps: it reports what was read, how well it was
read, and nothing else. It does not prescribe, does not decide a schedule and
does not invent a reminder time. Every value it returns is either present in
the image or explicitly marked as a suggestion for the reader to accept or
reject.
"""
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile

from app.core.auth import CurrentUser, get_current_user
from app.core.config import get_settings
from app.core.utils import detect_supported_file_type
from app.services.ocr import languages, structuring
from app.services.ocr_service import candidate_lines, extract, parse_medicine_candidates

router = APIRouter()

WARNING = (
    "OCR can be wrong. Gochano does not prescribe or infer a medical schedule. "
    "Confirm medicine name, dose/instructions and actual reminder times before saving."
)


@router.get("/ocr-status")
def ocr_status(user: CurrentUser = Depends(get_current_user)):
    """What text recognition can actually do on this server.

    Exposed because a missing Bengali pack does not fail loudly -- it returns
    confident-looking Latin nonsense -- and the app needs to be able to say so
    rather than present the result as a reading of the prescription.
    """
    return languages.status()


@router.post("/extract")
async def extract_prescription(
    file: UploadFile = File(...),
    # Off by default. The rule-based parser is the contract; the model pass is
    # an optional regrouping of the same text and never a source of new facts.
    use_model: bool = Query(default=False, alias="useModel"),
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

    engine = languages.status()
    if not engine["available"]:
        # Refusing here is the honest answer. Running an English-only engine
        # over a Bengali prescription would produce a confident-looking
        # medicine list that means nothing.
        raise HTTPException(status_code=503, detail=engine["message"])

    try:
        extraction = extract(raw, mime)
    except Exception as exc:
        # Keep the client response JSON so the app can show the real error.
        raise HTTPException(
            status_code=422,
            detail=(
                "OCR could not read this prescription. Try a clearer, well-lit "
                f"image. ({type(exc).__name__})"
            ),
        ) from exc

    medicines = parse_medicine_candidates(extraction.text, extraction.recognition)
    structured_by = "parser"

    if use_model and extraction.text.strip():
        # Only a regrouping of text already recognised. Every field it returns
        # is re-checked against the OCR text, and anything not found there is
        # dropped however plausible it looks.
        regrouped = await structuring.structure(user.uid, extraction.text)
        if regrouped:
            medicines = _merge(medicines, regrouped, extraction)
            structured_by = "model+parser"

    return {
        "rawText": extraction.text,
        "candidateLines": candidate_lines(extraction.text),
        "medicines": medicines,
        # How well the page was actually read, from Tesseract's own per-word
        # confidence. Never a fabricated percentage.
        "quality": extraction.quality(),
        "engine": {
            "language": engine["language"],
            "bengaliSupported": engine["bengaliSupported"],
        },
        "structuredBy": structured_by,
        "warning": WARNING,
    }


def _merge(parsed, regrouped, extraction):
    """Add model-found medicines the parser missed, keeping parser results.

    The parser's output is authoritative where the two agree, because it is
    the deterministic path and the one covered by tests. The model only
    contributes entries the parser did not find at all -- which is exactly the
    case it helps with, a medicine whose dose landed on another line.
    """
    seen = {str(item.get("name", "")).strip().lower() for item in parsed}
    merged = list(parsed)

    from app.services.ocr import medicine_names

    for entry in regrouped:
        name = entry.get("name", "").strip()
        if not name or name.lower() in seen:
            continue
        seen.add(name.lower())

        item = {
            "name": name,
            "dose": entry.get("dose", ""),
            "instruction": entry.get("instruction", ""),
            "scheduleHints": [],
            # The model is never allowed to supply a clock time. If the
            # prescription states one, the parser has already found it.
            "explicitTimes": [],
            "sourceText": " ".join(
                part for part in (name, entry.get("dose", ""), entry.get("instruction", "")) if part
            ),
            "lineIndex": -1,
            "foundBy": "model",
        }
        item.update(medicine_names.annotate(name))

        if extraction.recognition is not None:
            from app.services.ocr.recognition import band_for

            confidence = extraction.recognition.confidence_for(name)
            item["nameConfidence"] = {
                "band": band_for(confidence),
                "value": None if confidence is None else round(confidence),
            }

        merged.append(item)

    return merged
