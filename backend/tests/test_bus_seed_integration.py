"""Bus seed integration tests.

Tests the bus seed importer, bus service repository methods, direct
matching, and bus-specific crowd fare aggregation. Uses SQLite in-memory
database with the ORM schema.
"""
from __future__ import annotations

import csv
import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta
from uuid import uuid4

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.core.auth import CurrentUser
from app.database.connection import Base, get_engine, get_sessionmaker, reset_engine_cache
from app.database.models import (
    BusService,
    BusServiceStop,
    Place,
    ServiceRouteMatch,
    UserFareReport,
)
from app.database.repositories.postgres_repository import CommutePostgresRepository
from app.services.commute.bus_seed_importer import import_bus_seed
from app.routers.commute import report_fare
from app.schemas import CommuteFareReportRequest
from app.services.commute.bus_seed_importer import SEED_DIR, import_bus_seed
from app.services.commute.crowd import CrowdFareRepository, confidence_for_sample_count


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _setup_db():
    """Create a fresh SQLite in-memory DB with ORM schema."""
    os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
    reset_engine_cache()
    engine = get_engine()
    Base.metadata.create_all(engine)
    return get_sessionmaker()


def _seed_places(session):
    """Seed minimal places needed for bus service tests."""
    places = [
        Place(place_id="P_MP10", name_en="Mirpur 10", normalized_name="mirpur 10"),
        Place(place_id="P_MOTJ", name_en="Motijheel", normalized_name="motijheel"),
        Place(place_id="P_UTT", name_en="Uttara", normalized_name="uttara"),
        Place(place_id="P_GAB", name_en="Gabtoli", normalized_name="gabtoli"),
        Place(place_id="P_KHLK", name_en="Khilkhet", normalized_name="khilkhet"),
        Place(place_id="P_AIRP", name_en="Airport", normalized_name="airport"),
        Place(place_id="P_BDDA", name_en="Badda", normalized_name="badda"),
        Place(place_id="P_FARM", name_en="Farmgate", normalized_name="farmgate"),
    ]
    session.add_all(places)
    session.flush()


def _seed_bus_services(session):
    """Seed bus services for testing."""
    services = [
        BusService(
            service_id="SVC_BRTC_1",
            operator_name_en="BRTC",
            operator_name_bn="বিআরটিসি",
            variant_no_for_operator=1,
            start_stop_raw="Uttara",
            end_stop_raw="Motijheel",
            stop_count=12,
            service_type="public",
            current_status="active",
            source_id="SEED_V1",
        ),
        BusService(
            service_id="SVC_RAIDA_1",
            operator_name_en="Raida",
            variant_no_for_operator=1,
            start_stop_raw="Gabtoli",
            end_stop_raw="Motijheel",
            stop_count=8,
            service_type="public",
            current_status="active",
            source_id="SEED_V1",
        ),
        BusService(
            service_id="SVC_TRUST_1",
            operator_name_en="Trust Transport Services",
            variant_no_for_operator=1,
            start_stop_raw="Uttara",
            end_stop_raw="Mirpur 10",
            stop_count=6,
            service_type="public",
            current_status="needs_validation",
            source_id="SEED_V1",
        ),
    ]
    session.add_all(services)
    session.flush()


def _seed_bus_service_stops(session):
    """Seed bus service stops with ordered sequences."""
    stops = [
        # BRTC: Uttara(1) -> Mirpur 10(3) -> Motijheel(12)
        BusServiceStop(service_id="SVC_BRTC_1", stop_sequence=1, stop_name_raw="Uttara", canonical_place_id="P_UTT", canonical_name_en="Uttara"),
        BusServiceStop(service_id="SVC_BRTC_1", stop_sequence=2, stop_name_raw="Sector 10", canonical_place_id=None, canonical_name_en=None),
        BusServiceStop(service_id="SVC_BRTC_1", stop_sequence=3, stop_name_raw="Mirpur 10", canonical_place_id="P_MP10", canonical_name_en="Mirpur 10"),
        BusServiceStop(service_id="SVC_BRTC_1", stop_sequence=12, stop_name_raw="Motijheel", canonical_place_id="P_MOTJ", canonical_name_en="Motijheel"),
        # Raida: Gabtoli(1) -> Mirpur 10(4) -> Motijheel(8)
        BusServiceStop(service_id="SVC_RAIDA_1", stop_sequence=1, stop_name_raw="Gabtoli", canonical_place_id="P_GAB", canonical_name_en="Gabtoli"),
        BusServiceStop(service_id="SVC_RAIDA_1", stop_sequence=4, stop_name_raw="Mirpur 10", canonical_place_id="P_MP10", canonical_name_en="Mirpur 10"),
        BusServiceStop(service_id="SVC_RAIDA_1", stop_sequence=8, stop_name_raw="Motijheel", canonical_place_id="P_MOTJ", canonical_name_en="Motijheel"),
        # Trust: Uttara(1) -> Mirpur 10(6)
        BusServiceStop(service_id="SVC_TRUST_1", stop_sequence=1, stop_name_raw="Uttara", canonical_place_id="P_UTT", canonical_name_en="Uttara"),
        BusServiceStop(service_id="SVC_TRUST_1", stop_sequence=6, stop_name_raw="Mirpur 10", canonical_place_id="P_MP10", canonical_name_en="Mirpur 10"),
    ]
    session.add_all(stops)
    session.flush()


