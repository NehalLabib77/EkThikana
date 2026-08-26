from functools import lru_cache

from supabase import create_client

from app.core.config import get_settings, normalize_supabase_url


@lru_cache
def _client():
    s = get_settings()
    if not s.supabase_url or not s.supabase_service_role_key:
        raise RuntimeError("Supabase storage credentials are not configured")
    return create_client(normalize_supabase_url(s.supabase_url), s.supabase_service_role_key)


def upload_bytes(path: str, data: bytes, content_type: str):
    s = get_settings()
    return (
        _client()
        .storage
        .from_(s.supabase_bucket)
        .upload(
            path=path,
            file=data,
            file_options={
                "content-type": content_type or "application/octet-stream",
                "upsert": "false",
            },
        )
    )


def create_signed_url(path: str, *, download: bool = False) -> str:
    s = get_settings()
    options = {"download": True} if download else None
    result = (
        _client()
        .storage
        .from_(s.supabase_bucket)
        .create_signed_url(path, s.signed_url_ttl_seconds, options)
    )
    if isinstance(result, dict):
        return result.get("signedURL") or result.get("signedUrl") or result.get("signed_url") or ""
    if hasattr(result, "get"):
        return result.get("signedURL") or result.get("signedUrl") or ""
    return ""


def download_bytes(path: str) -> bytes:
    s = get_settings()
    return _client().storage.from_(s.supabase_bucket).download(path)


def delete_file(path: str):
    s = get_settings()
    return _client().storage.from_(s.supabase_bucket).remove([path])
