from __future__ import annotations

from datetime import datetime, timedelta, timezone
from statistics import median
from typing import Any

from sqlalchemy import and_, func, select

from app.core.config import get_settings
from app.database.connection import get_sessionmaker
from app.database.models import UserFareReport
from app.services.commute.fare_quality import remove_outliers


def percentile(values, p):
    if not values:
        raise ValueError("values cannot be empty")
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    position = (len(values) - 1) * p
    lower = int(position)
    upper = min(lower + 1, len(values) - 1)
    weight = position - lower
    return values[lower] * (1 - weight) + values[upper] * weight


def confidence_for_sample_count(count):
    if count < 3:
        return None
    if count < 8:
        return "Low"
    if count < 20:
        return "Medium"
    return "High"


class CrowdFareRepository:
    """PostgreSQL-backed approved fare-report repository.

    Public method surface matches the previous Supabase implementation. If
    PostgreSQL credentials are not configured, methods safely return empty
    results instead of fabricating data.
    """

    def __init__(self):
        self.enabled = bool(get_settings().database_url)

    def _session(self):
        return get_sessionmaker()()

    def approved_fares(
        self,
        *,
        mode,
        origin_text=None,
        destination_text=None,
        days=180,
        limit=500,
    ):
        if not self.enabled:
            return []
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
        stmt = (
            select(
                UserFareReport.fare_paid_tk,
                UserFareReport.origin_text,
                UserFareReport.destination_text,
            )
            .where(
                and_(
                    UserFareReport.transport_mode == mode,
                    UserFareReport.moderation_status == "approved",
                    UserFareReport.created_at >= cutoff,
                )
            )
            .order_by(UserFareReport.created_at.desc())
            .limit(limit)
        )
        origin_norm = (origin_text or "").strip().lower()
        dest_norm = (destination_text or "").strip().lower()
        fares = []
        try:
            with self._session() as session:
                for row in session.execute(stmt).all():
                    if origin_norm and origin_norm not in str(row.origin_text or "").lower():
                        continue
                    if dest_norm and dest_norm not in str(row.destination_text or "").lower():
                        continue
                    try:
                        fare = float(row.fare_paid_tk)
                    except Exception:
                        continue
                    if 1 <= fare <= 10000:
                        fares.append(fare)
        except Exception:
            return []
        return fares

    def count_approved(self, *, mode=None):
        """Return count of approved reports (optionally filtered by mode)."""
        if not self.enabled:
            return 0
        stmt = select(func.count()).select_from(UserFareReport).where(
            UserFareReport.moderation_status == "approved"
        )
        if mode is not None:
            stmt = stmt.where(UserFareReport.transport_mode == mode)
        try:
            with self._session() as session:
                return int(session.execute(stmt).scalar_one() or 0)
        except Exception:
            return 0

    def aggregate(self, *, mode, origin_text=None, destination_text=None):
        raw = self.approved_fares(
            mode=mode,
            origin_text=origin_text,
            destination_text=destination_text,
        )
        # One mistyped Tk 5,000 in a sample of thirty Tk 30 fares moves the
        # q75 a student is shown far more than it should. Prune first, then
        # judge confidence on what actually remains as evidence -- counting
        # the discarded reports towards confidence would be the same
        # over-claim in a different place.
        pruned = remove_outliers(raw)
        fares = pruned.kept

        confidence = confidence_for_sample_count(len(fares))
        if confidence is None:
            return None
        return {
            "sampleCount": len(fares),
            "outliersRemoved": pruned.removed_count,
            "q25": round(percentile(fares, 0.25) / 5) * 5,
            "median": round(median(fares) / 5) * 5,
            "q75": round(percentile(fares, 0.75) / 5) * 5,
            "confidence": confidence,
            "fareType": "crowdsourced",
            "source": "Approved recent Gochano fare reports",
        }


__all__ = ["CrowdFareRepository", "confidence_for_sample_count", "percentile"]
