"""CI helper: verify a fresh Postgres can absorb the full Gochano schema.

This script is intended to run in CI on every PR that touches ``app/database``
or ``alembic/versions``. It assumes:

* ``DATABASE_URL`` points to an empty (or throwaway) PostgreSQL DSN.
* The schema is the only thing in the database — running against a populated
  database WILL fail.

The script:

1. Runs ``alembic upgrade head`` (commits every migration in order).
2. Connects to the database and lists every table in the ``public`` schema.
3. Cross-checks the table list against the SQLAlchemy metadata in
   ``app.database.models.Base.metadata``.
4. Exits non-zero on any mismatch (missing table, extra table that is not a
   SQLAlchemy-managed table or alembic_version).

Run locally:

    DATABASE_URL=postgresql://user:pass@localhost:5432/gochano_ci \\
        python -m scripts.verify_postgres_schema

The script never mutates application data: it is safe to run against an
ephemeral Postgres in CI.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def _run_alembic_upgrade(database_url: str) -> None:
    """Invoke ``alembic upgrade head`` with the supplied DATABASE_URL."""
    env = os.environ.copy()
    env["DATABASE_URL"] = database_url
    # We invoke from the backend/ directory so ``alembic.ini`` is found.
    backend_dir = Path(__file__).resolve().parent.parent
    print(f"[verify-postgres] running 'alembic upgrade head' in {backend_dir}")
    result = subprocess.run(
        ["alembic", "upgrade", "head"],
        cwd=str(backend_dir),
        env=env,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"alembic upgrade head failed with exit code {result.returncode}"
        )


def _expected_tables() -> set[str]:
    """Return the set of table names that SQLAlchemy metadata declares."""
    # Imported here so the script can run without SQLAlchemy when the user
    # passes ``--skip-alembic``.
    from app.database.models import Base  # noqa: WPS433

    return {table.name for table in Base.metadata.sorted_tables}


def _actual_tables(database_url: str) -> set[str]:
    """Return every table in the ``public`` schema of ``database_url``."""
    # Imported lazily so the alembic-only mode does not require psycopg.
    from sqlalchemy import create_engine, text  # noqa: WPS433

    engine = create_engine(database_url, future=True)
    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "select tablename from pg_tables "
                "where schemaname = 'public' order by tablename"
            )
        ).fetchall()
    engine.dispose()
    return {row[0] for row in rows}


def _diff(expected: set[str], actual: set[str]) -> tuple[set[str], set[str]]:
    """Return ``(missing, unexpected)`` table sets."""
    return expected - actual, actual - expected


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-alembic",
        action="store_true",
        help="Skip running alembic upgrade; just verify an existing schema.",
    )
    parser.add_argument(
        "--allow-extra",
        action="append",
        default=[],
        help="Extra tables allowed in the DB but not declared in the ORM. "
        "Repeat for multiple. Use this for views and operator-managed tables.",
    )
    args = parser.parse_args(argv)

    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url:
        print("[verify-postgres] DATABASE_URL is not set", file=sys.stderr)
        return 2

    if not args.skip_alembic:
        _run_alembic_upgrade(database_url)

    expected = _expected_tables()
    actual = _actual_tables(database_url)

    allow_extra = set(args.allow_extra) | {"alembic_version"}
    actual_filtered = {t for t in actual if t not in allow_extra}

    missing, unexpected = _diff(expected, actual_filtered)

    print(f"[verify-postgres] expected {len(expected)} tables")
    print(f"[verify-postgres] actual   {len(actual)} tables")
    if missing:
        print(f"[verify-postgres] MISSING in DB: {sorted(missing)}", file=sys.stderr)
    if unexpected:
        print(
            f"[verify-postgres] UNEXPECTED in DB: {sorted(unexpected)}",
            file=sys.stderr,
        )

    if missing or unexpected:
        return 1
    print("[verify-postgres] schema matches SQLAlchemy metadata ✅")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())