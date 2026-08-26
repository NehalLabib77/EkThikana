from __future__ import annotations

from io import BytesIO
from typing import Any

import joblib
import numpy as np

from app.core.config import get_settings
from app.services.commute.crowd import CrowdFareRepository
from app.services.storage_service import download_bytes


class MLFarePredictionService:
    """Quantile fare model inference for uncertain observed-market fares only.

    Models are never used for official bus or metro fares. Activation is
    gated by approved real-report counts. If models/storage are unavailable,
    the fare engine falls back to crowd statistics/rules without failing the
    commute feature.
    """

    def __init__(self) -> None:
        self.settings = get_settings()
        self.crowd = CrowdFareRepository()
        self._models: dict[str, dict[str, Any]] = {}

    def _approved_counts(self, mode: str) -> tuple[int, int]:
        if not self.crowd.client:
            return 0, 0
        try:
            all_rows = (
                self.crowd.client.table("user_fare_reports")
                .select("report_id", count="exact")
                .eq("moderation_status", "approved")
                .execute()
            )
            mode_rows = (
                self.crowd.client.table("user_fare_reports")
                .select("report_id", count="exact")
                .eq("moderation_status", "approved")
                .eq("transport_mode", mode)
                .execute()
            )
            return int(getattr(all_rows, "count", 0) or 0), int(getattr(mode_rows, "count", 0) or 0)
        except Exception:
            return 0, 0

    def enabled_for(self, mode: str) -> bool:
        if mode not in {"rickshaw", "cng"}:
            return False
        total, per_mode = self._approved_counts(mode)
        return (
            total >= self.settings.commute_ml_min_total_reports
            and per_mode >= self.settings.commute_ml_min_mode_reports
        )

    def _load(self, mode: str) -> dict[str, Any] | None:
        if mode in self._models:
            return self._models[mode]
        if not self.enabled_for(mode):
            return None

        try:
            raw = download_bytes(f"models/commute/{mode}_quantiles.joblib")
            bundle = joblib.load(BytesIO(raw))
            if not isinstance(bundle, dict):
                return None
            if not {"q25", "q50", "q75", "features"}.issubset(bundle):
                return None
            self._models[mode] = bundle
            return bundle
        except Exception:
            return None

    def predict(
        self,
        *,
        mode: str,
        distance_km: float,
        trip_minutes: float | None = None,
        traffic_level: str = "unknown",
        hour: int = 12,
        weekday: int = 0,
    ) -> dict[str, Any] | None:
        bundle = self._load(mode)
        if not bundle:
            return None

        traffic = {"unknown": 0, "light": 1, "normal": 2, "heavy": 3}.get(traffic_level, 0)
        values = {
            "distance_km": max(0.05, float(distance_km)),
            "trip_minutes": max(1.0, float(trip_minutes or distance_km * 8)),
            "traffic_level_encoded": float(traffic),
            "hour": float(max(0, min(23, hour))),
            "weekday": float(max(0, min(6, weekday))),
        }
        features = list(bundle["features"])
        row = np.array([[values.get(name, 0.0) for name in features]], dtype=float)

        try:
            q25 = float(bundle["q25"].predict(row)[0])
            q50 = float(bundle["q50"].predict(row)[0])
            q75 = float(bundle["q75"].predict(row)[0])
        except Exception:
            return None

        ordered = sorted([q25, q50, q75])
        low = max(5, round(ordered[0] / 5) * 5)
        median = max(low, round(ordered[1] / 5) * 5)
        high = max(median, round(ordered[2] / 5) * 5)
        return {
            "low": low,
            "median": median,
            "high": high,
            "fareType": "estimated",
            "source": "Verified-report quantile ML model",
            "confidence": "Medium",
            "model": "GradientBoostingRegressor quantile",
        }