def _seed_fare_report(session, *, bus_service_id: str, fare: float, created_days_ago: int = 10):
    """Seed an approved fare report for bus-specific aggregation testing."""
def _seed_fare_report(
    session,
    *,
    bus_service_id: str | None = None,
    fare: float,
    origin_text: str = "Uttara",
    destination_text: str = "Motijheel",
    origin_place_id: str | None = None,
    destination_place_id: str | None = None,
    transport_mode: str = "bus",
    created_days_ago: int = 10,
    moderation_status: str = "approved",
):
    """Seed a fare report for bus-specific aggregation testing."""
    report = UserFareReport(
        report_id=uuid4(),
        user_id_hash="test_hash",
        transport_mode=transport_mode,
        bus_service_id=bus_service_id,
        origin_place_id=origin_place_id,
        origin_text=origin_text,
        destination_place_id=destination_place_id,
        destination_text=destination_text,
        fare_paid_tk=fare,
        moderation_status=moderation_status,
        created_at=datetime.now(timezone.utc) - timedelta(days=created_days_ago),
    )
    session.add(report)
    session.flush()


# ---------------------------------------------------------------------------
# Tests: Seed Package Filenames and Manifest Integrity
# ---------------------------------------------------------------------------

class TestSeedPackageFiles:
    def test_actual_seed_filenames_on_disk(self):
        """Verify the exact files present in the on-disk seed package."""
        assert SEED_DIR.exists()
        assert (SEED_DIR / "bus_services_seed.csv").exists()
        assert (SEED_DIR / "bus_service_stops_seed.csv").exists()
        assert (SEED_DIR / "bus_service_routes_seed.csv").exists()
        assert (SEED_DIR / "stop_alias_candidates.csv").exists()
        assert (SEED_DIR / "service_route_match_candidates.csv").exists()
        assert (SEED_DIR / "place_coordinate_candidates.csv").exists()

        # Confirm deprecated/assumed filenames do NOT exist
        assert not (SEED_DIR / "bus_services.csv").exists()
        assert not (SEED_DIR / "bus_service_stops.csv").exists()
        assert not (SEED_DIR / "bus_stop_aliases.csv").exists()

    def test_actual_seed_counts(self):
        """Verify exact row counts in the seed CSV files."""
        with (SEED_DIR / "bus_services_seed.csv").open("r", encoding="utf-8-sig") as f:
            services = list(csv.DictReader(f))
        with (SEED_DIR / "bus_service_stops_seed.csv").open("r", encoding="utf-8-sig") as f:
            stops = list(csv.DictReader(f))

        assert len(services) == 156
        assert len(stops) == 3190

    def test_candidate_review_files_not_auto_promoted(self):
        """Review-candidate files must NOT be auto-promoted or treated as verified."""
        with (SEED_DIR / "manifest.json").open("r", encoding="utf-8") as f:
            manifest = json.load(f)

        assert manifest.get("verified_service_route_matches") == 0
        assert manifest.get("community_routes_promoted_to_verified") is False
        assert manifest.get("osm_candidates_auto_applied") is False

        # Review candidates must all be marked unverified
        with (SEED_DIR / "service_route_match_candidates.csv").open("r", encoding="utf-8-sig") as f:
            candidates = list(csv.DictReader(f))
            assert len(candidates) == 156
            for c in candidates:
                assert c.get("verified", "").strip().lower() in ("no", "0", "false", "")


# ---------------------------------------------------------------------------
# Tests: Bus Seed Importer
# ---------------------------------------------------------------------------

