from io import BytesIO

from pypdf import PdfReader


def extract_pdf_text(data: bytes, page: int | None = None, max_chars: int = 70000) -> str:
    reader = PdfReader(BytesIO(data))

    if page is not None:
        if page < 1 or page > len(reader.pages):
            raise ValueError("Page number is outside the document")
        pages = [reader.pages[page - 1]]
    else:
        pages = reader.pages

    chunks = []
    total = 0
    for p in pages:
        text = p.extract_text() or ""
        if not text:
            continue
        remaining = max_chars - total
        if remaining <= 0:
            break
        chunks.append(text[:remaining])
        total += min(len(text), remaining)
    return "\n\n".join(chunks).strip()
