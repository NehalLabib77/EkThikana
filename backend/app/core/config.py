from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "development"
    cors_origins: str = ""

    # P4-1: shared secret required to read the internal latency snapshot.
    # Empty by default — when unset, GET /api/_internal/latency returns 404.
    internal_metrics_token: str = ""

    firebase_project_id: str = ""
    firebase_service_account_b64: str = ""

    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_bucket: str = "ekthikana-files"

    # Phase 2: PostgreSQL connection URL (psycopg2 dialect). When unset the
    # backend falls back to an in-memory SQLite engine so unit tests and
    # local dev never break on a missing database.
    database_url: str = ""
    # Private file storage: Backblaze B2 via its S3-compatible API. All five
    # values are required; when any is empty the storage service refuses
    # reads/writes so the backend fails loudly instead of silently routing
    # user files to a different provider (spec §79).
    b2_bucket_name: str = ""
    b2_endpoint_url: str = ""
    b2_region: str = ""
    b2_key_id: str = ""
    b2_application_key: str = ""

    # Retained only so an existing deployment that still sets this variable
    # does not fail validation. It is inert: nothing reads it at runtime.
    firebase_storage_bucket: str = ""

    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"

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


def normalize_supabase_url(value: str) -> str:
    """Accept either a full Supabase URL or a bare project ref."""
    raw = (value or "").strip().rstrip("/")
    if not raw:
        return ""
    if raw.startswith("http://") or raw.startswith("https://"):
        return raw
    return f"https://{raw}.supabase.co"


@lru_cache
def get_settings() -> Settings:
    return Settings()