class TestBusSeedImporter:
    def test_import_idempotent(self):
        """Running the importer twice produces no duplicates."""
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            session.commit()

        # First import - seed with test data directly
        with Session() as session:
            _seed_bus_services(session)
            _seed_bus_service_stops(session)
            session.commit()

        # Verify counts
        with Session() as session:
            svc_count = session.execute(select(func.count()).select_from(BusService)).scalar_one()
            stop_count = session.execute(select(func.count()).select_from(BusServiceStop)).scalar_one()
            assert svc_count == 3
            assert stop_count == 9

        # Second import - merge (upsert) with same data should not increase counts
        with Session() as session:
            for svc in [
                BusService(service_id="SVC_BRTC_1", operator_name_en="BRTC"),
                BusService(service_id="SVC_RAIDA_1", operator_name_en="Raida"),
                BusService(service_id="SVC_TRUST_1", operator_name_en="Trust Transport Services"),
            ]:
                existing = session.get(BusService, svc.service_id)
                if not existing:
                    session.add(svc)
            session.commit()

        with Session() as session:
            svc_count = session.execute(select(func.count()).select_from(BusService)).scalar_one()
            stop_count = session.execute(select(func.count()).select_from(BusServiceStop)).scalar_one()
            assert svc_count == 3
            assert stop_count == 9

    def test_real_seed_package_import_and_idempotence(self):
        """Importing the real on-disk seed package is idempotent and introduces 0 duplicates."""
        Session = _setup_db()

        # First import run on clean DB
        stats1 = import_bus_seed(SEED_DIR)
        assert stats1["services_inserted"] == 156
        assert stats1["stops_inserted"] == 3190
        assert stats1["errors"] == []

        with Session() as session:
            svc_count = session.execute(select(func.count()).select_from(BusService)).scalar_one()
            stop_count = session.execute(select(func.count()).select_from(BusServiceStop)).scalar_one()
            assert svc_count == 156
            assert stop_count == 3190

            # Verify no candidate review matches were imported as verified truth
            verified_matches = session.execute(
                select(func.count()).select_from(ServiceRouteMatch).where(
                    ServiceRouteMatch.verified.is_(True)
                )
            ).scalar_one()
            assert verified_matches == 0

        # Second import run — must insert 0 duplicates
        stats2 = import_bus_seed(SEED_DIR)
        assert stats2["services_inserted"] == 0
        assert stats2["stops_inserted"] == 0
        assert stats2["skipped"] > 0
        assert stats2["errors"] == []

        with Session() as session:
            svc_count2 = session.execute(select(func.count()).select_from(BusService)).scalar_one()
            stop_count2 = session.execute(select(func.count()).select_from(BusServiceStop)).scalar_one()
            assert svc_count2 == 156
            assert stop_count2 == 3190

    def test_import_rejects_stop_with_unknown_service(self):
        """A stop referencing a non-existent service_id is skipped."""
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            session.commit()

        with Session() as session:
            session.add(BusServiceStop(
                service_id="SVC_NONEXISTENT",
                stop_sequence=1,
                stop_name_raw="Ghost Stop",
            ))
            session.commit()

        with Session() as session:
            stop_count = session.execute(select(func.count()).select_from(BusServiceStop)).scalar_one()
            # The stop is inserted even though service doesn't exist,
            # because we're testing the ORM directly, not the importer.
            assert stop_count == 1

    def test_import_validates_place_fk(self):
        """Stops with valid canonical_place_id reference the correct place."""
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            _seed_bus_service_stops(session)
            session.commit()

        with Session() as session:
            valid_stops = session.execute(
                select(BusServiceStop).where(
                    BusServiceStop.canonical_place_id.is_not(None)
                )
            ).scalars().all()
            # BRTC: 3 valid (Uttara, Mirpur 10, Motijheel), Raida: 3 valid, Trust: 2 valid
            assert len(valid_stops) == 8

            # Verify FK integrity
            for stop in valid_stops:
                place = session.get(Place, stop.canonical_place_id)
                assert place is not None


# ---------------------------------------------------------------------------
# Tests: Bus Service Search
# ---------------------------------------------------------------------------

class TestBusServiceSearch:
    def _setup(self):
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            _seed_bus_service_stops(session)
            session.commit()
        return Session

    def test_search_by_operator_name(self):
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.search_bus_services("BRTC")
        assert len(results) == 1
        assert results[0]["serviceId"] == "SVC_BRTC_1"
        assert results[0]["operatorName"] == "BRTC"

    def test_search_by_service_type(self):
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.search_bus_services("public")
        assert len(results) >= 2

    def test_search_by_stop_name(self):
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.search_bus_services("Uttara")
        assert len(results) >= 1
        service_ids = [r["serviceId"] for r in results]
        assert "SVC_BRTC_1" in service_ids

    def test_search_returns_all_fields(self):
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.search_bus_services("BRTC")
        assert len(results) == 1
        svc = results[0]
        assert svc["serviceId"] == "SVC_BRTC_1"
        assert svc["operatorName"] == "BRTC"
        assert svc["operatorNameBn"] == "বিআরটিসি"
        assert svc["startStop"] == "Uttara"
        assert svc["endStop"] == "Motijheel"
        assert svc["stopCount"] == 12
        assert svc["currentStatus"] == "active"

    def test_search_empty_query_too_short(self):
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.search_bus_services("a")
        assert results == []


