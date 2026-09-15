from __future__ import annotations

from datetime import datetime, timedelta, timezone
from statistics import median
from typing import Any

from sqlalchemy import and_, func, select
from sqlalchemy import and_, func, or_, select

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

    def fares_for_bus_service(
        self,
        *,
        bus_service_id: str,
        origin_place_id: str | None = None,
        destination_place_id: str | None = None,
        origin_text: str = "",
        destination_text: str = "",
        days: int = 180,
        limit: int = 200,
    ) -> list[float]:
        """Get approved fares for a specific bus service on a specific route pair.

        Canonical place IDs (origin_place_id, destination_place_id) are the PRIMARY identity
        when available. Free-form text (origin_text, destination_text) strictly serves as
        fallback only when canonical IDs are null or unavailable.
        Direction matters: origin -> destination. Must NOT aggregate globally across routes.
        """
        if not self.enabled or not bus_service_id:
            return []

        has_origin = bool(origin_place_id or (origin_text and origin_text.strip()))
        has_dest = bool(destination_place_id or (destination_text and destination_text.strip()))
        if not has_origin or not has_dest:
            return []

        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
        conditions = [
            UserFareReport.transport_mode == "bus",
            UserFareReport.bus_service_id == bus_service_id,
            UserFareReport.moderation_status == "approved",
            UserFareReport.created_at >= cutoff,
        ]

        if origin_place_id:
            conditions.append(UserFareReport.origin_place_id == origin_place_id)
        elif origin_text and origin_text.strip():
            origin_norm = origin_text.strip().lower()
            conditions.append(func.lower(UserFareReport.origin_text) == origin_norm)

        if destination_place_id:
            conditions.append(UserFareReport.destination_place_id == destination_place_id)
        elif destination_text and destination_text.strip():
            dest_norm = destination_text.strip().lower()
            conditions.append(func.lower(UserFareReport.destination_text) == dest_norm)

        stmt = (
            select(UserFareReport.fare_paid_tk)
            .where(and_(*conditions))
            .order_by(UserFareReport.created_at.desc())
            .limit(limit)
        )

        fares: list[float] = []
        try:
            with self._session() as session:
                for row in session.execute(stmt).all():
                    try:
                        fare = float(row.fare_paid_tk)
                    except Exception:
                        continue
                    if 1 <= fare <= 10000:
                        fares.append(fare)
        except Exception:
            return []
        return fares

    def aggregate_for_bus_service(
        self,
        *,
        bus_service_id: str,
        origin_place_id: str | None = None,
        destination_place_id: str | None = None,
        origin_text: str = "",
        destination_text: str = "",
    ) -> dict[str, Any] | None:
        """Aggregate fares for a specific bus service on a specific route pair.

        Returns the same shape as ``aggregate()`` but scoped to a single
        bus service. Useful for showing per-bus fare comparisons.
        Returns None if fewer than 3 approved reports exist or if origin/destination is missing.
        One report must never become public qualified crowd truth.
        """
        raw = self.fares_for_bus_service(
            bus_service_id=bus_service_id,
            origin_place_id=origin_place_id,
            destination_place_id=destination_place_id,
            origin_text=origin_text,
            destination_text=destination_text,
        )
        if not raw:
            return None
        pruned = remove_outliers(raw)
        fares = pruned.kept

        confidence = confidence_for_sample_count(len(fares))
        if confidence is None:
            return None

        med = round(median(fares) / 5) * 5
        p25 = round(percentile(fares, 0.25) / 5) * 5
        p75 = round(percentile(fares, 0.75) / 5) * 5

        return {
            "busServiceId": bus_service_id,
            "originPlaceId": origin_place_id,
            "destinationPlaceId": destination_place_id,
            "sampleCount": len(fares),
            "medianFare": med,
            "p25Fare": p25,
            "p75Fare": p75,
            "confidence": confidence,
            "median": med,
            "q25": p25,
            "q75": p75,
            "outliersRemoved": pruned.removed_count,
            "fareType": "crowdsourced",
            "transportMode": "bus",
            "source": f"Approved fare reports for bus {bus_service_id}",
        }

    def aggregate_bus_fares_by_service(
        self,
        *,
        origin_place_id: str | None = None,
        destination_place_id: str | None = None,
        origin_text: str = "",
        destination_text: str = "",
    ) -> list[dict[str, Any]]:
        """Get crowd fare aggregates grouped by bus service for a specific route pair.

        Returns a list of per-bus-service aggregates for that route pair.
        Canonical place IDs are the primary identity when available.
        Direction matters: origin -> destination.
        Returns empty list if origin or destination is missing.
        """
        if not self.enabled:
            return []

        has_origin = bool(origin_place_id or (origin_text and origin_text.strip()))
        has_dest = bool(destination_place_id or (destination_text and destination_text.strip()))
        if not has_origin or not has_dest:
            return []

        cutoff = datetime.now(timezone.utc) - timedelta(days=180)
        origin_norm = origin_text.strip().lower() if origin_text else ""
        dest_norm = destination_text.strip().lower() if destination_text else ""

        conditions = [
            UserFareReport.transport_mode == "bus",
            UserFareReport.bus_service_id.is_not(None),
            UserFareReport.moderation_status == "approved",
            UserFareReport.created_at >= cutoff,
        ]

        if origin_place_id:
            conditions.append(UserFareReport.origin_place_id == origin_place_id)
        elif origin_norm:
            conditions.append(func.lower(UserFareReport.origin_text) == origin_norm)

        if destination_place_id:
            conditions.append(UserFareReport.destination_place_id == destination_place_id)
        elif dest_norm:
            conditions.append(func.lower(UserFareReport.destination_text) == dest_norm)

        stmt = (
            select(
                UserFareReport.bus_service_id,
                UserFareReport.fare_paid_tk,
            )
            .where(and_(*conditions))
            .order_by(UserFareReport.created_at.desc())
            .limit(500)
        )

        fares_by_service: dict[str, list[float]] = {}
        try:
            with self._session() as session:
                for row in session.execute(stmt).all():
                    svc_id = str(row.bus_service_id or "")
                    if not svc_id:
                        continue
                    try:
                        fare = float(row.fare_paid_tk)
                    except Exception:
                        continue
                    if 1 <= fare <= 10000:
                        fares_by_service.setdefault(svc_id, []).append(fare)
        except Exception:
            return []

        results: list[dict[str, Any]] = []
        for svc_id, raw_fares in fares_by_service.items():
            pruned = remove_outliers(raw_fares)
            fares = pruned.kept
            confidence = confidence_for_sample_count(len(fares))
            if confidence is None:
                continue
            med = round(median(fares) / 5) * 5
            p25 = round(percentile(fares, 0.25) / 5) * 5
            p75 = round(percentile(fares, 0.75) / 5) * 5
            results.append({
                "busServiceId": svc_id,
                "originPlaceId": origin_place_id,
                "destinationPlaceId": destination_place_id,
                "sampleCount": len(fares),
                "medianFare": med,
                "p25Fare": p25,
                "p75Fare": p75,
                "confidence": confidence,
                "median": med,
                "q25": p25,
                "q75": p75,
                "outliersRemoved": pruned.removed_count,
                "fareType": "crowdsourced",
                "transportMode": "bus",
                "source": f"Approved fare reports for bus {svc_id}",
            })

        results.sort(key=lambda r: (r["sampleCount"] * -1, r["busServiceId"]))
        return results


__all__ = ["CrowdFareRepository", "confidence_for_sample_count", "percentile"]
