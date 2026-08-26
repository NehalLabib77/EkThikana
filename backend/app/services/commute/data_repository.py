from __future__ import annotations

import csv
import math
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

DATA_ROOT = Path(__file__).resolve().parents[3] / "data" / "commutebd" / "core_dataset" / "csv"


def _clean(value: str | None) -> str:
    return (value or "").strip()


def _number(value: str | None) -> float | None:
    try:
        number = float(value or "")
        return number if math.isfinite(number) else None
    except Exception:
        return None


def _read_csv(name: str) -> list[dict[str, str]]:
    path = DATA_ROOT / name
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def normalize_name(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[\(\)\[\],./_-]+", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


class CommuteDataRepository:
    """Read-only repository for the supplied CommuteBD rule/community dataset.

    The repository deliberately preserves source/status fields. Community
    tables are never silently upgraded to authoritative data.
    """

    def __init__(self) -> None:
        self.places = _read_csv("places.csv")
        self.brta_fare_segments = _read_csv("brta_fare_segments.csv")
        self.brta_routes = _read_csv("brta_routes.csv")
        self.brta_route_stops = _read_csv("brta_route_stops.csv")
        self.fare_rules = _read_csv("fare_rules.csv")
        self.metro_fares = _read_csv("metro_fares.csv")
        self.metro_stations = _read_csv("metro_stations.csv")
        self.bus_services = _read_csv("bus_services.csv")
        self.bus_service_stops = _read_csv("bus_service_stops.csv")
        self.service_route_matches = _read_csv("service_route_matches.csv")
        self.rickshaw_fallback = _read_csv("rickshaw_auto_estimated_fares.csv")

        self._place_by_id = {
            row["place_id"]: row for row in self.places if _clean(row.get("place_id"))
        }
        self._place_names: dict[str, str] = {}
        for row in self.places:
            pid = _clean(row.get("place_id"))
            for key in ("name_en", "name_bn", "normalized_name"):
                value = _clean(row.get(key))
                if pid and value:
                    self._place_names.setdefault(normalize_name(value), pid)

        self._metro_station_names: dict[str, str] = {}
        for row in self.metro_stations:
            sid = _clean(row.get("station_id"))
            for key in ("name_en", "name_bn"):
                value = _clean(row.get(key))
                if sid and value:
                    self._metro_station_names[normalize_name(value)] = sid

    def search_local_places(self, query: str, limit: int = 15) -> list[dict[str, Any]]:
        q = normalize_name(query)
        if len(q) < 2:
            return []
        scored: list[tuple[int, dict[str, Any]]] = []
        for row in self.places:
            en = _clean(row.get("name_en"))
            bn = _clean(row.get("name_bn"))
            norm = normalize_name(_clean(row.get("normalized_name")) or en)
            hay = " ".join([normalize_name(en), normalize_name(bn), norm])
            if q not in hay:
                continue
            score = 0 if norm == q or normalize_name(en) == q or normalize_name(bn) == q else 1
            scored.append(
                (
                    score,
                    {
                        "placeId": row.get("place_id"),
                        "nameEn": en,
                        "nameBn": bn,
                        "geocodeStatus": row.get("geocode_status") or "pending",
                        "source": row.get("source_id"),
                    },
                )
            )
        scored.sort(key=lambda item: (item[0], item[1]["nameEn"]))
        return [item[1] for item in scored[:limit]]

    def resolve_place_id(self, name_or_id: str) -> str | None:
        if name_or_id in self._place_by_id:
            return name_or_id
        normalized = normalize_name(name_or_id)
        if normalized in self._place_names:
            return self._place_names[normalized]
        # Conservative fuzzy fallback: prefer the longest local place name
        # contained in a provider display string (e.g. "Mirpur 10, Dhaka...").
        matches = [
            (len(name), name, pid)
            for name, pid in self._place_names.items()
            if normalized and (normalized in name or name in normalized)
        ]
        if not matches:
            return None
        matches.sort(reverse=True)
        top_len = matches[0][0]
        top_pids = list(dict.fromkeys(pid for length, _, pid in matches if length == top_len))
        return top_pids[0] if len(top_pids) == 1 else None


    def _route_distance_fare(
        self,
        route_id: str,
        from_place_id: str,
        to_place_id: str,
    ) -> dict[str, Any] | None:
        """Calculate fare from official BRTA route cumulative distance only.

        This deliberately never uses generic OSRM/Google road distance for
        official bus pricing.
        """
        route = next(
            (
                row
                for row in self.brta_routes
                if _clean(row.get("route_id")) == route_id
                and _clean(row.get("live_use")).lower() in {"yes", "true", "1"}
            ),
            None,
        )
        if not route:
            return None

        stops = [
            row
            for row in self.brta_route_stops
            if _clean(row.get("route_id")) == route_id
            and _clean(row.get("place_id")) in {from_place_id, to_place_id}
        ]
        by_place = {_clean(row.get("place_id")): row for row in stops}
        if from_place_id not in by_place or to_place_id not in by_place:
            return None

        a = _number(by_place[from_place_id].get("cumulative_distance_km"))
        b = _number(by_place[to_place_id].get("cumulative_distance_km"))
        per_km = _number(route.get("fare_per_km_tk"))
        minimum = _number(route.get("minimum_fare_tk"))
        if a is None or b is None or per_km is None:
            return None

        distance = abs(b - a)
        if distance <= 0:
            return None
        fare = max(minimum or 0, distance * per_km)
        # BRTA consumer fares are displayed as whole Tk; keep the calculation
        # deterministic and avoid false decimal precision.
        return {
            "routeId": route_id,
            "fare": int(math.ceil(fare)),
            "distanceKm": round(distance, 2),
            "source": route.get("source_id"),
            "fareType": "official_rule_calculation",
            "confidence": "Authoritative",
        }

    def official_bus_route_distance_fares(
        self,
        origin: str,
        destination: str,
    ) -> list[dict[str, Any]]:
        origin_id = self.resolve_place_id(origin)
        destination_id = self.resolve_place_id(destination)
        if not origin_id or not destination_id or origin_id == destination_id:
            return []

        routes_origin = {
            _clean(row.get("route_id"))
            for row in self.brta_route_stops
            if _clean(row.get("place_id")) == origin_id
        }
        routes_destination = {
            _clean(row.get("route_id"))
            for row in self.brta_route_stops
            if _clean(row.get("place_id")) == destination_id
        }

        results = []
        for route_id in sorted(routes_origin & routes_destination):
            fare = self._route_distance_fare(route_id, origin_id, destination_id)
            if fare:
                fare["fromName"] = self._place_by_id.get(origin_id, {}).get("name_en")
                fare["toName"] = self._place_by_id.get(destination_id, {}).get("name_en")
                results.append(fare)
        return sorted(results, key=lambda row: (row["fare"], row["distanceKm"]))

    def official_bus_fares(self, origin: str, destination: str) -> list[dict[str, Any]]:
        origin_id = self.resolve_place_id(origin)
        destination_id = self.resolve_place_id(destination)
        if not origin_id or not destination_id or origin_id == destination_id:
            return []

        results: list[dict[str, Any]] = []
        for row in self.brta_fare_segments:
            a = _clean(row.get("from_place_id"))
            b = _clean(row.get("to_place_id"))
            if {a, b} != {origin_id, destination_id}:
                continue
            fare = _number(row.get("fare_tk"))
            distance = _number(row.get("distance_km"))
            if fare is None:
                continue
            results.append(
                {
                    "routeId": row.get("route_id"),
                    "fare": round(fare),
                    "distanceKm": distance,
                    "fromName": row.get("from_name_en"),
                    "toName": row.get("to_name_en"),
                    "source": row.get("source_id"),
                    "fareType": "official",
                    "confidence": "Authoritative",
                }
            )

        # Deduplicate by route/fare while preserving the official source.
        seen: set[tuple[str, int]] = set()
        deduped: list[dict[str, Any]] = []
        for result in sorted(results, key=lambda r: (r["fare"], r["distanceKm"] or 9999)):
            key = (str(result["routeId"]), int(result["fare"]))
            if key in seen:
                continue
            seen.add(key)
            deduped.append(result)
        return deduped


    def official_bus_one_transfer(
        self,
        origin: str,
        destination: str,
        limit: int = 3,
    ) -> list[dict[str, Any]]:
        origin_id = self.resolve_place_id(origin)
        destination_id = self.resolve_place_id(destination)
        if not origin_id or not destination_id or origin_id == destination_id:
            return []

        routes_by_place: dict[str, set[str]] = {}
        stops_by_route: dict[str, list[dict[str, str]]] = {}
        for row in self.brta_route_stops:
            route = _clean(row.get("route_id"))
            place = _clean(row.get("place_id"))
            if not route or not place:
                continue
            routes_by_place.setdefault(place, set()).add(route)
            stops_by_route.setdefault(route, []).append(row)

        origin_routes = routes_by_place.get(origin_id, set())
        dest_routes = routes_by_place.get(destination_id, set())
        if not origin_routes or not dest_routes:
            return []

        # Fast route-specific fare index.
        fare_index: dict[tuple[str, frozenset[str]], dict[str, str]] = {}
        for row in self.brta_fare_segments:
            route = _clean(row.get("route_id"))
            a = _clean(row.get("from_place_id"))
            b = _clean(row.get("to_place_id"))
            if route and a and b:
                fare_index[(route, frozenset((a, b)))] = row

        candidates: list[dict[str, Any]] = []
        for route_a in origin_routes:
            for route_b in dest_routes:
                if route_a == route_b:
                    continue
                places_a = {
                    _clean(row.get("place_id"))
                    for row in stops_by_route.get(route_a, [])
                }
                places_b = {
                    _clean(row.get("place_id"))
                    for row in stops_by_route.get(route_b, [])
                }
                transfers = places_a & places_b
                transfers.discard(origin_id)
                transfers.discard(destination_id)
                for transfer in transfers:
                    leg1 = fare_index.get((route_a, frozenset((origin_id, transfer))))
                    leg2 = fare_index.get((route_b, frozenset((transfer, destination_id))))
                    calc1 = None if leg1 else self._route_distance_fare(route_a, origin_id, transfer)
                    calc2 = None if leg2 else self._route_distance_fare(route_b, transfer, destination_id)
                    fare1 = _number(leg1.get("fare_tk")) if leg1 else (calc1 or {}).get("fare")
                    fare2 = _number(leg2.get("fare_tk")) if leg2 else (calc2 or {}).get("fare")
                    if fare1 is None or fare2 is None:
                        continue
                    transfer_row = self._place_by_id.get(transfer, {})
                    source1 = leg1.get("source_id") if leg1 else (calc1 or {}).get("source")
                    source2 = leg2.get("source_id") if leg2 else (calc2 or {}).get("source")
                    candidates.append(
                        {
                            "routeIds": [route_a, route_b],
                            "transferPlaceId": transfer,
                            "transferName": transfer_row.get("name_en") or transfer,
                            "fare": round(float(fare1) + float(fare2)),
                            "source": source1 or source2,
                            "fareType": "official",
                            "confidence": "Authoritative",
                            "transfers": 1,
                        }
                    )

        unique: dict[tuple[str, str, str], dict[str, Any]] = {}
        for item in candidates:
            key = (
                str(item["routeIds"][0]),
                str(item["routeIds"][1]),
                str(item["transferPlaceId"]),
            )
            unique[key] = item
        return sorted(unique.values(), key=lambda x: x["fare"])[:limit]

    def _resolve_metro_station(self, name: str) -> str | None:
        normalized = normalize_name(name)
        exact = self._metro_station_names.get(normalized)
        if exact:
            return exact
        # Geocoders often return a full display address. Prefer the longest
        # contained station name so "Motijheel, Dhaka..." still resolves.
        matches = [
            (station_name, station_id)
            for station_name, station_id in self._metro_station_names.items()
            if station_name and station_name in normalized
        ]
        if not matches:
            return None
        matches.sort(key=lambda pair: len(pair[0]), reverse=True)
        return matches[0][1]

    def metro_fare(self, origin: str, destination: str) -> dict[str, Any] | None:
        a = self._resolve_metro_station(origin)
        b = self._resolve_metro_station(destination)
        if not a or not b or a == b:
            return None

        station_status = {
            row.get("station_id"): (
                _clean(row.get("operational_status")).lower(),
                _clean(row.get("live_routing_enabled")).lower(),
            )
            for row in self.metro_stations
        }
        for sid in (a, b):
            status, live = station_status.get(sid, ("", ""))
            if status != "in_service" or live != "yes":
                return None

        for row in self.metro_fares:
            f = _clean(row.get("from_station_id"))
            t = _clean(row.get("to_station_id"))
            if {f, t} != {a, b}:
                continue
            if _clean(row.get("live_usable")).lower() != "yes":
                return None
            fare = _number(row.get("single_journey_fare_tk"))
            if fare is None:
                return None
            return {
                "lineId": row.get("line_id"),
                "fare": round(fare),
                "passFare": _number(row.get("mrt_rapid_pass_fare_tk")),
                "source": row.get("source_id"),
                "fareType": "official",
                "confidence": "Authoritative",
            }
        return None

    def cng_rule(self) -> dict[str, Any] | None:
        for row in self.fare_rules:
            if _clean(row.get("mode")).lower() != "cng_autorickshaw":
                continue
            return {
                "baseFare": _number(row.get("base_or_minimum_fare_tk")),
                "includedDistanceKm": _number(row.get("included_distance_km")),
                "perKm": _number(row.get("per_km_tk")),
                "waitingRule": row.get("waiting_rule"),
                "effectiveFrom": row.get("effective_from"),
                "productionStatus": row.get("production_status"),
                "source": row.get("source_id"),
            }
        return None

    def rickshaw_distance_fallback(self, distance_km: float) -> dict[str, Any] | None:
        if not self.rickshaw_fallback or distance_km <= 0:
            return None
        nearest = min(
            self.rickshaw_fallback,
            key=lambda row: abs((_number(row.get("distance_km")) or 9999) - distance_km),
        )
        base = _number(nearest.get("rickshaw_estimated_fare_tk"))
        if base is None:
            return None
        # Dataset explicitly labels these as user-provided estimates, so the
        # app exposes them only as a low-confidence fallback range.
        low = max(10, round(base * 0.85 / 5) * 5)
        high = max(low, round(base * 1.20 / 5) * 5)
        return {
            "low": low,
            "median": round(base / 5) * 5,
            "high": high,
            "source": nearest.get("source_id"),
            "fareType": "unverified",
            "confidence": "Low",
            "warning": "Low-confidence fallback from supplied synthetic/user-assumption rows.",
        }


@lru_cache
def get_commute_repository() -> CommuteDataRepository:
    return CommuteDataRepository()
