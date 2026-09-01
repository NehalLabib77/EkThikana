from __future__ import annotations

import math
from typing import Any

from app.services.commute.crowd import CrowdFareRepository
from app.services.commute.data_repository import get_commute_repository
from app.services.commute.ml_fare import MLFarePredictionService


class BusFareService:
    def __init__(self, repo=None) -> None:
        self.repo = repo or get_commute_repository()

    def lookup(self, origin: str, destination: str) -> list[dict[str, Any]]:
        return self.repo.official_bus_fares(origin, destination)

    def one_transfer(self, origin: str, destination: str) -> list[dict[str, Any]]:
        return self.repo.official_bus_one_transfer(origin, destination)


class MetroFareService:
    def __init__(self, repo=None) -> None:
        self.repo = repo or get_commute_repository()

    def lookup(self, origin: str, destination: str) -> dict[str, Any] | None:
        return self.repo.metro_fare(origin, destination)


class CNGFareService:
    def __init__(self, repo=None) -> None:
        self.repo = repo or get_commute_repository()
        self.crowd = CrowdFareRepository()

    def estimate(
        self,
        distance_km: float,
        *,
        origin: str = "",
        destination: str = "",
        waiting_minutes: float = 0,
    ) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []

        # Historical government meter rule from the supplied dataset.
        rule = self.repo.cng_rule()
        if rule and rule.get("baseFare") is not None:
            base = float(rule["baseFare"])
            included = float(rule.get("includedDistanceKm") or 0)
            per_km = float(rule.get("perKm") or 0)
            distance_charge = max(0.0, distance_km - included) * per_km
            # Waiting is deliberately omitted unless a machine-readable
            # numeric rule is available. We do not invent it.
            meter = math.ceil(base + distance_charge)
            results.append(
                {
                    "low": meter,
                    "median": meter,
                    "high": meter,
                    "fareType": "historical",
                    "confidence": "Low",
                    "source": rule.get("source"),
                    "warning": (
                        f"Historical meter rule effective {rule.get('effectiveFrom')}; "
                        "verify current legal rate before relying on it."
                    ),
                }
            )

        crowd = self.crowd.aggregate(
            mode="cng",
            origin_text=origin,
            destination_text=destination,
        )
        if crowd:
            results.insert(0, crowd)
        return results


class RickshawFareService:
    def __init__(self, repo=None) -> None:
        self.repo = repo or get_commute_repository()
        self.crowd = CrowdFareRepository()

    def estimate(
        self,
        distance_km: float,
        *,
        origin: str = "",
        destination: str = "",
    ) -> dict[str, Any] | None:
        crowd = self.crowd.aggregate(
            mode="rickshaw",
            origin_text=origin,
            destination_text=destination,
        )
        if crowd:
            return crowd
        # ML service is consulted by FareEngine after the activation gate.
        return self.repo.rickshaw_distance_fallback(distance_km)


