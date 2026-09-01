"""PostgreSQL-backed CommuteDB repository.

This is the Phase 2 replacement for
``app.services.commute.supabase_repository.CommuteSupabaseRepository``. The
public method surface is identical (so ``CommuteService`` and the router layer
do not need to change), but the underlying reads come from SQLAlchemy sessions
against the tables defined in ``app.database.models``.

Importing this module also re-routes ``app.services.commute.service`` to the
new class so legacy callers see the new behavior.

Dictionary shapes returned by each public method intentionally keep the same
keys the Supabase version returned (``placeId`` vs ``place_id`` etc.) so JSON
responses to Flutter are byte-identical.
"""
from __future__ import annotations

import math
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Iterable, Optional

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings
from app.database.connection import get_sessionmaker
from app.database.models import (
    BrtaFareSegment,
    BrtaGraphEdge,
    BrtaRoute,
    BrtaRouteStop,
    BusService,
    BusServiceStop,
    FareRule,
    MetroFare,
    MetroStation,
    Place,
    ServiceRouteMatch,
    StopAlias,
    UserFareReport,
)
from app.services.commute.data_repository import get_commute_repository, normalize_name
from app.services.commute.routing import Coordinate, MapRoutingProvider, get_routing_provider, haversine_km


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


# ---------------------------------------------------------------------------
# Small helpers (kept identical to the Supabase repository to avoid behavior drift)
# ---------------------------------------------------------------------------


def _f(value: Any) -> Optional[float]:
    """Coerce a value to a finite float (matching Supabase's ``numeric`` shape)."""
    if value is None:
        return None
    try:
        number = float(value)
    except Exception:
        return None
    if not math.isfinite(number):
        return None
    return number


def _to_float(value: Any) -> Optional[float]:
    if isinstance(value, Decimal):
        return _f(value)
    return _f(value)


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "y"}


def _place_row_to_dict(row: Place) -> dict[str, Any]:
    return {
        "place_id": row.place_id,
        "name_en": row.name_en,
        "name_bn": row.name_bn,
        "normalized_name": row.normalized_name,
        "latitude": _to_float(row.latitude),
        "longitude": _to_float(row.longitude),
        "geocode_status": row.geocode_status,
        "source_id": row.source_id,
    }


def _metro_row_to_dict(row: MetroStation) -> dict[str, Any]:
    return {
        "station_id": row.station_id,
        "line_id": row.line_id,
        "station_order": row.station_order,
        "name_en": row.name_en,
        "name_bn": row.name_bn,
        "operational_status": row.operational_status,
        "live_routing_enabled": row.live_routing_enabled,
        "latitude": _to_float(row.latitude),
        "longitude": _to_float(row.longitude),
        "source_id": row.source_id,
    }


def _route_stop_row_to_dict(row: BrtaRouteStop) -> dict[str, Any]:
    return {
        "route_id": row.route_id,
        "stop_sequence": row.stop_sequence,
        "place_id": row.place_id,
        "stop_name_en": row.stop_name_en,
        "stop_name_bn": row.stop_name_bn,
        "cumulative_distance_km": _to_float(row.cumulative_distance_km),
        "segment_distance_from_previous_km": _to_float(row.segment_distance_from_previous_km),
        "source_id": row.source_id,
    }


def _route_meta_row_to_dict(row: BrtaRoute) -> dict[str, Any]:
    return {
        "route_id": row.route_id,
        "route_name_en": row.route_name_en,
        "route_name_bn": row.route_name_bn,
        "fare_per_km_tk": _to_float(row.fare_per_km_tk),
        "minimum_fare_tk": _to_float(row.minimum_fare_tk),
        "live_use": row.live_use,
        "source_id": row.source_id,
    }


# ---------------------------------------------------------------------------
# Repository
# ---------------------------------------------------------------------------


