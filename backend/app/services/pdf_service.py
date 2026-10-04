from io import BytesIO

from pypdf import PdfReader


def count_pdf_pages(data: bytes) -> int:
    """Return the total number of pages in a PDF document."""
    try:
        reader = PdfReader(BytesIO(data))
        return len(reader.pages)
    except Exception:
        return 0


def extract_pdf_pages(data: bytes, max_pages: int = 200) -> list[dict]:
    """Extract text page by page from a PDF document.

    Returns a list of dictionaries with structure:
        [{"page": 1, "text": "Page text..."}, ...]
    """
    try:
        reader = PdfReader(BytesIO(data))
    except Exception:
        return []

    pages = reader.pages[:max_pages]
    result: list[dict] = []
    for idx, p in enumerate(pages, start=1):
        try:
            txt = p.extract_text() or ""
        except Exception:
            txt = ""
        result.append({"page": idx, "text": txt.strip()})
    return result


def extract_pdf_text(data: bytes, page: int | None = None, max_chars: int = 70000, max_pages: int | None = None) -> str:
    reader = PdfReader(BytesIO(data))

    if page is not None:
        if page < 1 or page > len(reader.pages):
            raise ValueError("Page number is outside the document")
        pages = [reader.pages[page - 1]]
    else:
        pages = reader.pages
        if max_pages is not None:
            pages = pages[:max_pages]

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
