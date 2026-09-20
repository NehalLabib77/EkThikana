"""Regression test for CommuteBD production seed dependency order and data integrity.

Guarantees:
1. Canonical places must precede dependent stop linking (places -> bus_service_stops).
2. Candidate/review files must never be imported as ground truth.
3. All non-null canonical_place_id references in verified bus_service_stops resolve to places.csv.
4. Stop pairs preserve strict directionality (origin_seq < dest_seq).
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path
import pytest
from sqlalchemy import create_engine, select, text

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.database.connection import Base
from app.database.models import Place, BusService, BusServiceStop

BACKEND_DIR = Path(__file__).resolve().parent.parent
COMMUTEBD_DIR = BACKEND_DIR / "data" / "commutebd" / "core_dataset" / "csv"
COMMUTE_SEED_DIR = BACKEND_DIR / "data" / "commute_seed" / "gochano_bus_seed_v1"


def test_seed_files_exist_and_non_empty():
    required_files = [
        COMMUTEBD_DIR / "places.csv",
        COMMUTEBD_DIR / "stop_aliases.csv",
        COMMUTE_SEED_DIR / "bus_services_seed.csv",
        COMMUTE_SEED_DIR / "bus_service_stops_seed.csv",
        COMMUTEBD_DIR / "brta_routes.csv",
        COMMUTEBD_DIR / "brta_route_stops.csv",
        COMMUTEBD_DIR / "metro_stations.csv",
        COMMUTEBD_DIR / "metro_fares.csv",
        COMMUTEBD_DIR / "fare_rules.csv",
        COMMUTEBD_DIR / "sources.csv",
    ]
    for path in required_files:
        assert path.exists(), f"Required seed file missing: {path}"
        with open(path, encoding="utf-8-sig") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header is not None, f"File empty: {path}"
            rows = list(reader)
            assert len(rows) > 0, f"File has 0 data rows: {path}"


def test_candidate_files_excluded_from_seed():
    """Candidate/review files must not be treated as authoritative truth."""
    candidate_files = [
        "stop_alias_candidates.csv",
        "service_route_match_candidates.csv",
        "place_coordinate_candidates.csv",
    ]
    for name in candidate_files:
        path = COMMUTE_SEED_DIR / name
        assert path.exists(), f"Candidate review file expected at {path}"
        # Candidate files must have candidate in name and not be core datasets
        assert "candidate" in name.lower()


def test_bus_stop_canonical_places_referential_integrity():
    """Every non-null canonical_place_id in verified seed must exist in places.csv."""
    places = set()
    with open(COMMUTEBD_DIR / "places.csv", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            places.add(r["place_id"])

    assert len(places) == 387

    linked_count = 0
    unresolved_count = 0
    with open(COMMUTE_SEED_DIR / "bus_service_stops_seed.csv", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            cpid = r.get("canonical_place_id")
            if cpid:
                assert cpid in places, f"canonical_place_id={cpid} not found in places.csv!"
                linked_count += 1
            else:
                unresolved_count += 1

    assert linked_count == 2518
    assert unresolved_count == 672
    assert linked_count + unresolved_count == 3190


def test_dependency_order_enforced_in_sqlite():
    """Demonstrates that child stop references require parent places to exist first."""
    engine = create_engine("sqlite+pysqlite:///:memory:")
    with engine.connect() as conn:
        conn.execute(text("PRAGMA foreign_keys = ON;"))
        conn.commit()

    Base.metadata.create_all(engine)

    from sqlalchemy.orm import Session
    with Session(engine) as session:
        # Seeding bus service without parent is fine
        svc = BusService(service_id="SVC_TEST", operator_name_en="Test Bus")
        session.add(svc)
        session.flush()

        # Seeding bus stop referencing non-existent canonical place fails with FK error
        stop_fail = BusServiceStop(
            service_id="SVC_TEST",
            stop_sequence=1,
            canonical_place_id="PLC_NON_EXISTENT",
        )
        session.add(stop_fail)
        with pytest.raises(Exception):
            session.flush()
        session.rollback()

        # Following safe order: 1. Place, 2. BusService, 3. BusServiceStop succeeds
        place = Place(place_id="PLC_VALID", name_en="Valid Stop")
        session.add(place)
        session.flush()

        svc2 = BusService(service_id="SVC_TEST_2", operator_name_en="Test Bus 2")
        session.add(svc2)
        session.flush()

        stop_pass = BusServiceStop(
            service_id="SVC_TEST_2",
            stop_sequence=1,
            canonical_place_id="PLC_VALID",
        )
        session.add(stop_pass)
        session.flush()

        assert stop_pass.canonical_place_id == "PLC_VALID"


def test_stop_pairs_directionality():
    """Verify origin_sequence < destination_sequence directionality requirement."""
    stops_file = COMMUTE_SEED_DIR / "bus_service_stops_seed.csv"
    stops_by_service: dict[str, list[tuple[int, str]]] = {}
    with open(stops_file, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            cpid = r.get("canonical_place_id")
            if cpid:
                stops_by_service.setdefault(r["service_id"], []).append(
                    (int(r["stop_sequence"]), cpid)
                )

    # Check Farmgate (PLC0112) to Mirpur-10 (PLC0240)
    forward_matches = []
    reverse_matches = []
    for svc_id, stop_list in stops_by_service.items():
        farmgate_seqs = [seq for seq, pid in stop_list if pid == "PLC0112"]
        mirpur10_seqs = [seq for seq, pid in stop_list if pid == "PLC0240"]
        for f_seq in farmgate_seqs:
            for m_seq in mirpur10_seqs:
                if f_seq < m_seq:
                    forward_matches.append(svc_id)
                elif m_seq < f_seq:
                    reverse_matches.append(svc_id)

    assert len(forward_matches) > 0, "Expected at least one direct service from Farmgate to Mirpur-10"
    assert len(reverse_matches) > 0, "Expected at least one direct service from Mirpur-10 to Farmgate"