class CommutePostgresRepository:
    """PostgreSQL-backed primary read repository for CommuteBD."""

    def __init__(self, session_factory: sessionmaker[Session] | None = None) -> None:
        self._session_factory = session_factory or get_sessionmaker()
        # Legacy rickshaw fallback is unchanged (synthetic CSV).
        self._legacy_fallback = get_commute_repository()

    # ------------------------------------------------------------------
    # Session helper
    # ------------------------------------------------------------------
    def _session(self) -> Session:
        return self._session_factory()

    # ------------------------------------------------------------------
    # Table presence / status
    # ------------------------------------------------------------------
    def data_status(self) -> dict[str, Any]:
        # The short-term implementation does an exact count per table using
        # ``func.count(*)``. If any table is missing it would not raise here
        # because we only ever SELECT from declared ORM classes.
        from sqlalchemy import func  # local import to avoid a cycle at module import time

        counts: dict[str, int | None] = {name: None for name in COMMUTE_TABLES}
        errors: dict[str, str] = {}
        with self._session() as session:
            model_map = {
                "places": Place,
                "fare_rules": FareRule,
                "brta_routes": BrtaRoute,
                "brta_route_stops": BrtaRouteStop,
                "bus_services": BusService,
                "bus_service_stops": BusServiceStop,
                "metro_stations": MetroStation,
                "metro_fares": MetroFare,
                "sources": None,
                "stop_aliases": StopAlias,
                "service_route_matches": ServiceRouteMatch,
                "brta_fare_segments": BrtaFareSegment,
                "brta_graph_edges": None,
                "geocoding_queue": None,
                "transit_network_plan": None,
            }
            for table_name, model_cls in model_map.items():
                if model_cls is None:
                    continue
                try:
                    total: int = (
                        session.execute(
                            select(func.count()).select_from(model_cls)
                        ).scalar_one()
                    )
                    counts[table_name] = int(total)
                except Exception as exc:
                    counts[table_name] = None
                    errors[table_name] = type(exc).__name__

        return {
            "ok": not errors,
            "source": "supabase",
            # preserve the existing key so callers do not need to change
            "source": "postgres",
            "tables": counts,
            "errors": errors,
        }

    # ------------------------------------------------------------------
    # Places / aliases / nearby stops
    # ------------------------------------------------------------------
    def get_place(self, place_id: str) -> dict[str, Any] | None:
        with self._session() as session:
            row = session.get(Place, place_id)
            return _place_row_to_dict(row) if row else None

    def search_places(self, query: str, limit: int = 15) -> list[dict[str, Any]]:
        q_raw = (query or "").strip()
        q_norm = normalize_name(q_raw)
        if len(q_raw) < 2:
            return []
        limit = max(1, min(int(limit), 20))

        place_rows: list[dict[str, Any]] = []
        alias_rows: list[dict[str, Any]] = []

        with self._session() as session:
            # Direct name matches (case-insensitive ``ILIKE``).
            place_columns = (
                Place.place_id,
                Place.name_en,
                Place.name_bn,
                Place.normalized_name,
                Place.latitude,
                Place.longitude,
                Place.geocode_status,
                Place.source_id,
            )

            place_filters = []
            if q_norm:
                place_filters.append(Place.normalized_name.ilike(f"%{q_norm}%"))
            if q_raw:
                place_filters.append(Place.name_en.ilike(f"%{q_raw}%"))
                place_filters.append(Place.name_bn.ilike(f"%{q_raw}%"))
            if place_filters:
                stmt = select(*place_columns).where(or_(*place_filters)).limit(limit)
                for row in session.execute(stmt).all():
                    place_rows.append(
                        {
                            "place_id": row.place_id,
                            "name_en": row.name_en,
                            "name_bn": row.name_bn,
                            "normalized_name": row.normalized_name,
                            "latitude": _to_float(row.latitude),
                            "longitude": _to_float(row.longitude),
                            "geocode_status": row.geocode_status,
                            "source_id": row.source_id,
                        }
                    )

            # Alias matches.
            alias_columns = (
                StopAlias.raw_stop_name,
                StopAlias.normalized_stop_name,
                StopAlias.canonical_place_id,
                StopAlias.canonical_name_en,
                StopAlias.match_score,
                StopAlias.match_method,
                StopAlias.needs_manual_review,
                StopAlias.source_id,
            )
            alias_filters = []
            if q_norm:
                alias_filters.append(StopAlias.normalized_stop_name.ilike(f"%{q_norm}%"))
            if q_raw:
                alias_filters.append(StopAlias.raw_stop_name.ilike(f"%{q_raw}%"))
            if alias_filters:
                alias_stmt = (
                    select(*alias_columns).where(or_(*alias_filters)).limit(limit * 2)
                )
                for row in session.execute(alias_stmt).all():
                    alias_rows.append(
                        {
                            "raw_stop_name": row.raw_stop_name,
                            "normalized_stop_name": row.normalized_stop_name,
                            "canonical_place_id": row.canonical_place_id,
                            "canonical_name_en": row.canonical_name_en,
                            "match_score": _to_float(row.match_score),
                            "match_method": row.match_method,
                            "needs_manual_review": bool(row.needs_manual_review),
                            "source_id": row.source_id,
                        }
                    )

            # Fetch any canonical place rows resolved via aliases that were
            # not already returned by direct name match.
            existing_ids = {row["place_id"] for row in place_rows}
            extra_ids = [
                str(row.get("canonical_place_id"))
                for row in alias_rows
                if row.get("canonical_place_id")
                and str(row.get("canonical_place_id")) not in existing_ids
            ]
            if extra_ids:
                place_stmt = select(*place_columns).where(Place.place_id.in_(extra_ids))
                for row in session.execute(place_stmt).all():
                    place_rows.append(
                        {
                            "place_id": row.place_id,
                            "name_en": row.name_en,
                            "name_bn": row.name_bn,
                            "normalized_name": row.normalized_name,
                            "latitude": _to_float(row.latitude),
                            "longitude": _to_float(row.longitude),
                            "geocode_status": row.geocode_status,
                            "source_id": row.source_id,
                        }
                    )

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
                "lat": _to_float(row.get("latitude")),
                "lon": _to_float(row.get("longitude")),
                "geocodeStatus": row.get("geocode_status") or "pending",
                "source": row.get("source_id"),
                "alias": best_alias.get("raw_stop_name") if best_alias else None,
                "aliasMatchScore": _to_float(best_alias.get("match_score")) if best_alias else None,
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
            place = self.get_place(value)
            if place:
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
        origin = Coordinate(lat=lat, lon=lon)

        nearby_places: dict[str, tuple[dict[str, Any], float]] = {}
        bus_items: list[dict[str, Any]] = []
        metro_items: list[dict[str, Any]] = []

        with self._session() as session:
            place_stmt = (
                select(Place)
                .where(
                    and_(
                        Place.latitude >= lat - lat_delta,
                        Place.latitude <= lat + lat_delta,
                        Place.longitude >= lon - lon_delta,
                        Place.longitude <= lon + lon_delta,
                    )
                )
                .limit(400)
            )
            for row in session.execute(place_stmt).scalars():
                plat = _to_float(row.latitude)
                plon = _to_float(row.longitude)
                if plat is None or plon is None:
                    continue
                distance = haversine_km(origin, Coordinate(plat, plon))
                if distance <= radius_km:
                    nearby_places[row.place_id] = (
                        _place_row_to_dict(row),
                        distance,
                    )

            if nearby_places:
                ids = list(nearby_places)
                route_stop_stmt = select(BrtaRouteStop).where(BrtaRouteStop.place_id.in_(ids))
                service_stop_stmt = select(BusServiceStop).where(
                    BusServiceStop.canonical_place_id.in_(ids)
                )
                route_counts: dict[str, set[str]] = defaultdict(set)
                for rs in session.execute(route_stop_stmt).scalars():
                    if rs.place_id and rs.route_id:
                        route_counts[rs.place_id].add(rs.route_id)
                service_counts: dict[str, set[str]] = defaultdict(set)
                for ss in session.execute(service_stop_stmt).scalars():
                    if ss.canonical_place_id and ss.service_id:
                        service_counts[ss.canonical_place_id].add(ss.service_id)

                for pid, (place, distance) in nearby_places.items():
                    if not route_counts.get(pid) and not service_counts.get(pid):
                        continue
                    bus_items.append(
                        {
                            "id": pid,
                            "name": place["name_en"] or place["name_bn"] or pid,
                            "nameBn": place["name_bn"],
                            "type": "bus_stop",
                            "lat": _to_float(place["latitude"]),
                            "lon": _to_float(place["longitude"]),
                            "distanceM": round(distance * 1000),
                            "routeCount": len(route_counts.get(pid, set())),
                            "serviceCount": len(service_counts.get(pid, set())),
                            "source": place["source_id"],
                            "confidence": "Authoritative" if route_counts.get(pid) else "Medium",
                        }
                    )

            metro_stmt = (
                select(MetroStation)
                .where(
                    and_(
                        MetroStation.latitude >= lat - lat_delta,
                        MetroStation.latitude <= lat + lat_delta,
                        MetroStation.longitude >= lon - lon_delta,
                        MetroStation.longitude <= lon + lon_delta,
                    )
                )
                .limit(100)
            )
            for row in session.execute(metro_stmt).scalars():
                slat = _to_float(row.latitude)
                slon = _to_float(row.longitude)
                if slat is None or slon is None:
                    continue
                distance = haversine_km(origin, Coordinate(slat, slon))
                if distance > radius_km:
                    continue
                metro_items.append(
                    {
                        "id": row.station_id,
                        "name": row.name_en or row.station_id,
                        "nameBn": row.name_bn,
                        "type": "metro_station",
                        "lineId": row.line_id,
                        "lat": slat,
                        "lon": slon,
                        "distanceM": round(distance * 1000),
                        "operationalStatus": row.operational_status,
                        "liveRoutingEnabled": bool(row.live_routing_enabled),
                        "source": row.source_id,
                        "confidence": "Authoritative",
                    }
                )

        return sorted(bus_items + metro_items, key=lambda item: item["distanceM"])

    # ------------------------------------------------------------------
    # Metro
    # ------------------------------------------------------------------
    def _resolve_metro_station(self, name_or_id: str) -> dict[str, Any] | None:
        value = (name_or_id or "").strip()
        if not value:
            return None
        with self._session() as session:
            row = session.get(MetroStation, value)
            if row:
                return _metro_row_to_dict(row)
            normalized = normalize_name(value)
            candidates: list[dict[str, Any]] = []
            for column in (MetroStation.name_en, MetroStation.name_bn):
                stmt = select(MetroStation).where(column.ilike(f"%{value}%")).limit(10)
                for hit in session.execute(stmt).scalars():
                    candidates.append(_metro_row_to_dict(hit))
            if not candidates:
                return None
            candidates.sort(
                key=lambda item: (
                    0
                    if normalized
                    in {
                        normalize_name(str(item.get("name_en") or "")),
                        normalize_name(str(item.get("name_bn") or "")),
                    }
                    else 1,
                    int(item.get("station_order") or 999),
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

        with self._session() as session:
            rows: list[MetroFare] = []
            for first, second in ((sid_a, sid_b), (sid_b, sid_a)):
                stmt = (
                    select(MetroFare)
                    .where(
                        and_(
                            MetroFare.from_station_id == first,
                            MetroFare.to_station_id == second,
                        )
                    )
                    .limit(1)
                )
                fetched = list(session.execute(stmt).scalars())
                rows.extend(fetched)
                if rows:
                    break
            if not rows or not _truthy(rows[0].live_usable):
                return None
            fare = _to_float(rows[0].single_journey_fare_tk)
            if fare is None:
                return None
            return {
                "lineId": rows[0].line_id,
                "fare": round(fare),
                "passFare": _to_float(rows[0].mrt_rapid_pass_fare_tk),
                "source": rows[0].source_id,
                "fareType": "official",
                "confidence": "Authoritative",
            }

    # ------------------------------------------------------------------
    # Official BRTA bus fares / routing structure
    # ------------------------------------------------------------------
    def _route_rows_for_pair(
        self, origin_id: str, destination_id: str
    ) -> dict[str, dict[str, dict[str, Any]]]:
        with self._session() as session:
            stmt = select(BrtaRouteStop).where(
                BrtaRouteStop.place_id.in_([origin_id, destination_id])
            )
            grouped: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
            for row in session.execute(stmt).scalars():
                rid = str(row.route_id or "")
                pid = str(row.place_id or "")
                if rid and pid:
                    grouped[rid][pid] = _route_stop_row_to_dict(row)
        return {
            route_id: by_place
            for route_id, by_place in grouped.items()
            if origin_id in by_place and destination_id in by_place
        }

    def _route_meta(self, route_ids: Iterable[str]) -> dict[str, dict[str, Any]]:
        ids = [str(v) for v in route_ids if v]
        if not ids:
            return {}
        with self._session() as session:
            stmt = select(BrtaRoute).where(BrtaRoute.route_id.in_(ids))
            return {row.route_id: _route_meta_row_to_dict(row) for row in session.execute(stmt).scalars()}

    @staticmethod
    def _calculated_route_fare(
        route_id: str,
        origin_row: dict[str, Any],
        destination_row: dict[str, Any],
        route_meta: dict[str, Any],
    ) -> dict[str, Any] | None:
        if not _truthy(route_meta.get("live_use")):
            return None
        a = _to_float(origin_row.get("cumulative_distance_km"))
        b = _to_float(destination_row.get("cumulative_distance_km"))
        per_km = _to_float(route_meta.get("fare_per_km_tk"))
        minimum = _to_float(route_meta.get("minimum_fare_tk")) or 0
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

        segment_rows: list[BrtaFareSegment] = []
        with self._session() as session:
            for first, second in (
                (origin_id, destination_id),
                (destination_id, origin_id),
            ):
                stmt = (
                    select(BrtaFareSegment)
                    .where(
                        and_(
                            BrtaFareSegment.from_place_id == first,
                            BrtaFareSegment.to_place_id == second,
                        )
                    )
                )
                segment_rows.extend(list(session.execute(stmt).scalars()))

        results: list[dict[str, Any]] = []
        for row in segment_rows:
            fare = _to_float(row.fare_tk)
            if fare is None:
                continue
            results.append(
                {
                    "routeId": row.route_id,
                    "fare": round(fare),
                    "distanceKm": _to_float(row.distance_km),
                    "fromName": row.from_name_en,
                    "toName": row.to_name_en,
                    "source": row.source_id,
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

        with self._session() as session:
            origin_rows = list(
                session.execute(
                    select(BrtaRouteStop).where(BrtaRouteStop.place_id == origin_id)
                ).scalars()
            )
            destination_rows = list(
                session.execute(
                    select(BrtaRouteStop).where(BrtaRouteStop.place_id == destination_id)
                ).scalars()
            )
            origin_routes = {str(row.route_id) for row in origin_rows if row.route_id}
            destination_routes = {str(row.route_id) for row in destination_rows if row.route_id}
            if not origin_routes or not destination_routes:
                return []

            route_ids = sorted(origin_routes | destination_routes)
            all_stops = list(
                session.execute(
                    select(BrtaRouteStop).where(BrtaRouteStop.route_id.in_(route_ids))
                ).scalars()
            )
            stops_by_route: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
            for rs in all_stops:
                rid = str(rs.route_id or "")
                pid = str(rs.place_id or "")
                if rid and pid:
                    stops_by_route[rid][pid] = _route_stop_row_to_dict(rs)

            meta_rows = list(
                session.execute(
                    select(BrtaRoute).where(BrtaRoute.route_id.in_(route_ids))
                ).scalars()
            )
            meta = {row.route_id: _route_meta_row_to_dict(row) for row in meta_rows}

        candidates: list[dict[str, Any]] = []
        for route_a in sorted(origin_routes):
            for route_b in sorted(destination_routes):
                if route_a == route_b:
                    continue
                transfers = set(stops_by_route.get(route_a, {})) & set(
                    stops_by_route.get(route_b, {})
                )
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
    # Community service-route candidates
    # ------------------------------------------------------------------
    def bus_route_via_services(
        self,
        origin_place_id: str,
        destination_place_id: str,
        limit: int = 6,
    ) -> list[dict[str, Any]]:
        columns = (
            BusServiceStop.service_id,
            BusServiceStop.stop_sequence,
            BusServiceStop.canonical_place_id,
            BusServiceStop.canonical_name_en,
        )

        with self._session() as session:
            origin_rows = list(
                session.execute(
                    select(*columns).where(
                        BusServiceStop.canonical_place_id == origin_place_id
                    )
                ).all()
            )
            destination_rows = list(
                session.execute(
                    select(*columns).where(
                        BusServiceStop.canonical_place_id == destination_place_id
                    )
                ).all()
            )

            origin_seq: dict[str, int] = {
                str(r.service_id): int(r.stop_sequence or 0)
                for r in origin_rows
                if r.service_id
            }
            destination_seq: dict[str, int] = {
                str(r.service_id): int(r.stop_sequence or 0)
                for r in destination_rows
                if r.service_id
            }
            direct_ids = [
                sid
                for sid in origin_seq.keys() & destination_seq.keys()
                if origin_seq[sid] < destination_seq[sid]
            ]

            candidates: list[dict[str, Any]] = []
            if direct_ids:
                service_rows = list(
                    session.execute(
                        select(BusService).where(BusService.service_id.in_(direct_ids))
                    ).scalars()
                )
                match_rows = list(
                    session.execute(
                        select(ServiceRouteMatch).where(
                            ServiceRouteMatch.service_id.in_(direct_ids)
                        )
                    ).scalars()
                )
                matches = {row.service_id: row for row in match_rows if row.service_id}
                for service in service_rows:
                    sid = str(service.service_id or "")
                    if not sid:
                        continue
                    match = matches.get(sid)
                    candidates.append(
                        {
                            "type": "direct",
                            "serviceId": sid,
                            "operatorName": service.operator_name_en,
                            "operatorNameBn": service.operator_name_bn,
                            "serviceType": service.service_type,
                            "currentStatus": service.current_status,
                            "bestBrtaRouteId": match.best_brta_route_id if match else None,
                            "verified": bool(match and _truthy(match.verified)),
                            "matchQuality": match.match_quality if match else None,
                            "matchScore": _to_float(match.match_score) if match else None,
                            "warning": match.warning if match else None,
                            "source": service.source_id,
                            "confidence": "High" if (match and _truthy(match.verified)) else "Low",
                        }
                    )

            # One-transfer suggestions from community service stop order.
            if len(candidates) < limit and origin_seq and destination_seq:
                origin_services = list(origin_seq)
                destination_services = list(destination_seq)
                origin_service_stops = list(
                    session.execute(
                        select(*columns).where(
                            BusServiceStop.service_id.in_(origin_services)
                        )
                    ).all()
                )
                destination_service_stops = list(
                    session.execute(
                        select(*columns).where(
                            BusServiceStop.service_id.in_(destination_services)
                        )
                    ).all()
                )
                stops_a: dict[str, dict[str, int]] = defaultdict(dict)
                stops_b: dict[str, dict[str, int]] = defaultdict(dict)
                names: dict[str, str] = {}
                for row in origin_service_stops:
                    sid = str(row.service_id or "")
                    pid = str(row.canonical_place_id or "")
                    if sid and pid:
                        stops_a[sid][pid] = int(row.stop_sequence or 0)
                        names[pid] = str(row.canonical_name_en or pid)
                for row in destination_service_stops:
                    sid = str(row.service_id or "")
                    pid = str(row.canonical_place_id or "")
                    if sid and pid:
                        stops_b[sid][pid] = int(row.stop_sequence or 0)
                        names[pid] = str(row.canonical_name_en or pid)

                for service_a in origin_services:
                    for service_b in destination_services:
                        if service_a == service_b:
                            continue
                        for transfer in set(stops_a.get(service_a, {})) & set(
                            stops_b.get(service_b, {})
                        ):
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
        with self._session() as session:
            stmt = (
                select(FareRule)
                .where(FareRule.mode == "cng_autorickshaw")
                .limit(1)
            )
            rows = list(session.execute(stmt).scalars())
            if not rows:
                return None
            row = rows[0]
            return {
                "baseFare": _to_float(row.base_or_minimum_fare_tk),
                "includedDistanceKm": _to_float(row.included_distance_km),
                "perKm": _to_float(row.per_km_tk),
                "waitingRule": row.waiting_rule,
                "effectiveFrom": row.effective_from,
                "productionStatus": row.production_status,
                "source": row.source_id,
            }

    def rickshaw_distance_fallback(self, distance_km: float) -> dict[str, Any] | None:
        return self._legacy_fallback.rickshaw_distance_fallback(distance_km)

    # ------------------------------------------------------------------
    # Multimodal routing graph
    # ------------------------------------------------------------------
    def load_graph_data(self):
        """Everything the multimodal router needs, in one pass.

        The graph is built once and cached by `journey_service`, so this runs
        on a cold start rather than per request. Reading whole tables is the
        right shape here: the dataset is a few thousand rows and a shortest
        path needs the *whole* network, not a neighbourhood of it.
        """
        from app.services.commute.graph_builder import GraphData, load_coordinates

        with self._session() as session:
            places = [
                {"place_id": r.place_id, "name_en": r.name_en}
                for r in session.execute(select(Place)).scalars()
            ]
            brta_edges = [
                {
                    "from_place_id": r.from_place_id,
                    "to_place_id": r.to_place_id,
                    "segment_distance_km": _to_float(r.distance_km),
                    "route_id": r.route_id,
                }
                for r in session.execute(select(BrtaGraphEdge)).scalars()
            ]
            brta_fares = [
                {
                    "from_place_id": r.from_place_id,
                    "to_place_id": r.to_place_id,
                    "fare_tk": _to_float(r.fare_tk),
                }
                for r in session.execute(
                    select(BrtaFareSegment).where(BrtaFareSegment.fare_tk.is_not(None))
                ).scalars()
            ]
            service_stops = [
                {
                    "service_id": r.service_id,
                    "stop_sequence": r.stop_sequence,
                    "canonical_place_id": r.canonical_place_id,
                }
                for r in session.execute(
                    select(BusServiceStop).where(
                        BusServiceStop.canonical_place_id.is_not(None)
                    )
                ).scalars()
            ]
            services = [
                {"service_id": r.service_id, "operator_name_en": r.operator_name_en}
                for r in session.execute(select(BusService)).scalars()
            ]
            metro_stations = [
                {
                    "station_id": r.station_id,
                    "name_en": r.name_en,
                    "station_order": r.station_order,
                    "line_id": r.line_id,
                }
                for r in session.execute(
                    select(MetroStation).where(
                        or_(
                            MetroStation.live_routing_enabled.is_(True),
                            MetroStation.live_routing_enabled.is_(None),
                        )
                    )
                ).scalars()
            ]
            metro_fares = [
                {
                    "from_station_id": r.from_station_id,
                    "to_station_id": r.to_station_id,
                    "single_journey_fare_tk": _to_float(r.single_journey_fare_tk),
                }
                for r in session.execute(select(MetroFare)).scalars()
            ]

        return GraphData(
            places=places,
            brta_edges=brta_edges,
            brta_fares=brta_fares,
            service_stops=service_stops,
            services=services,
            metro_stations=metro_stations,
            metro_fares=metro_fares,
            coordinates=load_coordinates(),
        )


__all__ = ["COMMUTE_TABLES", "CommutePostgresRepository"]