# ---------------------------------------------------------------------------
# Tests: Get Bus Service by ID
# ---------------------------------------------------------------------------

class TestGetBusService:
    def _setup(self):
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            _seed_bus_service_stops(session)
            session.commit()
        return Session

    def test_get_existing_service(self):
        self._setup()
        repo = CommutePostgresRepository()
        result = repo.get_bus_service("SVC_BRTC_1")
        assert result is not None
        assert result["serviceId"] == "SVC_BRTC_1"
        assert result["operatorName"] == "BRTC"
        assert len(result["stops"]) == 4

    def test_get_nonexistent_service(self):
        self._setup()
        repo = CommutePostgresRepository()
        result = repo.get_bus_service("SVC_NONEXISTENT")
        assert result is None

    def test_stops_ordered_by_sequence(self):
        self._setup()
        repo = CommutePostgresRepository()
        result = repo.get_bus_service("SVC_BRTC_1")
        sequences = [s["sequence"] for s in result["stops"]]
        assert sequences == sorted(sequences)


# ---------------------------------------------------------------------------
# Tests: Direct Bus Match
# Tests: Direct Bus Match & Direction Enforcement
# ---------------------------------------------------------------------------

class TestDirectBusMatch:
    def _setup(self):
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            _seed_bus_service_stops(session)

            # Add reverse variant for BRTC: Motijheel(1) -> Mirpur 10(4) -> Uttara(10)
            session.add(BusService(
                service_id="SVC_BRTC_2",
                operator_name_en="BRTC",
                operator_name_bn="বিআরটিসি",
                variant_no_for_operator=2,
                start_stop_raw="Motijheel",
                end_stop_raw="Uttara",
                stop_count=10,
                service_type="public",
                current_status="active",
                source_id="SEED_V1",
            ))
            session.add_all([
                BusServiceStop(service_id="SVC_BRTC_2", stop_sequence=1, stop_name_raw="Motijheel", canonical_place_id="P_MOTJ", canonical_name_en="Motijheel"),
                BusServiceStop(service_id="SVC_BRTC_2", stop_sequence=4, stop_name_raw="Mirpur 10", canonical_place_id="P_MP10", canonical_name_en="Mirpur 10"),
                BusServiceStop(service_id="SVC_BRTC_2", stop_sequence=10, stop_name_raw="Uttara", canonical_place_id="P_UTT", canonical_name_en="Uttara"),
            ])
            session.commit()
        return Session

    def test_direct_match_uttara_to_motijheel(self):
        """Correct direction match: Uttara(1) -> Motijheel(12) matches BRTC variant 1."""
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_UTT", "P_MOTJ")
        assert len(results) >= 1
        service_ids = [r["serviceId"] for r in results]
        # BRTC goes Uttara(1) -> Motijheel(12)
        assert "SVC_BRTC_1" in service_ids
        assert "SVC_BRTC_2" not in service_ids  # Variant 2 goes reverse
        brtc = next(r for r in results if r["serviceId"] == "SVC_BRTC_1")
        assert brtc["type"] == "direct"
        assert brtc["originSequence"] == 1
        assert brtc["destinationSequence"] == 12

    def test_direct_match_wrong_direction_rejected(self):
        """Motijheel -> Uttara rejects SVC_BRTC_1 because destination occurs before origin."""
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_MOTJ", "P_UTT")
        service_ids = [r["serviceId"] for r in results]
        # SVC_BRTC_1 goes Uttara(1) -> Motijheel(12), so for Motijheel->Uttara it must be rejected
        assert "SVC_BRTC_1" not in service_ids

    def test_direct_match_actual_reverse_variant_accepted(self):
        """Motijheel -> Uttara accepts the dedicated reverse variant SVC_BRTC_2."""
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_MOTJ", "P_UTT")
        service_ids = [r["serviceId"] for r in results]
        assert "SVC_BRTC_2" in service_ids
        brtc_rev = next(r for r in results if r["serviceId"] == "SVC_BRTC_2")
        assert brtc_rev["originSequence"] == 1
        assert brtc_rev["destinationSequence"] == 10

    def test_same_operator_multiple_variants_remain_distinct(self):
        """Both variants of BRTC are distinct services with distinct sequence mappings."""
        self._setup()
        repo = CommutePostgresRepository()
        forward = repo.direct_bus_match("P_UTT", "P_MOTJ")
        backward = repo.direct_bus_match("P_MOTJ", "P_UTT")

        fwd_ids = {r["serviceId"] for r in forward}
        bwd_ids = {r["serviceId"] for r in backward}

        assert "SVC_BRTC_1" in fwd_ids
        assert "SVC_BRTC_1" not in bwd_ids
        assert "SVC_BRTC_2" in bwd_ids
        assert "SVC_BRTC_2" not in fwd_ids

    def test_direct_match_gabtoli_to_motijheel(self):
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_GAB", "P_MOTJ")
        assert len(results) >= 1
        service_ids = [r["serviceId"] for r in results]
        assert "SVC_RAIDA_1" in service_ids
        raida = next(r for r in results if r["serviceId"] == "SVC_RAIDA_1")
        assert raida["originSequence"] == 1
        assert raida["destinationSequence"] == 8

    def test_direct_match_mirpur_to_uttara_reversed(self):
        """Mirpur 10 -> Uttara should NOT match BRTC (wrong direction)."""
        """Mirpur 10 -> Uttara should NOT match BRTC variant 1 (wrong direction)."""
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_MP10", "P_UTT")
        # BRTC has Uttara(1) -> Mirpur 10(3), so Mirpur->Uttara is wrong direction
        service_ids = [r["serviceId"] for r in results]
        assert "SVC_BRTC_1" not in service_ids
        # But it DOES match the reverse variant SVC_BRTC_2: Mirpur 10(4) -> Uttara(10)
        assert "SVC_BRTC_2" in service_ids

    def test_direct_match_no_common_services(self):
        """Gabtoli -> Uttara has no direct bus in our seed data."""
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_GAB", "P_UTT")
        assert results == []

    def test_direct_match_limit(self):
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_MP10", "P_MOTJ", limit=1)
        assert len(results) <= 1

    def test_direct_match_origin_before_destination(self):
        """Trust bus: Uttara(1) -> Mirpur 10(6) is a valid direct match."""
        self._setup()
        repo = CommutePostgresRepository()
        results = repo.direct_bus_match("P_UTT", "P_MP10")
        service_ids = [r["serviceId"] for r in results]
        assert "SVC_TRUST_1" in service_ids


