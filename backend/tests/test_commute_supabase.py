from __future__ import annotations

from types import SimpleNamespace
from typing import Any

from app.schemas import CommutePlaceInput, CommuteRoutesRequest
from app.services.commute.service import CommuteService
from app.services.commute.supabase_repository import COMMUTE_TABLES, CommuteSupabaseRepository


class FakeResponse:
    def __init__(self, data=None, count=None):
        self.data = data or []
        self.count = count


class FakeQuery:
    def __init__(self, client: "FakeClient", table: str):
        self.client = client
        self.table = table
        self.filters: list[tuple[str, str, Any]] = []
        self.max_rows: int | None = None
        self.want_count = False
        self.head = False

    def select(self, columns="*", count=None, head=False):
        self.want_count = count == "exact"
        self.head = bool(head)
        return self

    def eq(self, column, value):
        self.filters.append(("eq", column, value))
        return self

    def ilike(self, column, pattern):
        self.filters.append(("ilike", column, pattern))
        return self

    def in_(self, column, values):
        self.filters.append(("in", column, list(values)))
        return self

    def gte(self, column, value):
        self.filters.append(("gte", column, value))
        return self

    def lte(self, column, value):
        self.filters.append(("lte", column, value))
        return self

    def limit(self, value):
        self.max_rows = int(value)
        return self

    def execute(self):
        rows = [dict(r) for r in self.client.tables.get(self.table, [])]
        for op, column, value in self.filters:
            if op == "eq":
                rows = [r for r in rows if r.get(column) == value]
            elif op == "in":
                rows = [r for r in rows if r.get(column) in value]
            elif op == "gte":
                rows = [r for r in rows if r.get(column) is not None and r.get(column) >= value]
            elif op == "lte":
                rows = [r for r in rows if r.get(column) is not None and r.get(column) <= value]
            elif op == "ilike":
                needle = str(value).strip("%").lower()
                rows = [r for r in rows if needle in str(r.get(column) or "").lower()]
        count = len(rows)
        if self.max_rows is not None:
            rows = rows[: self.max_rows]
        return FakeResponse([] if self.head else rows, count=count if self.want_count else None)


class FakeTable:
    def __init__(self, client: "FakeClient", table: str):
        self.client = client
        self.name = table

    def select(self, columns="*", count=None, head=False):
        return FakeQuery(self.client, self.name).select(columns, count=count, head=head)


class FakeClient:
    def __init__(self, tables: dict[str, list[dict[str, Any]]]):
        self.tables = tables

    def table(self, name: str):
        return FakeTable(self, name)


class FakeRouting:
    async def search(self, query: str, limit: int = 8):
        return [{"displayName": query, "lat": 23.8, "lon": 90.4, "provider": "fake"}]

    async def route(self, origin, destination):
        return {
            "distanceKm": 8.0,
            "durationMinutes": 20,
            "polyline": [{"lat": origin.lat, "lon": origin.lon}, {"lat": destination.lat, "lon": destination.lon}],
            "provider": "fake",
        }


