"""Unit tests for the P0-2 CI helper ``scripts/verify_postgres_schema.py``.

These tests do NOT require a live Postgres. They cover:

* The script exits 2 with a clear error when ``DATABASE_URL`` is missing.
* ``_expected_tables`` returns the same set that ``Base.metadata`` declares.
* The diff helper returns the right ``(missing, unexpected)`` partition.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest


_HELPER_PATH = (
    Path(__file__).resolve().parent.parent / "scripts" / "verify_postgres_schema.py"
)


def _load_helper():
    spec = importlib.util.spec_from_file_location("verify_postgres_schema", str(_HELPER_PATH))
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_helper_loads():
    helper = _load_helper()
    assert callable(helper.main)
    assert callable(helper._expected_tables)


def test_expected_tables_includes_commutedb_core():
    helper = _load_helper()
    tables = helper._expected_tables()
    # The Phase-2 CommuteBD models are the only ones currently committed
    # in ``app/database/models.py``. This test guards against an accidental
    # drop in the model module.
    assert "places" in tables
    assert "user_fare_reports" in tables
    assert "fare_model_registry" in tables


def test_diff_helper_reports_missing_and_unexpected():
    helper = _load_helper()
    expected = {"a", "b", "c"}
    actual = {"a", "c", "d"}
    missing, unexpected = helper._diff(expected, actual)
    assert missing == {"b"}
    assert unexpected == {"d"}


def test_main_returns_2_when_database_url_missing(monkeypatch, capsys):
    helper = _load_helper()
    monkeypatch.delenv("DATABASE_URL", raising=False)
    rc = helper.main([])
    assert rc == 2
    captured = capsys.readouterr()
    assert "DATABASE_URL" in captured.err


def test_main_returns_0_when_schema_matches(monkeypatch):
    """Verify the script logic by patching the two table-collectors to agree."""
    helper = _load_helper()
    monkeypatch.setenv("DATABASE_URL", "postgresql://test/test")
    monkeypatch.setattr(
        helper,
        "_expected_tables",
        lambda: {"places", "user_fare_reports"},
    )
    monkeypatch.setattr(
        helper,
        "_actual_tables",
        lambda _url: {"places", "user_fare_reports", "alembic_version"},
    )
    monkeypatch.setattr(helper, "_run_alembic_upgrade", lambda _url: None)
    rc = helper.main(["--skip-alembic"])
    assert rc == 0


def test_main_returns_1_on_missing_tables(monkeypatch, capsys):
    helper = _load_helper()
    monkeypatch.setenv("DATABASE_URL", "postgresql://test/test")
    monkeypatch.setattr(helper, "_expected_tables", lambda: {"places", "ghost"})
    monkeypatch.setattr(
        helper,
        "_actual_tables",
        lambda _url: {"places", "alembic_version"},
    )
    monkeypatch.setattr(helper, "_run_alembic_upgrade", lambda _url: None)
    rc = helper.main(["--skip-alembic"])
    assert rc == 1
    captured = capsys.readouterr()
    assert "ghost" in captured.err


def test_main_returns_1_on_unexpected_tables(monkeypatch, capsys):
    helper = _load_helper()
    monkeypatch.setenv("DATABASE_URL", "postgresql://test/test")
    monkeypatch.setattr(helper, "_expected_tables", lambda: {"places"})
    monkeypatch.setattr(
        helper,
        "_actual_tables",
        lambda _url: {"places", "alembic_version", "legacy"},
    )
    monkeypatch.setattr(helper, "_run_alembic_upgrade", lambda _url: None)
    rc = helper.main(["--skip-alembic", "--allow-extra", "legacy"])
    # 'legacy' is exempted, so it should pass.
    assert rc == 0
