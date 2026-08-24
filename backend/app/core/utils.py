import re
from datetime import datetime, timezone


def utc_now():
    return datetime.now(timezone.utc)


def safe_filename(name: str) -> str:
    name = name.strip().replace("\\", "_").replace("/", "_")
    name = re.sub(r"[^A-Za-z0-9._() -]+", "_", name)
    return name[:120] or "file"


def keywords(text: str, limit: int = 100):
    parts = re.findall(r"[A-Za-z0-9\u0980-\u09FF]+", text.lower())
    out = []
    seen = set()
    for p in parts:
        if len(p) < 2 or p in seen:
            continue
        seen.add(p)
        out.append(p)
        if len(out) >= limit:
            break
    return out


def detect_supported_file_type(data: bytes) -> tuple[str, str]:
    if data.startswith(b"%PDF-"):
        return "application/pdf", ".pdf"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", ".png"
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg", ".jpg"
    raise ValueError("Only PDF, PNG and JPEG files are allowed")