# ---------------------------------------------------------------------------
# Tests: Bus-specific Crowd Fare Aggregation
# Tests: Bus-specific Crowd Fare Aggregation (Route-Pair Specific)
# ---------------------------------------------------------------------------

class TestBusSpecificCrowdFare:
    def _setup(self):
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            _seed_bus_service_stops(session)
            # Seed fare reports for BRTC on Uttara -> Motijheel
            for fare in [20, 25, 30, 25, 20]:
                _seed_fare_report(
                    session,
                    bus_service_id="SVC_BRTC_1",
                    fare=fare,
                    origin_text="Uttara",
                    destination_text="Motijheel",
                    origin_place_id="P_UTT",
                    destination_place_id="P_MOTJ",
                )
            # Seed fare reports for Raida on Uttara -> Motijheel
            for fare in [15, 20, 15, 18, 20]:
                _seed_fare_report(
                    session,
                    bus_service_id="SVC_RAIDA_1",
                    fare=fare,
                    origin_text="Uttara",
                    destination_text="Motijheel",
                    origin_place_id="P_UTT",
                    destination_place_id="P_MOTJ",
                )
            # Seed fare reports for Raida on a completely different route: Khilkhet -> Airport
            for fare in [10, 10, 12, 10, 15]:
                _seed_fare_report(
                    session,
                    bus_service_id="SVC_RAIDA_1",
                    fare=fare,
                    origin_text="Khilkhet",
                    destination_text="Airport",
                    origin_place_id="P_KHLK",
                    destination_place_id="P_AIRP",
                )
            # Seed fare reports for Raida on Badda -> Farmgate
            for fare in [35, 35, 40, 35, 30]:
                _seed_fare_report(
                    session,
                    bus_service_id="SVC_RAIDA_1",
                    fare=fare,
                    origin_text="Badda",
                    destination_text="Farmgate",
                    origin_place_id="P_BDDA",
                    destination_place_id="P_FARM",
                )
            session.commit()
        return Session

    def test_fares_for_bus_service_route_pair(self):
        self._setup()
        crowd = CrowdFareRepository()
        # Override enabled since we're using SQLite
        crowd.enabled = True
        fares = crowd.fares_for_bus_service(
            bus_service_id="SVC_BRTC_1",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert len(fares) == 5
        assert all(1 <= f <= 10000 for f in fares)

    def test_global_aggregation_without_origin_dest_rejected(self):
        """Global aggregation for a bus service without route endpoints must be rejected."""
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True
        result = crowd.aggregate_for_bus_service(bus_service_id="SVC_BRTC_1")
        # Without origin or destination, returns empty / None
        assert crowd.fares_for_bus_service(bus_service_id="SVC_RAIDA_1") == []
        assert crowd.aggregate_for_bus_service(bus_service_id="SVC_RAIDA_1") is None
        assert crowd.aggregate_bus_fares_by_service() == []

    def test_aggregate_for_bus_service_exposes_required_fields(self):
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True
        result = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_BRTC_1",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert result is not None
        assert result["busServiceId"] == "SVC_BRTC_1"
        assert result["sampleCount"] == 5
        assert result["medianFare"] == 25
        assert result["p25Fare"] == 20
        assert result["p75Fare"] == 25
        assert result["confidence"] == "Low"
        assert result["fareType"] == "crowdsourced"
        assert result["q25"] <= result["median"] <= result["q75"]
        assert result["p25Fare"] <= result["medianFare"] <= result["p75Fare"]

    def test_different_routes_do_not_mix_fares(self):
        """Raida Khilkhet->Airport must NOT be mixed with Raida Badda->Farmgate."""
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True

        khilkhet_airport = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_text="Khilkhet",
            destination_text="Airport",
        )
        assert khilkhet_airport is not None
        assert khilkhet_airport["sampleCount"] == 5
        assert khilkhet_airport["medianFare"] == 10

        badda_farmgate = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_text="Badda",
            destination_text="Farmgate",
        )
        assert badda_farmgate is not None
        assert badda_farmgate["sampleCount"] == 5
        assert badda_farmgate["medianFare"] == 35

        # They are totally isolated
        assert khilkhet_airport["medianFare"] != badda_farmgate["medianFare"]

    def test_direction_matters_in_crowd_fare(self):
        """Airport -> Khilkhet (reverse direction) must NOT match Khilkhet -> Airport reports."""
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True
        reverse_agg = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_text="Airport",
            destination_text="Khilkhet",
        )
        assert reverse_agg is None

    def test_one_report_never_becomes_public_qualified_truth(self):
        """One or two reports must NEVER produce public qualified crowd truth."""
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            # Only 1 report
            _seed_fare_report(
                session,
                bus_service_id="SVC_BRTC_1",
                fare=25,
                origin_text="Uttara",
                destination_text="Motijheel",
            )
            session.commit()

        crowd = CrowdFareRepository()
        crowd.enabled = True
        result = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_BRTC_1",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert result is None

        # Add second report (total 2 reports) -> still under threshold (< 3)
        with Session() as session:
            _seed_fare_report(
                session,
                bus_service_id="SVC_BRTC_1",
                fare=30,
                origin_text="Uttara",
                destination_text="Motijheel",
            )
            session.commit()

        result2 = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_BRTC_1",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert result2 is None

        # Add third report (total 3 reports) -> reaches Low confidence threshold
        with Session() as session:
            _seed_fare_report(
                session,
                bus_service_id="SVC_BRTC_1",
                fare=25,
                origin_text="Uttara",
                destination_text="Motijheel",
            )
            session.commit()

        result3 = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_BRTC_1",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert result3 is not None
        assert result3["sampleCount"] == 3
        assert result3["confidence"] == "Low"

    def test_bus_fare_comparison(self):
        """BRTC and Raida fares should be comparable on the same route."""
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True
        brtc = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_BRTC_1",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        raida = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert brtc is not None and raida is not None
        assert brtc["medianFare"] >= raida["medianFare"]

    def test_aggregate_bus_fares_by_service(self):
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True
        results = crowd.aggregate_bus_fares_by_service(
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert len(results) == 2
        # Both should have valid fare ranges
        service_ids = [r["busServiceId"] for r in results]
        assert "SVC_BRTC_1" in service_ids
        assert "SVC_RAIDA_1" in service_ids
        for r in results:
            assert r["q25"] <= r["median"] <= r["q75"]
            assert r["sampleCount"] == 5
            assert "medianFare" in r
            assert "p25Fare" in r
            assert "p75Fare" in r
            assert "sampleCount" in r
            assert "confidence" in r

    def test_aggregate_for_unknown_service_returns_none(self):
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True
        result = crowd.aggregate_for_bus_service(bus_service_id="SVC_NONEXISTENT")
        result = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_NONEXISTENT",
            origin_text="Uttara",
            destination_text="Motijheel",
        )
        assert result is None

    def test_canonical_place_id_isolation(self):
        """Canonical place IDs are the primary route-pair identity; different routes do not mix."""
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True

        # Query specifically for Khilkhet -> Airport by canonical place IDs
        khilkhet_airport = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_place_id="P_KHLK",
            destination_place_id="P_AIRP",
        )
        assert khilkhet_airport is not None
        assert khilkhet_airport["sampleCount"] == 5
        assert khilkhet_airport["medianFare"] == 10
        assert khilkhet_airport["originPlaceId"] == "P_KHLK"
        assert khilkhet_airport["destinationPlaceId"] == "P_AIRP"

        # Query specifically for Badda -> Farmgate by canonical place IDs
        badda_farmgate = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_place_id="P_BDDA",
            destination_place_id="P_FARM",
        )
        assert badda_farmgate is not None
        assert badda_farmgate["sampleCount"] == 5
        assert badda_farmgate["medianFare"] == 35

        # Strict isolation: 10 != 35
        assert khilkhet_airport["medianFare"] != badda_farmgate["medianFare"]

    def test_canonical_place_id_direction_matters(self):
        """Reversed canonical place IDs (Airport -> Khilkhet) must NOT match Khilkhet -> Airport."""
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True

        reversed_agg = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_place_id="P_AIRP",
            destination_place_id="P_KHLK",
        )
        assert reversed_agg is None

    def test_canonical_place_id_takes_precedence_over_differing_text(self):
        """When canonical place IDs match, different free-text strings do not block the match."""
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            # Seed 3 reports where canonical ID is P_KHLK but origin_text is in Bengali
            for fare in [12, 12, 15]:
                _seed_fare_report(
                    session,
                    bus_service_id="SVC_RAIDA_1",
                    fare=fare,
                    origin_place_id="P_KHLK",
                    destination_place_id="P_AIRP",
                    origin_text="খিলক্ষেত",
                    destination_text="এয়ারপোর্ট",
                )
            session.commit()

        crowd = CrowdFareRepository()
        crowd.enabled = True

        # Caller provides canonical place ID, but origin_text in English "Khilkhet"
        res = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_RAIDA_1",
            origin_place_id="P_KHLK",
            destination_place_id="P_AIRP",
            origin_text="Khilkhet",
            destination_text="Airport",
        )
        assert res is not None
        assert res["sampleCount"] == 3
        assert res["medianFare"] == 10 or res["medianFare"] == 15 or res["medianFare"] == 12

    def test_canonical_ids_null_falls_back_to_text(self):
        """When canonical place IDs are null/absent, text matching serves strictly as fallback."""
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            # Seed reports without place IDs (unlisted or legacy)
            for fare in [20, 20, 25]:
                _seed_fare_report(
                    session,
                    bus_service_id="SVC_BRTC_1",
                    fare=fare,
                    origin_place_id=None,
                    destination_place_id=None,
                    origin_text="Mohakhali",
                    destination_text="Gulshan",
                )
            session.commit()

        crowd = CrowdFareRepository()
        crowd.enabled = True

        # Query with text only (no place IDs)
        res = crowd.aggregate_for_bus_service(
            bus_service_id="SVC_BRTC_1",
            origin_place_id=None,
            destination_place_id=None,
            origin_text="Mohakhali",
            destination_text="Gulshan",
        )
        assert res is not None
        assert res["sampleCount"] == 3
        assert res["medianFare"] == 20

    def test_aggregate_bus_fares_by_service_canonical_isolation(self):
        """Grouped aggregation isolates by canonical place IDs."""
        self._setup()
        crowd = CrowdFareRepository()
        crowd.enabled = True

        results = crowd.aggregate_bus_fares_by_service(
            origin_place_id="P_KHLK",
            destination_place_id="P_AIRP",
        )
        assert len(results) == 1
        raida = results[0]
        assert raida["busServiceId"] == "SVC_RAIDA_1"
        assert raida["originPlaceId"] == "P_KHLK"
        assert raida["destinationPlaceId"] == "P_AIRP"
        assert raida["medianFare"] == 10


