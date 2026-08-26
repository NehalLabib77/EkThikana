from __future__ import annotations

import math
from collections import defaultdict
from typing import Any, Iterable

from supabase import create_client

from app.core.config import get_settings, normalize_supabase_url
from app.services.commute.data_repository import get_commute_repository, normalize_name
from app.services.commute.routing import Coordinate, haversine_km


COMMUTE_TABLES: tuple[str, ...] = (
    "places",
    "fare_rules",
    "brta_routes",
    "brta_route_stops",
    "bus_services",
    "bus_service_stops",
    "metro_stations",
    "metro_fares",
    "sources",
    "stop_aliases",
    "service_route_matches",
    "brta_fare_segments",
    "brta_graph_edges",
    "geocoding_queue",
    "transit_network_plan",
)


def _rows(response: Any) -> list[dict[str, Any]]:
    data = getattr(response, "data", None)
    return list(data) if isinstance(data, list) else []


def _number(value: Any) -> float | None:
    try:
        number = float(value)
        return number if math.isfinite(number) else None
    except Exception:
        return None


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "y"}


def _chunks(values: list[str], size: int = 150) -> Iterable[list[str]]:
    for index in range(0, len(values), size):
        yield values[index : index + size]


class CommuteSupabaseRepository:
    """Primary read repository for CommuteBD's Supabase/PostgreSQL dataset.

    Runtime routing/fare reads come from the remote structured tables. The
    bundled CSV repository is retained only for the intentionally synthetic
    rickshaw distance fallback, which is not imported as observed data.
    """

    def __init__(self, client: Any | None = None) -> None:
        settings = get_settings()
        url = normalize_supabase_url(settings.supabase_url)
        if client is None:
            if not url or not settings.supabase_service_role_key:
                raise RuntimeError("Supabase CommuteBD credentials are not configured")
            client = create_client(url, settings.supabase_service_role_key)
        self.client = client
        self._legacy_fallback = get_commute_repository()

    # ------------------------------------------------------------------
    # Generic helpers
    # ------------------------------------------------------------------
    def _select(self, table: str, columns: str = "*"):
        return self.client.table(table).select(columns)

    def _fetch_by_ids(
        self,
        table: str,
        id_column: str,
        ids: Iterable[str],
        columns: str = "*",
    ) -> list[dict[str, Any]]:
        unique = list(dict.fromkeys(str(v) for v in ids if v))
        results: list[dict[str, Any]] = []
        for chunk in _chunks(unique):
            if not chunk:
                continue
            response = self._select(table, columns).in_(id_column, chunk).execute()
            results.extend(_rows(response))
        return results

    def data_status(self) -> dict[str, Any]:
        counts: dict[str, int | None] = {}
        errors: dict[str, str] = {}
        for table in COMMUTE_TABLES:
            try:
                response = (
                    self.client.table(table)
                    .select("*", count="exact", head=True)
                    .execute()
                )
                count = getattr(response, "count", None)
                counts[table] = int(count) if count is not None else None
            except Exception as exc:
                counts[table] = None
                errors[table] = type(exc).__name__
        return {
            "ok": not errors,
            "source": "supabase",
            "tables": counts,
            "errors": errors,
        }

    # ------------------------------------------------------------------
    # Places / aliases / nearby stops
    # ------------------------------------------------------------------
    def get_place(self, place_id: str) -> dict[str, Any] | None:
        response = (
            self._select(
                "places",
                "place_id,name_en,name_bn,normalized_name,latitude,longitude,geocode_status,source_id",
            )
            .eq("place_id", place_id)
            .limit(1)
            .execute()
        )
        rows = _rows(response)
        return rows[0] if rows else None

    def search_places(self, query: str, limit: int = 15) -> list[dict[str, Any]]:
        q_raw = (query or "").strip()
        q_norm = normalize_name(q_raw)
        if len(q_raw) < 2:
            return []
        limit = max(1, min(int(limit), 20))
        place_rows: list[dict[str, Any]] = []
        alias_rows: list[dict[str, Any]] = []

        columns = "place_id,name_en,name_bn,normalized_name,latitude,longitude,geocode_status,source_id"
        # Separate ilike queries avoid a large untrusted PostgREST `or_` string.
        for column, needle in (
            ("normalized_name", q_norm),
            ("name_en", q_raw),
            ("name_bn", q_raw),
        ):
            if not needle:
                continue
            try:
                response = (
                    self._select("places", columns)
                    .ilike(column, f"%{needle}%")
                    .limit(limit)
                    .execute()
                )
                place_rows.extend(_rows(response))
            except Exception:
                continue

        alias_columns = (
            "raw_stop_name,normalized_stop_name,canonical_place_id,canonical_name_en,"
            "match_score,match_method,needs_manual_review,source_id"
        )
        for column, needle in (
            ("normalized_stop_name", q_norm),
            ("raw_stop_name", q_raw),
        ):
            if not needle:
                continue
            try:
                response = (
                    self._select("stop_aliases", alias_columns)
                    .ilike(column, f"%{needle}%")
                    .limit(limit * 2)
                    .execute()
                )
                alias_rows.extend(_rows(response))
            except Exception:
                continue

        canonical_ids = [
            str(row.get("canonical_place_id"))
            for row in alias_rows
            if row.get("canonical_place_id")
        ]
        if canonical_ids:
            try:
                place_rows.extend(
                    self._fetch_by_ids("places", "place_id", canonical_ids, columns)
                )
            except Exception:
                pass

        aliases_by_place: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for row in alias_rows:
            pid = str(row.get("canonical_place_id") or "")
            if pid:
                aliases_by_place[pid].append(row)

        unique: dict[str, dict[str, Any]] = {}
        for row in place_rows:
            pid = str(row.get("place_id") or "")
            if not pid:
                continue
            aliases = aliases_by_place.get(pid, [])
            best_alias = aliases[0] if aliases else None
            name_en = str(row.get("name_en") or "")
            name_bn = str(row.get("name_bn") or "")
            normalized = normalize_name(str(row.get("normalized_name") or name_en))
            exact = q_norm in {
                normalized,
                normalize_name(name_en),
                normalize_name(name_bn),
            }
            alias_exact = any(
                normalize_name(str(a.get("raw_stop_name") or "")) == q_norm
                or normalize_name(str(a.get("normalized_stop_name") or "")) == q_norm
                for a in aliases
            )
            score = 0 if exact else (1 if alias_exact else (2 if aliases else 3))
            item = {
                "placeId": pid,
                "nameEn": name_en,
                "nameBn": name_bn,
                "lat": _number(row.get("latitude")),
                "lon": _number(row.get("longitude")),
                "geocodeStatus": row.get("geocode_status") or "pending",
                "source": row.get("source_id"),
                "alias": best_alias.get("raw_stop_name") if best_alias else None,
                "aliasMatchScore": _number(best_alias.get("match_score")) if best_alias else None,
                "needsManualReview": bool(best_alias and _truthy(best_alias.get("needs_manual_review"))),
                "_score": score,
            }
            current = unique.get(pid)
            if current is None or item["_score"] < current["_score"]:
                unique[pid] = item

        results = sorted(
            unique.values(),
            key=lambda item: (item["_score"], item["nameEn"].lower()),
        )[:limit]
        for item in results:
            item.pop("_score", None)
        return results

    def resolve_place_id(self, name_or_id: str) -> str | None:
        value = (name_or_id or "").strip()
        if not value:
            return None
        try:
            if self.get_place(value):
                return value
        except Exception:
            pass
        results = self.search_places(value, limit=10)
        if not results:
            return None
        normalized = normalize_name(value)
        exact = [
            row
            for row in results
            if normalized
            in {
                normalize_name(str(row.get("nameEn") or "")),
                normalize_name(str(row.get("nameBn") or "")),
                normalize_name(str(row.get("alias") or "")),
            }
        ]
        return str((exact[0] if exact else results[0]).get("placeId") or "") or None

    def nearby_stops(self, lat: float, lon: float, radius_m: int = 1500) -> list[dict[str, Any]]:
        radius_m = max(100, min(int(radius_m), 10000))
        radius_km = radius_m / 1000.0
        lat_delta = radius_m / 111_320.0
        lon_scale = max(0.15, math.cos(math.radians(lat)))
        lon_delta = radius_m / (111_320.0 * lon_scale)

        place_response = (
            self._select(
                "places",
                "place_id,name_en,name_bn,latitude,longitude,geocode_status,source_id",
            )
            .gte("latitude", lat - lat_delta)
            .lte("latitude", lat + lat_delta)
            .gte("longitude", lon - lon_delta)
            .lte("longitude", lon + lon_delta)
            .limit(400)
            .execute()
        )
        nearby_places: dict[str, tuple[dict[str, Any], float]] = {}
        origin = Coordinate(lat=lat, lon=lon)
        for row in _rows(place_response):
            plat = _number(row.get("latitude"))
            plon = _number(row.get("longitude"))
            pid = str(row.get("place_id") or "")
            if plat is None or plon is None or not pid:
                continue
            distance = haversine_km(origin, Coordinate(plat, plon))
            if distance <= radius_km:
                nearby_places[pid] = (row, distance)

        bus_items: list[dict[str, Any]] = []
        if nearby_places:
            ids = list(nearby_places)
            route_stop_rows: list[dict[str, Any]] = []
            service_stop_rows: list[dict[str, Any]] = []
            try:
                route_stop_rows = self._fetch_by_ids(
                    "brta_route_stops",
                    "place_id",
                    ids,
                    "route_id,place_id,stop_name_en,stop_name_bn",
                )
            except Exception:
                route_stop_rows = []
            try:
                service_stop_rows = self._fetch_by_ids(
                    "bus_service_stops",
                    "canonical_place_id",
                    ids,
                    "service_id,canonical_place_id,canonical_name_en",
                )
            except Exception:
                service_stop_rows = []

            route_counts: dict[str, set[str]] = defaultdict(set)
            service_counts: dict[str, set[str]] = defaultdict(set)
            for row in route_stop_rows:
                pid = str(row.get("place_id") or "")
                if pid and row.get("route_id"):
                    route_counts[pid].add(str(row["route_id"]))
            for row in service_stop_rows:
                pid = str(row.get("canonical_place_id") or "")
                if pid and row.get("service_id"):
                    service_counts[pid].add(str(row["service_id"]))

            for pid, (place, distance) in nearby_places.items():
                if not route_counts.get(pid) and not service_counts.get(pid):
                    continue
                bus_items.append(
                    {
                        "id": pid,
                        "name": place.get("name_en") or place.get("name_bn") or pid,
                        "nameBn": place.get("name_bn"),
                        "type": "bus_stop",
                        "lat": _number(place.get("latitude")),
                        "lon": _number(place.get("longitude")),
                        "distanceM": round(distance * 1000),
                        "routeCount": len(route_counts.get(pid, set())),
                        "serviceCount": len(service_counts.get(pid, set())),
                        "source": place.get("source_id"),
                        "confidence": "Authoritative" if route_counts.get(pid) else "Medium",
                    }
                )

        metro_items: list[dict[str, Any]] = []
        try:
            metro_response = (
                self._select(
                    "metro_stations",
                    "station_id,line_id,name_en,name_bn,operational_status,live_routing_enabled,"
                    "latitude,longitude,geocode_status,source_id",
                )
                .gte("latitude", lat - lat_delta)
                .lte("latitude", lat + lat_delta)
                .gte("longitude", lon - lon_delta)
                .lte("longitude", lon + lon_delta)
                .limit(100)
                .execute()
            )
            for row in _rows(metro_response):
                slat = _number(row.get("latitude"))
                slon = _number(row.get("longitude"))
                if slat is None or slon is None:
                    continue
                distance = haversine_km(origin, Coordinate(slat, slon))
                if distance > radius_km:
                    continue
                metro_items.append(
                    {
                        "id": row.get("station_id"),
                        "name": row.get("name_en") or row.get("station_id"),
                        "nameBn": row.get("name_bn"),
                        "type": "metro_station",
                        "lineId": row.get("line_id"),
                        "lat": slat,
                        "lon": slon,
                        "distanceM": round(distance * 1000),
                        "operationalStatus": row.get("operational_status"),
                        "liveRoutingEnabled": _truthy(row.get("live_routing_enabled")),
                        "source": row.get("source_id"),
                        "confidence": "Authoritative",
                    }
                )
        except Exception:
            pass

        return sorted(bus_items + metro_items, key=lambda item: item["distanceM"])

    # ------------------------------------------------------------------
    # Metro
    # ------------------------------------------------------------------
    def _resolve_metro_station(self, name_or_id: str) -> dict[str, Any] | None:
        value = (name_or_id or "").strip()
        if not value:
            return None
        columns = (
            "station_id,line_id,station_order,name_en,name_bn,operational_status,live_routing_enabled,"
            "latitude,longitude,source_id"
        )
        try:
            response = self._select("metro_stations", columns).eq("station_id", value).limit(1).execute()
            rows = _rows(response)
            if rows:
                return rows[0]
        except Exception:
            pass
        normalized = normalize_name(value)
        candidates: list[dict[str, Any]] = []
        for column, needle in (("name_en", value), ("name_bn", value)):
            try:
                response = (
                    self._select("metro_stations", columns)
                    .ilike(column, f"%{needle}%")
                    .limit(10)
                    .execute()
                )
                candidates.extend(_rows(response))
            except Exception:
                continue
        if not candidates:
            return None
        candidates.sort(
            key=lambda row: (
                0
                if normalized
                in {
                    normalize_name(str(row.get("name_en") or "")),
                    normalize_name(str(row.get("name_bn") or "")),
                }
                else 1,
                int(row.get("station_order") or 999),
            )
        )
        return candidates[0]

    def metro_fare(self, origin: str, destination: str) -> dict[str, Any] | None:
        a = self._resolve_metro_station(origin)
        b = self._resolve_metro_station(destination)
        if not a or not b or a.get("station_id") == b.get("station_id"):
            return None
        for station in (a, b):
            if str(station.get("operational_status") or "").lower() != "in_service":
                return None
            if not _truthy(station.get("live_routing_enabled")):
                return None

        sid_a = str(a["station_id"])
        sid_b = str(b["station_id"])
        rows: list[dict[str, Any]] = []
        for first, second in ((sid_a, sid_b), (sid_b, sid_a)):
            response = (
                self._select(
                    "metro_fares",
                    "line_id,from_station_id,to_station_id,single_journey_fare_tk,"
                    "mrt_rapid_pass_fare_tk,live_usable,source_id",
                )
                .eq("from_station_id", first)
                .eq("to_station_id", second)
                .limit(1)
                .execute()
            )
            rows.extend(_rows(response))
            if rows:
                break
        if not rows or not _truthy(rows[0].get("live_usable")):
            return None
        fare = _number(rows[0].get("single_journey_fare_tk"))
        if fare is None:
            return None
        return {
            "lineId": rows[0].get("line_id"),
            "fare": round(fare),
            "passFare": _number(rows[0].get("mrt_rapid_pass_fare_tk")),
            "source": rows[0].get("source_id"),
            "fareType": "official",
            "confidence": "Authoritative",
        }

    # ------------------------------------------------------------------
    # Official BRTA bus fares / routing structure
    # ------------------------------------------------------------------
    def _route_rows_for_pair(self, origin_id: str, destination_id: str) -> dict[str, dict[str, dict[str, Any]]]:
        response = (
            self._select(
                "brta_route_stops",
                "route_id,stop_sequence,place_id,stop_name_en,stop_name_bn,cumulative_distance_km,source_id",
            )
            .in_("place_id", [origin_id, destination_id])
            .execute()
        )
        grouped: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
        for row in _rows(response):
            route_id = str(row.get("route_id") or "")
            place_id = str(row.get("place_id") or "")
            if route_id and place_id:
                grouped[route_id][place_id] = row
        return {
            route_id: by_place
            for route_id, by_place in grouped.items()
            if origin_id in by_place and destination_id in by_place
        }

    def _route_meta(self, route_ids: Iterable[str]) -> dict[str, dict[str, Any]]:
        rows = self._fetch_by_ids(
            "brta_routes",
            "route_id",
            route_ids,
            "route_id,route_name_en,route_name_bn,fare_per_km_tk,minimum_fare_tk,live_use,source_id",
        )
        return {str(row.get("route_id")): row for row in rows if row.get("route_id")}

    @staticmethod
    def _calculated_route_fare(
        route_id: str,
        origin_row: dict[str, Any],
        destination_row: dict[str, Any],
        route_meta: dict[str, Any],
    ) -> dict[str, Any] | None:
        if not _truthy(route_meta.get("live_use")):
            return None
        a = _number(origin_row.get("cumulative_distance_km"))
        b = _number(destination_row.get("cumulative_distance_km"))
        per_km = _number(route_meta.get("fare_per_km_tk"))
        minimum = _number(route_meta.get("minimum_fare_tk")) or 0
        if a is None or b is None or per_km is None:
            return None
        distance = abs(b - a)
        if distance <= 0:
            return None
        return {
            "routeId": route_id,
            "fare": int(math.ceil(max(minimum, distance * per_km))),
            "distanceKm": round(distance, 2),
            "source": route_meta.get("source_id"),
            "fareType": "official_rule_calculation",
            "confidence": "Authoritative",
        }

    def official_bus_fares(self, origin: str, destination: str) -> list[dict[str, Any]]:
        origin_id = self.resolve_place_id(origin)
        destination_id = self.resolve_place_id(destination)
        if not origin_id or not destination_id or origin_id == destination_id:
            return []

        segment_rows: list[dict[str, Any]] = []
        for first, second in ((origin_id, destination_id), (destination_id, origin_id)):
            response = (
                self._select(
                    "brta_fare_segments",
                    "route_id,from_place_id,from_name_en,to_place_id,to_name_en,distance_km,"
                    "fare_tk,fare_per_km_tk,minimum_fare_tk,source_id",
                )
                .eq("from_place_id", first)
                .eq("to_place_id", second)
                .execute()
            )
            segment_rows.extend(_rows(response))

        results: list[dict[str, Any]] = []
        for row in segment_rows:
            fare = _number(row.get("fare_tk"))
            if fare is None:
                continue
            results.append(
                {
                    "routeId": row.get("route_id"),
                    "fare": round(fare),
                    "distanceKm": _number(row.get("distance_km")),
                    "fromName": row.get("from_name_en"),
                    "toName": row.get("to_name_en"),
                    "source": row.get("source_id"),
                    "fareType": "official",
                    "confidence": "Authoritative",
                }
            )

        if not results:
            pairs = self._route_rows_for_pair(origin_id, destination_id)
            route_meta = self._route_meta(pairs.keys()) if pairs else {}
            for route_id, by_place in pairs.items():
                calculated = self._calculated_route_fare(
                    route_id,
                    by_place[origin_id],
                    by_place[destination_id],
                    route_meta.get(route_id, {}),
                )
                if calculated:
                    calculated["fromName"] = by_place[origin_id].get("stop_name_en")
                    calculated["toName"] = by_place[destination_id].get("stop_name_en")
                    results.append(calculated)

        unique: dict[tuple[str, int], dict[str, Any]] = {}
        for item in results:
            key = (str(item.get("routeId") or ""), int(item.get("fare") or 0))
            unique[key] = item
        return sorted(unique.values(), key=lambda row: (row["fare"], row.get("distanceKm") or 9999))

    def official_bus_route_distance_fares(self, origin: str, destination: str) -> list[dict[str, Any]]:
        # `official_bus_fares` already performs this fallback after exact
        # precomputed BRTA segments.
        return self.official_bus_fares(origin, destination)

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

        origin_rows = _rows(
            self._select("brta_route_stops", "route_id,place_id,cumulative_distance_km")
            .eq("place_id", origin_id)
            .execute()
        )
        destination_rows = _rows(
            self._select("brta_route_stops", "route_id,place_id,cumulative_distance_km")
            .eq("place_id", destination_id)
            .execute()
        )
        origin_routes = {str(row.get("route_id")) for row in origin_rows if row.get("route_id")}
        destination_routes = {str(row.get("route_id")) for row in destination_rows if row.get("route_id")}
        if not origin_routes or not destination_routes:
            return []

        route_ids = sorted(origin_routes | destination_routes)
        all_stops = self._fetch_by_ids(
            "brta_route_stops",
            "route_id",
            route_ids,
            "route_id,stop_sequence,place_id,stop_name_en,cumulative_distance_km",
        )
        stops_by_route: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
        for row in all_stops:
            rid = str(row.get("route_id") or "")
            pid = str(row.get("place_id") or "")
            if rid and pid:
                stops_by_route[rid][pid] = row
        meta = self._route_meta(route_ids)

        candidates: list[dict[str, Any]] = []
        for route_a in sorted(origin_routes):
            for route_b in sorted(destination_routes):
                if route_a == route_b:
                    continue
                transfers = set(stops_by_route.get(route_a, {})) & set(stops_by_route.get(route_b, {}))
                transfers.discard(origin_id)
                transfers.discard(destination_id)
                for transfer in transfers:
                    leg1 = self._calculated_route_fare(
                        route_a,
                        stops_by_route[route_a].get(origin_id, {}),
                        stops_by_route[route_a].get(transfer, {}),
                        meta.get(route_a, {}),
                    )
                    leg2 = self._calculated_route_fare(
                        route_b,
                        stops_by_route[route_b].get(transfer, {}),
                        stops_by_route[route_b].get(destination_id, {}),
                        meta.get(route_b, {}),
                    )
                    if not leg1 or not leg2:
                        continue
                    transfer_row = stops_by_route[route_a].get(transfer, {})
                    candidates.append(
                        {
                            "routeIds": [route_a, route_b],
                            "transferPlaceId": transfer,
                            "transferName": transfer_row.get("stop_name_en") or transfer,
                            "fare": int(leg1["fare"]) + int(leg2["fare"]),
                            "source": leg1.get("source") or leg2.get("source"),
                            "fareType": "official_rule_calculation",
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
        return sorted(unique.values(), key=lambda row: row["fare"])[: max(1, min(limit, 10))]

    # ------------------------------------------------------------------
    # Community service-route candidates (never silently authoritative)
    # ------------------------------------------------------------------
    def bus_route_via_services(
        self,
        origin_place_id: str,
        destination_place_id: str,
        limit: int = 6,
    ) -> list[dict[str, Any]]:
        columns = "service_id,stop_sequence,canonical_place_id,canonical_name_en"
        origin_rows = _rows(
            self._select("bus_service_stops", columns)
            .eq("canonical_place_id", origin_place_id)
            .execute()
        )
        destination_rows = _rows(
            self._select("bus_service_stops", columns)
            .eq("canonical_place_id", destination_place_id)
            .execute()
        )
        origin_seq = {str(r["service_id"]): int(r.get("stop_sequence") or 0) for r in origin_rows if r.get("service_id")}
        destination_seq = {
            str(r["service_id"]): int(r.get("stop_sequence") or 0)
            for r in destination_rows
            if r.get("service_id")
        }
        direct_ids = [
            sid
            for sid in origin_seq.keys() & destination_seq.keys()
            if origin_seq[sid] < destination_seq[sid]
        ]

        candidates: list[dict[str, Any]] = []
        if direct_ids:
            service_rows = self._fetch_by_ids(
                "bus_services",
                "service_id",
                direct_ids,
                "service_id,operator_name_en,operator_name_bn,service_type,current_status,source_id",
            )
            match_rows = self._fetch_by_ids(
                "service_route_matches",
                "service_id",
                direct_ids,
                "service_id,best_brta_route_id,match_score,match_quality,verified,warning",
            )
            matches = {str(row.get("service_id")): row for row in match_rows}
            for service in service_rows:
                sid = str(service.get("service_id") or "")
                match = matches.get(sid, {})
                candidates.append(
                    {
                        "type": "direct",
                        "serviceId": sid,
                        "operatorName": service.get("operator_name_en"),
                        "operatorNameBn": service.get("operator_name_bn"),
                        "serviceType": service.get("service_type"),
                        "currentStatus": service.get("current_status"),
                        "bestBrtaRouteId": match.get("best_brta_route_id"),
                        "verified": _truthy(match.get("verified")),
                        "matchQuality": match.get("match_quality"),
                        "matchScore": _number(match.get("match_score")),
                        "warning": match.get("warning"),
                        "source": service.get("source_id"),
                        "confidence": "High" if _truthy(match.get("verified")) else "Low",
                    }
                )

        # One-transfer suggestions from community service stop order. Scope all
        # rows to services touching the origin/destination instead of loading
        # the whole 3k-row table on every request.
        if len(candidates) < limit and origin_seq and destination_seq:
            origin_services = list(origin_seq)
            destination_services = list(destination_seq)
            origin_service_stops = self._fetch_by_ids(
                "bus_service_stops", "service_id", origin_services, columns
            )
            destination_service_stops = self._fetch_by_ids(
                "bus_service_stops", "service_id", destination_services, columns
            )
            stops_a: dict[str, dict[str, int]] = defaultdict(dict)
            stops_b: dict[str, dict[str, int]] = defaultdict(dict)
            names: dict[str, str] = {}
            for row in origin_service_stops:
                sid = str(row.get("service_id") or "")
                pid = str(row.get("canonical_place_id") or "")
                if sid and pid:
                    stops_a[sid][pid] = int(row.get("stop_sequence") or 0)
                    names[pid] = str(row.get("canonical_name_en") or pid)
            for row in destination_service_stops:
                sid = str(row.get("service_id") or "")
                pid = str(row.get("canonical_place_id") or "")
                if sid and pid:
                    stops_b[sid][pid] = int(row.get("stop_sequence") or 0)
                    names[pid] = str(row.get("canonical_name_en") or pid)

            for service_a in origin_services:
                for service_b in destination_services:
                    if service_a == service_b:
                        continue
                    for transfer in set(stops_a.get(service_a, {})) & set(stops_b.get(service_b, {})):
                        if transfer in {origin_place_id, destination_place_id}:
                            continue
                        if not (
                            origin_seq[service_a] < stops_a[service_a][transfer]
                            and stops_b[service_b][transfer] < destination_seq[service_b]
                        ):
                            continue
                        candidates.append(
                            {
                                "type": "one_transfer",
                                "serviceIds": [service_a, service_b],
                                "transferPlaceId": transfer,
                                "transferName": names.get(transfer, transfer),
                                "verified": False,
                                "matchQuality": "community_unverified",
                                "warning": "Community service combination; verify current operation before travel.",
                                "confidence": "Low",
                            }
                        )
                        if len(candidates) >= limit:
                            break
                    if len(candidates) >= limit:
                        break
                if len(candidates) >= limit:
                    break

        return candidates[:limit]

    # ------------------------------------------------------------------
    # Rules / low-confidence fallback
    # ------------------------------------------------------------------
    def cng_rule(self) -> dict[str, Any] | None:
        response = (
            self._select(
                "fare_rules",
                "fare_rule_id,mode,effective_from,base_or_minimum_fare_tk,included_distance_km,"
                "per_km_tk,waiting_rule,other_rule,production_status,source_id",
            )
            .eq("mode", "cng_autorickshaw")
            .limit(1)
            .execute()
        )
        rows = _rows(response)
        if not rows:
            return None
        row = rows[0]
        return {
            "baseFare": _number(row.get("base_or_minimum_fare_tk")),
            "includedDistanceKm": _number(row.get("included_distance_km")),
            "perKm": _number(row.get("per_km_tk")),
            "waitingRule": row.get("waiting_rule"),
            "effectiveFrom": row.get("effective_from"),
            "productionStatus": row.get("production_status"),
            "source": row.get("source_id"),
        }

    def rickshaw_distance_fallback(self, distance_km: float) -> dict[str, Any] | None:
        # The synthetic fallback dataset is intentionally not imported into
        # Supabase as observed truth. Preserve the existing explicitly-low-
        # confidence fallback for this one case only.
        return self._legacy_fallback.rickshaw_distance_fallback(distance_km)
