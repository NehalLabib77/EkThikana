from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "development"
    cors_origins: str = ""

    firebase_project_id: str = ""
    firebase_service_account_b64: str = ""

    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_bucket: str = "ekthikana-files"

    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.7-flash"

    max_upload_mb: int = 15
    user_storage_limit_mb: int = 100
    upload_daily_limit: int = 10
    # Spec §8.10: signed download/view URLs must expire in 15 minutes or less.
    signed_url_ttl_seconds: int = 900
    ai_daily_limit: int = 30

    routing_provider: str = "osrm"
    osrm_base_url: str = "https://router.project-osrm.org"
    nominatim_base_url: str = "https://nominatim.openstreetmap.org"
    routing_user_agent: str = "Gochano/1.0 (configure SUPPORT_EMAIL before public release)"
    commute_ml_min_total_reports: int = 500
    commute_ml_min_mode_reports: int = 150

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


def normalize_supabase_url(url: str) -> str:
    """Trim whitespace/trailing slashes from a Supabase project URL.

    The Supabase Python SDK raises if the URL has a trailing path segment,
    so accept either a bare project URL or one already prefixed with
    ``/rest/v1`` and normalize it back to the canonical bare form.
    """
    if not url:
        return url
    cleaned = url.strip().rstrip("/")
    for suffix in ("/rest/v1", "/auth/v1", "/storage/v1"):
        if cleaned.endswith(suffix):
            cleaned = cleaned[: -len(suffix)]
            break
    return cleaned
