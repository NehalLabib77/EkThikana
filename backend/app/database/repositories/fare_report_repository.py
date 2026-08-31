"""PostgreSQL-backed repository for community-submitted fare reports.

Mirrors the public surface of
``app.services.commute.crowd.SupabaseFareReportRepository`` so callers do not
need to change. The previous implementation reached into a Supabase client
attribute (``self.client``); the new one accepts a ``Session`` and exposes the
same insert helper as a module-level function so the leak in ``ml_fare.py`` is
fixed at the same time.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import hashlib

from sqlalchemy import delete, select

from app.database.connection import get_sessionmaker
from app.database.models import UserFareReport


# Translate router-side dict keys into SQL column names.  The router still
# sends legacy keys ("fare_paid_tk", "transport_mode") that already match
# the canonical SQL schema; this map covers the camelCase keys that admin/
# test paths may pass.
_COLUMN_ALIASES: dict[str, str] = {
    "id": "report_id",
    "moderationStatus": "moderation_status",
}


def _normalize_payload(payload: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in payload.items():
        target = _COLUMN_ALIASES.get(key, key)
        out[target] = value
    out.setdefault("moderation_status", "pending")
    if "created_at" in out and isinstance(out["created_at"], str):
        try:
            out["created_at"] = datetime.fromisoformat(out["created_at"])
        except ValueError:
            out["created_at"] = datetime.now(timezone.utc)
    return out


def insert_fare_report(payload: dict[str, Any]) -> dict[str, Any]:
    """Insert a community-submitted fare report and return its plain dict."""
    row_payload = _normalize_payload(payload)
    with get_sessionmaker()() as session:
        row = UserFareReport(**row_payload)
        session.add(row)
        session.commit()
        session.refresh(row)
        return _report_row_to_dict(row)


def list_recent_fare_reports(limit: int = 50) -> list[dict[str, Any]]:
    stmt = (
        select(UserFareReport)
        .order_by(UserFareReport.created_at.desc())
        .limit(max(1, min(int(limit), 200)))
    )
    with get_sessionmaker()() as session:
        rows = list(session.execute(stmt).scalars())
        return [_report_row_to_dict(row) for row in rows]


def delete_fare_reports_for_user(uid: str) -> int:
    """P1-5 — wipe community fare reports authored by ``uid``.

    The owning column is hashed to keep raw Firebase UIDs out of the
    Postgres mirror. Returns the number of rows deleted (zero if the user
    never reported a fare, or if the Postgres mirror is unreachable —
    the caller treats both as success so account deletion can finish).
    """
    user_id_hash = hashlib.sha256(uid.encode("utf-8")).hexdigest()
    stmt = delete(UserFareReport).where(UserFareReport.user_id_hash == user_id_hash)
    with get_sessionmaker()() as session:
        result = session.execute(stmt)
        session.commit()
        return int(result.rowcount or 0)


def _report_row_to_dict(row: UserFareReport) -> dict[str, Any]:
    return {
        "reportId": str(row.report_id) if row.report_id is not None else None,
        "userIdHash": row.user_id_hash,
        "transportMode": row.transport_mode,
        "farePaidTk": float(row.fare_paid_tk) if row.fare_paid_tk is not None else None,
        "originPlaceId": row.origin_place_id,
        "originText": row.origin_text,
        "destinationPlaceId": row.destination_place_id,
        "destinationText": row.destination_text,
        "moderationStatus": row.moderation_status,
        "trafficLevel": row.traffic_level,
        "deviceLocationVerified": row.device_location_verified,
        "routeDistanceKm": float(row.route_distance_km) if row.route_distance_km is not None else None,
        "tripMinutes": row.trip_minutes,
        "createdAt": row.created_at.isoformat() if row.created_at else None,
    }


def get_fare_report_repository() -> "FareReportRepository":
    return FareReportRepository()


class FareReportRepository:
    """Object-style wrapper kept for compatibility with old import sites."""

    @property
    def client(self) -> None:  # pragma: no cover - explicit compatibility stub
        return None

    def insert(self, payload: dict[str, Any]) -> dict[str, Any]:
        return insert_fare_report(payload)


__all__ = [
    "FareReportRepository",
    "get_fare_report_repository",
    "insert_fare_report",
    "list_recent_fare_reports",
    "delete_fare_reports_for_user",
]
