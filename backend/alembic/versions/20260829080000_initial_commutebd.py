"""Initial CommuteBD schema (Gochano Phase 2 baseline).

Revision ID: 20260829080000
Revises:
Create Date: 2026-08-29 08:00:00.000000

This migration is idempotent and safe to apply against an existing CommuteBD
Postgres database that was provisioned from
``backend/data/commutebd/core_dataset/supabase_schema.sql`` and
``backend/data/commutebd/db/supabase_schema_ml_extension.sql``.  It brings
the schema in line with the SQLAlchemy models used by the runtime layer and
applies the production-only column additions from
``backend/migrations/001_gochano_commutebd_production.sql``.

Down migration is a no-op because dropping the unique index and columns on
a live database would silently destroy user-submitted data.
"""
from __future__ import annotations

from typing import Sequence, Union

from alembic import op


revision: str = "20260829080000"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Production extension columns (from 001_gochano_commutebd_production.sql)
    op.execute(
        "alter table if exists user_fare_reports "
        "add column if not exists trip_minutes integer, "
        "add column if not exists dedupe_key text, "
        "add column if not exists source_type text default 'user_report';"
    )

    op.execute(
        "create unique index if not exists idx_user_fare_reports_dedupe "
        "on user_fare_reports(dedupe_key) where dedupe_key is not null;"
    )

    op.execute(
        "create index if not exists idx_user_fare_reports_approved_mode_created "
        "on user_fare_reports(transport_mode, created_at desc) "
        "where moderation_status = 'approved';"
    )

    op.execute(
        "create or replace view commute_approved_fare_reports as "
        "select * from user_fare_reports where moderation_status = 'approved';"
    )

    # Enable RLS without permissive policies: backend service-role bypasses.
    for table in ("user_fare_reports", "crowd_fare_aggregates", "fare_model_registry"):
        op.execute(f"alter table if exists {table} enable row level security;")


def downgrade() -> None:
    # Intentionally a no-op: destructive downgrades would erase approved fare
    # reports.  Production rollback must be done through a forward-only
    # migration that explicitly moves data first.
    pass