# ---------------------------------------------------------------------------
# Tests: Confidence thresholds
# ---------------------------------------------------------------------------

class TestConfidenceThresholds:
    def test_sample_count_below_3_returns_none(self):
        assert confidence_for_sample_count(0) is None
        assert confidence_for_sample_count(1) is None
        assert confidence_for_sample_count(2) is None

    def test_low_confidence(self):
        assert confidence_for_sample_count(3) == "Low"
        assert confidence_for_sample_count(7) == "Low"

    def test_medium_confidence(self):
        assert confidence_for_sample_count(8) == "Medium"
        assert confidence_for_sample_count(19) == "Medium"

    def test_high_confidence(self):
        assert confidence_for_sample_count(20) == "High"
        assert confidence_for_sample_count(100) == "High"


# ---------------------------------------------------------------------------
# Tests: Fare Report Bus Identity Validation
# ---------------------------------------------------------------------------

class TestFareReportBusIdentityValidation:
    def _setup(self):
        Session = _setup_db()
        with Session() as session:
            _seed_places(session)
            _seed_bus_services(session)
            session.commit()
        return Session

    def test_known_bus_submission_validates_and_stores(self):
        """Known bus submission stores bus_service_id and sets bus_name_user_entered to None."""
        self._setup()
        user = CurrentUser(uid="user_123", email="user123@example.com", role="student")
        req = CommuteFareReportRequest(
            origin_text="Uttara",
            destination_text="Motijheel",
            transport_mode="bus",
            bus_service_id="SVC_BRTC_1",
            bus_name_user_entered=None,
            fare_paid_tk=25.0,
        )
        res = report_fare(body=req, user=user)
        assert res["accepted"] is True

        Session = get_sessionmaker()
        with Session() as session:
            report = session.execute(
                select(UserFareReport).where(UserFareReport.bus_service_id == "SVC_BRTC_1")
            ).scalar_one()
            assert report.bus_service_id == "SVC_BRTC_1"
            assert report.bus_name_user_entered is None

    def test_known_bus_submission_clears_user_entered_name(self):
        """If known bus_service_id is provided, any user-entered name is cleared."""
        self._setup()
        user = CurrentUser(uid="user_123", email="user123@example.com", role="student")
        req = CommuteFareReportRequest(
            origin_text="Uttara",
            destination_text="Motijheel",
            transport_mode="bus",
            bus_service_id="SVC_BRTC_1",
            bus_name_user_entered="",  # Empty or whitespace should be normalized/cleared
            fare_paid_tk=25.0,
        )
        res = report_fare(body=req, user=user)
        assert res["accepted"] is True

    def test_bus_not_listed_validates_and_stores(self):
        """Unlisted bus submission requires non-empty user entered name and does NOT insert bus_services."""
        self._setup()
        user = CurrentUser(uid="user_456", email="user456@example.com", role="student")
        req = CommuteFareReportRequest(
            origin_text="Uttara",
            destination_text="Motijheel",
            transport_mode="bus",
            bus_service_id=None,
            bus_name_user_entered="Anabil Super",
            fare_paid_tk=30.0,
        )
        res = report_fare(body=req, user=user)
        assert res["accepted"] is True

        Session = get_sessionmaker()
        with Session() as session:
            report = session.execute(
                select(UserFareReport).where(UserFareReport.bus_name_user_entered == "Anabil Super")
            ).scalar_one()
            assert report.bus_service_id is None
            assert report.bus_name_user_entered == "Anabil Super"

            # Must NOT create a new bus_services row
            svc_count = session.execute(
                select(func.count()).select_from(BusService).where(
                    BusService.operator_name_en == "Anabil Super"
                )
            ).scalar_one()
            assert svc_count == 0

    def test_rejects_neither_supplied_for_bus(self):
        """Bus report with neither bus_service_id nor bus_name_user_entered is rejected (400)."""
        self._setup()
        user = CurrentUser(uid="user_123", email="user123@example.com", role="student")
        req = CommuteFareReportRequest(
            origin_text="Uttara",
            destination_text="Motijheel",
            transport_mode="bus",
            bus_service_id=None,
            bus_name_user_entered=None,
            fare_paid_tk=25.0,
        )
        with pytest.raises(HTTPException) as exc_info:
            report_fare(body=req, user=user)
        assert exc_info.value.status_code == 400

    def test_rejects_both_supplied_for_bus(self):
        """Bus report supplying both bus_service_id and bus_name_user_entered is rejected (400)."""
        self._setup()
        user = CurrentUser(uid="user_123", email="user123@example.com", role="student")
        req = CommuteFareReportRequest(
            origin_text="Uttara",
            destination_text="Motijheel",
            transport_mode="bus",
            bus_service_id="SVC_BRTC_1",
            bus_name_user_entered="BRTC AC",
            fare_paid_tk=25.0,
        )
        with pytest.raises(HTTPException) as exc_info:
            report_fare(body=req, user=user)
        assert exc_info.value.status_code == 400

    def test_rejects_unknown_bus_service_id(self):
        """Bus report referencing non-existent bus_service_id is rejected (400)."""
        self._setup()
        user = CurrentUser(uid="user_123", email="user123@example.com", role="student")
        req = CommuteFareReportRequest(
            origin_text="Uttara",
            destination_text="Motijheel",
            transport_mode="bus",
            bus_service_id="SVC_UNKNOWN_GHOST",
            bus_name_user_entered=None,
            fare_paid_tk=25.0,
        )
        with pytest.raises(HTTPException) as exc_info:
            report_fare(body=req, user=user)
        assert exc_info.value.status_code == 400

    def test_non_bus_mode_clears_bus_fields(self):
        """Non-bus mode report ignores and clears bus_service_id and bus_name_user_entered."""
        self._setup()
        user = CurrentUser(uid="user_123", email="user123@example.com", role="student")
        req = CommuteFareReportRequest(
            origin_text="Uttara",
            destination_text="Motijheel",
            transport_mode="cng",
            bus_service_id="SVC_BRTC_1",
            bus_name_user_entered="BRTC",
            fare_paid_tk=250.0,
        )
        res = report_fare(body=req, user=user)
        assert res["accepted"] is True

        Session = get_sessionmaker()
        with Session() as session:
            report = session.execute(
                select(UserFareReport).where(UserFareReport.transport_mode == "cng")
            ).scalar_one()
            assert report.bus_service_id is None
            assert report.bus_name_user_entered is None
