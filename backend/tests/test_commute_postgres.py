"""CommuteDB PostgreSQL repository tests.

Phase 2 of the migration replaces the Supabase-backed
``CommuteSupabaseRepository`` with a SQLAlchemy-based
``CommutePostgresRepository``. These tests build the ORM schema on a
SQLite in-memory database, seed it with the fixtures the
``CommuteService`` consumes, and exercise the public repository API.
"""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


from app.database.connection import Base, get_engine, get_sessionmaker, reset_engine_cache
from app.database.models import (
    BrtaFareSegment,
    BrtaRoute,
    BrtaRouteStop,
    BusServiceStop,
    MetroFare,
    MetroStation,
    Place,
    StopAlias,
)
from app.database.repositories.postgres_repository import (
    COMMUTE_TABLES,
    CommutePostgresRepository,
)
from app.schemas import CommutePlaceInput, CommuteRoutesRequest
from app.services.commute.service import CommuteService


def _seed_tables():
    """Seed a SQLite in-memory DB with the canonical fixture set."""
    os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
    reset_engine_cache()
    engine = get_engine()
    Base.metadata.create_all(engine)
    Session = get_sessionmaker()
    with Session() as session:
        session.add_all(
            [
                Place(
                    place_id="P1",
                    name_en="Mirpur 10",
                    name_bn="\u09ae\u09bf\u09b0\u09aa\u09c1\u09b0 \u09e7\u09e6",
                    normalized_name="mirpur 10",
                    latitude=23.8067,
                    longitude=90.3687,
                    geocode_status="verified",
                    source_id="S1",
                ),
                Place(
                    place_id="P2",
                    name_en="Motijheel",
                    name_bn="\u09ae\u09a4\u09bf\u099d\u09bf\u09b2",
                    normalized_name="motijheel",
                    latitude=23.733,
                    longitude=90.417,
                    geocode_status="verified",
                    source_id="S1",
                ),
            ]
        )
        session.add(
            StopAlias(
                alias_id=1,
                raw_stop_name="Mirpur Ten",
                normalized_stop_name="mirpur ten",
                canonical_place_id="P1",
                canonical_name_en="Mirpur 10",
                match_score=0.99,
                match_method="manual",
                needs_manual_review=False,
                source_id="S2",
            )
        )
        session.add_all(
            [
                MetroStation(
                    station_id="M1",
                    line_id="MRT6",
                    station_order=1,
                    name_en="Mirpur 10",
                    name_bn="\u09ae\u09bf\u09b0\u09aa\u09c1\u09b0 \u09e7\u09e6",
                    operational_status="in_service",
                    live_routing_enabled=True,
                    latitude=23.8067,
                    longitude=90.3687,
                    source_id="SM",
                ),
                MetroStation(
                    station_id="M2",
                    line_id="MRT6",
                    station_order=2,
                    name_en="Motijheel",
                    name_bn="\u09ae\u09a4\u09bf\u099d\u09bf\u09b2",
                    operational_status="in_service",
                    live_routing_enabled=True,
                    latitude=23.733,
                    longitude=90.417,
                    source_id="SM",
                ),
            ]
        )
        session.add(
            MetroFare(
                line_id="MRT6",
                from_station_id="M1",
                to_station_id="M2",
                single_journey_fare_tk=40,
                mrt_rapid_pass_fare_tk=36,
                live_usable=True,
                source_id="MF",
            )
        )
        session.add(
            BrtaRoute(
                route_id="R1",
                route_name_en="R1",
                fare_per_km_tk=2.45,
                minimum_fare_tk=10,
                live_use=True,
                source_id="BRTA",
            )
        )
        session.add_all(
            [
                BrtaRouteStop(
                    route_id="R1",
                    stop_sequence=1,
                    place_id="P1",
                    stop_name_en="Mirpur 10",
                    cumulative_distance_km=0,
                ),
                BrtaRouteStop(
                    route_id="R1",
                    stop_sequence=2,
                    place_id="P2",
                    stop_name_en="Motijheel",
                    cumulative_distance_km=8,
                ),
            ]
        )
        session.add(
            BrtaFareSegment(
                route_id="R1",
                from_place_id="P1",
                from_name_en="Mirpur 10",
                to_place_id="P2",
                to_name_en="Motijheel",
                distance_km=8,
                fare_tk=25,
                source_id="BRTA",
            )
        )
        session.add(
            BusServiceStop(
                service_id="SVC1",
                stop_sequence=1,
                canonical_place_id="P1",
                canonical_name_en="Mirpur 10",
            )
        )
        session.commit()
    return Session


class _FakeRouting:
    async def search(self, query: str, limit: int = 8):
        return [{"displayName": query, "lat": 23.8, "lon": 90.4, "provider": "fake"}]

    async def route(self, origin, destination):
        return {
            "distanceKm": 8.0,
            "durationMinutes": 20,
            "polyline": [
                {"lat": origin.lat, "lon": origin.lon},
                {"lat": destination.lat, "lon": destination.lon},
            ],
            "provider": "fake",
        }


def test_data_status_counts_all_tables():
    _seed_tables()
    repo = CommutePostgresRepository()
    status = repo.data_status()
    assert status["ok"] is True
    expected = {"places", "brta_routes", "metro_stations", "metro_fares", "stop_aliases"}
    assert expected.issubset(set(status["tables"].keys()))
    assert status["tables"]["places"] == 2
    assert status["source"] == "postgres"


def test_place_search_uses_alias_and_deduplicates():
    _seed_tables()
    repo = CommutePostgresRepository()
    rows = repo.search_places("Mirpur Ten")
    assert len(rows) == 1
    assert rows[0]["placeId"] == "P1"
    assert rows[0]["alias"] == "Mirpur Ten"


def test_bangla_place_search():
    _seed_tables()
    repo = CommutePostgresRepository()
    rows = repo.search_places("\u09ae\u09bf\u09b0\u09aa\u09c1\u09b0")
    assert rows and rows[0]["placeId"] == "P1"


def test_metro_fare_is_deterministic():
    _seed_tables()
    repo = CommutePostgresRepository()
    fare = repo.metro_fare("M1", "M2")
    assert fare is not None
    assert fare["fare"] == 40
    assert fare["fareType"] == "official"
    assert fare["confidence"] == "Authoritative"


def test_official_bus_segment_lookup():
    _seed_tables()
    repo = CommutePostgresRepository()
    fares = repo.official_bus_fares("P1", "P2")
    assert fares and fares[0]["fare"] == 25
    assert fares[0]["fareType"] == "official"


def test_nearby_stops_orders_by_distance():
    _seed_tables()
    repo = CommutePostgresRepository()
    rows = repo.nearby_stops(23.8067, 90.3687, 2000)
    assert rows
    assert rows[0]["distanceM"] <= rows[-1]["distanceM"]


def test_routes_uses_postgres_repo_and_ranking():
    _seed_tables()
    repo = CommutePostgresRepository()
    service = CommuteService(repo=repo, routing_provider=_FakeRouting())
    result = asyncio.run(
        service.routes(
            CommuteRoutesRequest(
                origin=CommutePlaceInput(place_id="P1"),
                destination=CommutePlaceInput(place_id="P2"),
            )
        )
    )
    assert result["dataSource"] == "postgres"
    assert result["distanceKm"] == 8.0
    assert any(o["mode"] == "bus" for o in result["recommendations"])
    assert any(
        "Recommended" in (o.get("badges") or []) for o in result["recommendations"]
    )


def test_new_places_endpoint_requires_auth(client):
    response = client.get("/api/commute/places/search?q=Mirpur")
    assert response.status_code == 401
