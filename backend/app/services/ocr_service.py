from io import BytesIO

import pytesseract
from PIL import Image
from pdf2image import convert_from_bytes

from app.services.pdf_service import extract_pdf_text


def extract_text(data: bytes, content_type: str) -> str:
    content_type = (content_type or "").lower()

    if "pdf" in content_type:
        try:
            text = extract_pdf_text(data, max_chars=30000)
            if len(text.strip()) >= 40:
                return text
        except Exception:
            pass

        images = convert_from_bytes(data, first_page=1, last_page=3, dpi=180)
        return "\n\n".join(pytesseract.image_to_string(img) for img in images).strip()

    image = Image.open(BytesIO(data)).convert("RGB")
    return pytesseract.image_to_string(image).strip()


def candidate_lines(text: str):
    lines = []
    for raw in text.splitlines():
        line = " ".join(raw.split())
        if len(line) >= 3:
            lines.append(line[:180])
    return lines[:80]
