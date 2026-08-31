"""SQLAlchemy engine + session bootstrap.

`DATABASE_URL` is read from the environment via ``app.core.config.Settings``.
When unset (typical for the bare test fixture or local CLI smoke-tests), the
layer falls back to a SQLite in-memory database so ``Base.metadata.create_all``
still works without a live Postgres.

Production safety (P0-1):
    When ``app_env == "production"`` and ``DATABASE_URL`` is empty, building
    the engine **raises** instead of silently falling back to SQLite. This
    prevents a misconfigured Render deploy from "running" against a
    non-persistent database that loses data on every restart.

Example:

    DATABASE_URL=postgresql+psycopg2://user:pass@host:5432/gochano?sslmode=require

The module exposes:

* ``Base`` — declarative base for all ORM models.
* ``engine`` — lazily-built ``create_engine`` result.
* ``SessionLocal`` — session factory.
* ``get_db`` — FastAPI dependency yielding a session.
* ``describe_active_database`` — returns a short summary used by the startup
  banner so operators can see the active database surface.
"""
from __future__ import annotations

from typing import Iterator

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings


class Base(DeclarativeBase):
    """Declarative base for Gochano ORM models."""


class DatabaseConfigError(RuntimeError):
    """Raised when the database configuration is incompatible with the active env."""


_engine: Engine | None = None
_SessionLocal: sessionmaker[Session] | None = None


def _build_engine() -> Engine:
    settings = get_settings()
    url = settings.database_url.strip()
    if not url:
        # Local-only fallback so unit tests / smoke tests can still import
        # ``Base`` without a Postgres. Production code MUST set DATABASE_URL.
        if settings.app_env.lower() == "production":
            raise DatabaseConfigError(
                "DATABASE_URL is not set but APP_ENV=production. "
                "Set DATABASE_URL to a PostgreSQL DSN before starting the API."
            )
        url = "sqlite+pysqlite:///:memory:"
    connect_args: dict[str, object] = {}
    if url.startswith("sqlite"):
        connect_args["check_same_thread"] = False
    return create_engine(url, pool_pre_ping=True, future=True, connect_args=connect_args)


def get_engine() -> Engine:
    """Lazily build the SQLAlchemy engine."""
    global _engine
    if _engine is None:
        _engine = _build_engine()
    return _engine


def get_sessionmaker() -> sessionmaker[Session]:
    """Return (and cache) the ``sessionmaker`` tied to the engine."""
    global _SessionLocal
    if _SessionLocal is None:
        _SessionLocal = sessionmaker(bind=get_engine(), autoflush=False, autocommit=False, future=True)
    return _SessionLocal


def get_db() -> Iterator[Session]:
    """FastAPI dependency: yield a session, commit on success, rollback on error."""
    session = get_sessionmaker()()
    try:
        yield session
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def reset_engine_cache() -> None:
    """Test hook: drop the cached engine/sessionmaker so a new DATABASE_URL is honored."""
    global _engine, _SessionLocal
    if _engine is not None:
        _engine.dispose()
    _engine = None
    _SessionLocal = None


def describe_active_database() -> str:
    """Return a short human-readable summary of the active database engine.

    Used by the startup banner in :mod:`app.main` so operators can see which
    backend is live without having to inspect environment variables. The
    password is masked when the URL is a Postgres DSN.
    """
    settings = get_settings()
    url = settings.database_url.strip()
    if not url:
        if settings.app_env.lower() == "production":
            return "DATABASE_URL UNSET (production would fail)"
        return "sqlite-in-memory (dev/test fallback)"
    if url.startswith("sqlite"):
        return "sqlite"
    if "://" in url:
        scheme, rest = url.split("://", 1)
        if "@" in rest:
            creds, host_part = rest.split("@", 1)
            user = creds.split(":", 1)[0] if ":" in creds else creds
            host = host_part.split("/", 1)[0]
            return f"{scheme}://{user}:***@{host}"
        return f"{scheme}://{rest}"
    return scheme  # type: ignore[return-value]