def _tables():
    return {
        "places": [
            {
                "place_id": "P1",
                "name_en": "Mirpur 10",
                "name_bn": "মিরপুর ১০",
                "normalized_name": "mirpur 10",
                "latitude": 23.8067,
                "longitude": 90.3687,
                "geocode_status": "verified",
                "source_id": "S1",
            },
            {
                "place_id": "P2",
                "name_en": "Motijheel",
                "name_bn": "মতিঝিল",
                "normalized_name": "motijheel",
                "latitude": 23.733,
                "longitude": 90.417,
                "geocode_status": "verified",
                "source_id": "S1",
            },
        ],
        "stop_aliases": [
            {
                "raw_stop_name": "Mirpur Ten",
                "normalized_stop_name": "mirpur ten",
                "canonical_place_id": "P1",
                "canonical_name_en": "Mirpur 10",
                "match_score": 0.99,
                "match_method": "manual",
                "needs_manual_review": False,
                "source_id": "S2",
            }
        ],
        "metro_stations": [
            {
                "station_id": "M1",
                "line_id": "MRT6",
                "station_order": 1,
                "name_en": "Mirpur 10",
                "name_bn": "মিরপুর ১০",
                "operational_status": "in_service",
                "live_routing_enabled": True,
                "latitude": 23.8067,
                "longitude": 90.3687,
                "source_id": "SM",
            },
            {
                "station_id": "M2",
                "line_id": "MRT6",
                "station_order": 2,
                "name_en": "Motijheel",
                "name_bn": "মতিঝিল",
                "operational_status": "in_service",
                "live_routing_enabled": True,
                "latitude": 23.733,
                "longitude": 90.417,
                "source_id": "SM",
            },
        ],
        "metro_fares": [
            {
                "line_id": "MRT6",
                "from_station_id": "M1",
                "to_station_id": "M2",
                "single_journey_fare_tk": 40,
                "mrt_rapid_pass_fare_tk": 36,
                "live_usable": True,
                "source_id": "MF",
            }
        ],
        "brta_fare_segments": [
            {
                "route_id": "R1",
                "from_place_id": "P1",
                "from_name_en": "Mirpur 10",
                "to_place_id": "P2",
                "to_name_en": "Motijheel",
                "distance_km": 8,
                "fare_tk": 25,
                "source_id": "BRTA",
            }
        ],
        "brta_route_stops": [
            {"route_id": "R1", "stop_sequence": 1, "place_id": "P1", "stop_name_en": "Mirpur 10", "cumulative_distance_km": 0},
            {"route_id": "R1", "stop_sequence": 2, "place_id": "P2", "stop_name_en": "Motijheel", "cumulative_distance_km": 8},
        ],
        "brta_routes": [
            {"route_id": "R1", "route_name_en": "R1", "fare_per_km_tk": 2.45, "minimum_fare_tk": 10, "live_use": True, "source_id": "BRTA"}
        ],
        "fare_rules": [],
        "bus_services": [],
        "bus_service_stops": [],
        "sources": [],
        "service_route_matches": [],
        "brta_graph_edges": [],
        "geocoding_queue": [],
        "transit_network_plan": [],
    }


def test_data_status_counts_all_tables():
    tables = _tables()
    repo = CommuteSupabaseRepository(client=FakeClient(tables))
    status = repo.data_status()
    assert status["ok"] is True
    assert set(status["tables"]) == set(COMMUTE_TABLES)
    assert status["tables"]["places"] == 2


def test_place_search_uses_alias_and_deduplicates():
    repo = CommuteSupabaseRepository(client=FakeClient(_tables()))
    rows = repo.search_places("Mirpur Ten")
    assert len(rows) == 1
    assert rows[0]["placeId"] == "P1"
    assert rows[0]["alias"] == "Mirpur Ten"


def test_bangla_place_search():
    repo = CommuteSupabaseRepository(client=FakeClient(_tables()))
    rows = repo.search_places("মিরপুর")
    assert rows and rows[0]["placeId"] == "P1"


def test_metro_fare_is_deterministic():
    repo = CommuteSupabaseRepository(client=FakeClient(_tables()))
    fare = repo.metro_fare("M1", "M2")
    assert fare is not None
    assert fare["fare"] == 40
    assert fare["fareType"] == "official"
    assert fare["confidence"] == "Authoritative"


def test_official_bus_segment_lookup():
    repo = CommuteSupabaseRepository(client=FakeClient(_tables()))
    fares = repo.official_bus_fares("P1", "P2")
    assert fares and fares[0]["fare"] == 25
    assert fares[0]["fareType"] == "official"


def test_nearby_stops_orders_by_distance():
    tables = _tables()
    tables["bus_service_stops"] = [
        {"service_id": "S1", "canonical_place_id": "P1", "canonical_name_en": "Mirpur 10"}
    ]
    repo = CommuteSupabaseRepository(client=FakeClient(tables))
    rows = repo.nearby_stops(23.8067, 90.3687, 2000)
    assert rows
    assert rows[0]["distanceM"] <= rows[-1]["distanceM"]


def test_routes_uses_supabase_repo_and_ranking():
    repo = CommuteSupabaseRepository(client=FakeClient(_tables()))
    service = CommuteService(repo=repo, routing_provider=FakeRouting())
    import asyncio

    result = asyncio.run(
        service.routes(
            CommuteRoutesRequest(
                origin=CommutePlaceInput(place_id="P1"),
                destination=CommutePlaceInput(place_id="P2"),
            )
        )
    )
    assert result["dataSource"] == "supabase"
    assert result["distanceKm"] == 8.0
    assert any(o["mode"] == "bus" for o in result["recommendations"])
    assert any("Recommended" in (o.get("badges") or []) for o in result["recommendations"])


def test_new_places_endpoint_requires_auth(client):
    response = client.get("/api/commute/places/search?q=Mirpur")
    assert response.status_code == 401
