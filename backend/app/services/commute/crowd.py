from __future__ import annotations

from datetime import datetime, timedelta, timezone
from statistics import median
from typing import Any

from supabase import create_client

from app.core.config import get_settings


def percentile(values: list[float], p: float) -> float:
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


def confidence_for_sample_count(count: int) -> str | None:
    if count < 3:
        return None
    if count < 8:
        return "Low"
    if count < 20:
        return "Medium"
    return "High"


class CrowdFareRepository:
    """Supabase-backed approved fare report repository.

    Service-role credentials stay server-side. If Supabase/report tables are
    not configured yet, methods safely return no crowd estimate instead of
    fabricating data.
    """

    def __init__(self) -> None:
        settings = get_settings()
        self.enabled = bool(settings.supabase_url and settings.supabase_service_role_key)
        self.client = (
            create_client(settings.supabase_url, settings.supabase_service_role_key)
            if self.enabled
            else None
        )

    def approved_fares(
        self,
        *,
        mode: str,
        origin_text: str | None = None,
        destination_text: str | None = None,
        days: int = 180,
        limit: int = 500,
    ) -> list[float]:
        if not self.client:
            return []
        try:
            cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
            query = (
                self.client.table("user_fare_reports")
                .select("fare_paid_tk,origin_text,destination_text,created_at")
                .eq("transport_mode", mode)
                .eq("moderation_status", "approved")
                .gte("created_at", cutoff)
                .limit(limit)
            )
            response = query.execute()
            rows = getattr(response, "data", None) or []
            fares: list[float] = []
            origin_norm = (origin_text or "").strip().lower()
            dest_norm = (destination_text or "").strip().lower()
            for row in rows:
                if origin_norm and origin_norm not in str(row.get("origin_text", "")).lower():
                    continue
                if dest_norm and dest_norm not in str(row.get("destination_text", "")).lower():
                    continue
                try:
                    fare = float(row.get("fare_paid_tk"))
                    if 1 <= fare <= 10000:
                        fares.append(fare)
                except Exception:
                    continue
            return fares
        except Exception:
            return []

    def aggregate(
        self,
        *,
        mode: str,
        origin_text: str | None = None,
        destination_text: str | None = None,
    ) -> dict[str, Any] | None:
        fares = self.approved_fares(
            mode=mode,
            origin_text=origin_text,
            destination_text=destination_text,
        )
        confidence = confidence_for_sample_count(len(fares))
        if confidence is None:
            return None
        return {
            "sampleCount": len(fares),
            "q25": round(percentile(fares, 0.25) / 5) * 5,
            "median": round(median(fares) / 5) * 5,
            "q75": round(percentile(fares, 0.75) / 5) * 5,
            "confidence": confidence,
            "fareType": "crowdsourced",
            "source": "Approved recent Gochano fare reports",
        }