class FareEngine:
    def __init__(self, repo=None) -> None:
        self.bus = BusFareService(repo=repo)
        self.metro = MetroFareService(repo=repo)
        self.cng = CNGFareService(repo=repo)
        self.rickshaw = RickshawFareService(repo=repo)
        self.ml = MLFarePredictionService()

    def options(
        self,
        *,
        origin_name: str,
        destination_name: str,
        distance_km: float,
        driving_minutes: int,
    ) -> list[dict[str, Any]]:
        options: list[dict[str, Any]] = []

        for bus in self.bus.lookup(origin_name, destination_name)[:3]:
            options.append(
                {
                    "mode": "bus",
                    "label": "Bus",
                    "minutes": max(driving_minutes + 8, round(driving_minutes * 1.35)),
                    "fareLow": bus["fare"],
                    "fareHigh": bus["fare"],
                    "fareType": bus["fareType"],
                    "source": bus["source"],
                    "confidence": bus["confidence"],
                    "routeId": bus["routeId"],
                    "transfers": 0,
                    "walkingKm": None,
                }
            )

        if not any(o["mode"] == "bus" for o in options):
            for bus in self.bus.one_transfer(origin_name, destination_name)[:2]:
                options.append(
                    {
                        "mode": "bus",
                        "label": f"Bus • transfer at {bus['transferName']}",
                        "minutes": max(driving_minutes + 15, round(driving_minutes * 1.55)),
                        "fareLow": bus["fare"],
                        "fareHigh": bus["fare"],
                        "fareType": bus["fareType"],
                        "source": bus["source"],
                        "confidence": bus["confidence"],
                        "routeId": " + ".join(bus["routeIds"]),
                        "transfers": 1,
                        "walkingKm": None,
                    }
                )

        metro = self.metro.lookup(origin_name, destination_name)
        if metro:
            options.append(
                {
                    "mode": "metro",
                    "label": "Metro",
                    "minutes": max(10, round(driving_minutes * 0.75)),
                    "fareLow": metro["fare"],
                    "fareHigh": metro["fare"],
                    "fareType": metro["fareType"],
                    "source": metro["source"],
                    "confidence": metro["confidence"],
                    "routeId": metro["lineId"],
                    "transfers": 0,
                    "walkingKm": None,
                }
            )

        cng_estimates = self.cng.estimate(
            distance_km,
            origin=origin_name,
            destination=destination_name,
        )
        cng = cng_estimates[0] if cng_estimates else None
        # If no recent crowd market estimate exists, use ML only after its
        # approved-report activation gate; otherwise retain the historical
        # legal-rule estimate as clearly labeled fallback.
        if cng and cng.get("fareType") == "historical":
            predicted = self.ml.predict(
                mode="cng",
                distance_km=distance_km,
                trip_minutes=driving_minutes,
            )
            if predicted:
                cng = predicted
        if cng:
            options.append(
                {
                    "mode": "cng",
                    "label": "CNG",
                    "minutes": driving_minutes,
                    "fareLow": cng["q25"] if "q25" in cng else cng["low"],
                    "fareHigh": cng["q75"] if "q75" in cng else cng["high"],
                    "fareType": cng["fareType"],
                    "source": cng["source"],
                    "confidence": cng["confidence"],
                    "warning": cng.get("warning"),
                    "transfers": 0,
                    "walkingKm": 0,
                }
            )

        rickshaw = self.rickshaw.crowd.aggregate(
            mode="rickshaw",
            origin_text=origin_name,
            destination_text=destination_name,
        )
        if not rickshaw:
            rickshaw = self.ml.predict(
                mode="rickshaw",
                distance_km=distance_km,
                trip_minutes=max(driving_minutes + 5, round(driving_minutes * 1.25)),
            )
        if not rickshaw:
            rickshaw = self.rickshaw.repo.rickshaw_distance_fallback(distance_km)
        if rickshaw:
            options.append(
                {
                    "mode": "rickshaw",
                    "label": "Rickshaw",
                    "minutes": max(driving_minutes + 5, round(driving_minutes * 1.25)),
                    "fareLow": rickshaw["q25"] if "q25" in rickshaw else rickshaw["low"],
                    "fareHigh": rickshaw["q75"] if "q75" in rickshaw else rickshaw["high"],
                    "fareType": rickshaw["fareType"],
                    "source": rickshaw["source"],
                    "confidence": rickshaw["confidence"],
                    "warning": rickshaw.get("warning"),
                    "transfers": 0,
                    "walkingKm": 0,
                }
            )

        if distance_km <= 2.5:
            options.append(
                {
                    "mode": "walk",
                    "label": "Walk",
                    "minutes": max(1, round(distance_km / 4.5 * 60)),
                    "fareLow": 0,
                    "fareHigh": 0,
                    "fareType": "none",
                    "source": "Walking estimate",
                    "confidence": "High",
                    "transfers": 0,
                    "walkingKm": round(distance_km, 2),
                }
            )

        self._rank(options)
        return options

    @staticmethod
    def _confidence_score(value: str) -> float:
        return {
            "Authoritative": 1.0,
            "High": 0.85,
            "Medium": 0.65,
            "Low": 0.35,
        }.get(value, 0.2)

    def _rank(self, options: list[dict[str, Any]]) -> None:
        if not options:
            return

        max_time = max(float(o["minutes"]) for o in options) or 1
        max_fare = max(float(o["fareHigh"]) for o in options) or 1

        for option in options:
            time_score = float(option["minutes"]) / max_time
            fare_score = float(option["fareHigh"]) / max_fare
            walk = float(option.get("walkingKm") or 0)
            transfer = float(option.get("transfers") or 0)
            confidence_penalty = 1 - self._confidence_score(str(option["confidence"]))
            option["_score"] = (
                0.38 * time_score
                + 0.32 * fare_score
                + 0.10 * min(walk / 2, 1)
                + 0.08 * min(transfer, 2)
                + 0.12 * confidence_penalty
            )

        cheapest = min(options, key=lambda o: (o["fareHigh"], o["minutes"]))
        fastest = min(options, key=lambda o: (o["minutes"], o["fareHigh"]))
        recommended = min(options, key=lambda o: o["_score"])

        for option in options:
            option["badges"] = []
        # One option can hold several badges -- the cheapest ride is often
        # also the recommended one, and it says so rather than being listed
        # twice. Both arms of the old conditionals here did the same thing,
        # which made the branching read as if some case were handled.
        recommended["badges"].append("Recommended")
        cheapest["badges"].append("Cheapest")
        fastest["badges"].append("Fastest")

        options.sort(key=lambda o: (0 if "Recommended" in o["badges"] else 1, o["_score"]))
        for option in options:
            option.pop("_score", None)
