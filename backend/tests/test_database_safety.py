"""Tests for the P0-1 backend database-safety guard.

Verifies:
* ``app_env="production"`` with empty ``DATABASE_URL`` raises
  :class:`DatabaseConfigError` when the engine is built.
* ``app_env="development"`` with empty ``DATABASE_URL`` silently falls back to
  SQLite in-memory (current dev/test behaviour preserved).
* ``describe_active_database`` returns a non-empty summary that masks the
  Postgres password when one is present.
"""
from __future__ import annotations

from unittest.mock import patch

import pytest

from app.core.config import Settings, get_settings
from app.database.connection import (
    DatabaseConfigError,
    _build_engine,
    describe_active_database,
    reset_engine_cache,
)


def _settings(**overrides) -> Settings:
    """Build a Settings instance without reading the host .env."""
    base = {
        "app_env": "development",
        "database_url": "",
        "firebase_project_id": "",
        "firebase_service_account_b64": "",
        "supabase_url": "",
        "supabase_service_role_key": "",
        "supabase_bucket": "ekthikana-files",
        "firebase_storage_bucket": "",
        "gemini_api_key": "",
        "gemini_model": "gemini-2.5-flash",
    }
    base.update(overrides)
    # Use _settings_construct to avoid the lru_cache and the .env file.
    return Settings(**base)


@pytest.fixture(autouse=True)
def _clear_settings_cache():
    reset_engine_cache()
    get_settings.cache_clear()
    yield
    reset_engine_cache()
    get_settings.cache_clear()


def test_production_without_database_url_raises():
    settings = _settings(app_env="production", database_url="")
    with patch("app.database.connection.get_settings", return_value=settings):
        with pytest.raises(DatabaseConfigError) as excinfo:
            _build_engine()
    assert "DATABASE_URL" in str(excinfo.value)
    assert "production" in str(excinfo.value).lower()


def test_development_without_database_url_falls_back_to_sqlite():
    settings = _settings(app_env="development", database_url="")
    with patch("app.database.connection.get_settings", return_value=settings):
        engine = _build_engine()
    assert engine.dialect.name == "sqlite"


def test_describe_active_database_production_missing_url():
    settings = _settings(app_env="production", database_url="")
    with patch("app.database.connection.get_settings", return_value=settings):
        summary = describe_active_database()
    assert "UNSET" in summary
    assert "production" in summary.lower()


def test_describe_active_database_dev_fallback():
    settings = _settings(app_env="development", database_url="")
    with patch("app.database.connection.get_settings", return_value=settings):
        summary = describe_active_database()
    assert "sqlite" in summary.lower()


def test_describe_active_database_postgres_masks_password():
    settings = _settings(
        app_env="production",
        database_url="postgresql+psycopg2://app_user:s3cret@db.internal:5432/gochano?sslmode=require",
    )
    with patch("app.database.connection.get_settings", return_value=settings):
        summary = describe_active_database()
    assert "db.internal" in summary
    assert "s3cret" not in summary
    assert "***" in summary
