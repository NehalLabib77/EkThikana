"""Idempotent Python CSV importer for the Gochano Bus Seed v1 package.

Reads ``bus_services_seed.csv`` and ``bus_service_stops_seed.csv`` from the
seed directory, validates FK references (stops with a canonical_place_id must
refer to an existing ``places`` row), and inserts only rows that don't already
exist.

The importer is deliberately idempotent: running it twice produces no errors
and no duplicate rows (``ON CONFLICT DO NOTHING`` at the ORM level).

Usage::

    from app.services.commute.bus_seed_importer import import_bus_seed
    result = import_bus_seed()
    # result = {"services_inserted": 156, "stops_inserted": 3190, "skipped": 0}
"""
from __future__ import annotations

import csv
import logging
from pathlib import Path
from typing import Any

from sqlalchemy import select

from app.database.connection import get_sessionmaker
from app.database.models import BusService, BusServiceStop, Place

logger = logging.getLogger("gochano.commute.seed")

SEED_DIR = Path(__file__).resolve().parents[3] / "data" / "commute_seed" / "gochano_bus_seed_v1"


def _clean(value: str | None) -> str:
    return (value or "").strip()


def _int(value: str | None) -> int | None:
    try:
        v = int((value or "").strip())
        return v if v > 0 else None
    except (ValueError, TypeError):
        return None


def _read_csv(directory: Path, name: str) -> list[dict[str, str]]:
    path = directory / name
    if not path.exists():
        logger.warning("Seed CSV not found: %s", path)
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def import_bus_seed(seed_dir: Path | None = None) -> dict[str, Any]:
    """Import bus_services and bus_service_stops from the verified seed CSVs.

    Only verified seed CSVs (``bus_services_seed.csv`` and ``bus_service_stops_seed.csv``)
    are imported. Review-candidate files (such as ``stop_alias_candidates.csv``,
    ``service_route_match_candidates.csv``, ``place_coordinate_candidates.csv``)
    are explicitly NOT imported or auto-promoted to verified truth.

    Returns a summary dict with counts. Safe to call multiple times (idempotent).
    """
    seed_path = seed_dir or SEED_DIR
    services_rows = _read_csv(seed_path, "bus_services_seed.csv")
    stops_rows = _read_csv(seed_path, "bus_service_stops_seed.csv")

    if not services_rows and not stops_rows:
        return {"services_inserted": 0, "stops_inserted": 0, "skipped": 0, "errors": ["No seed CSVs found"]}

    stats = {"services_inserted": 0, "stops_inserted": 0, "skipped": 0, "errors": []}

    with get_sessionmaker()() as session:
        # --- Bus services ---
        existing_service_ids: set[str] = set()
        result = session.execute(select(BusService.service_id))
        for row in result:
            existing_service_ids.add(str(row[0]))

        valid_place_ids: set[str] = set()
        for row in session.execute(select(Place.place_id)):
            valid_place_ids.add(str(row[0]))

        for svc in services_rows:
            svc_id = _clean(svc.get("service_id"))
            if not svc_id:
                stats["skipped"] += 1
                continue
            if svc_id in existing_service_ids:
                stats["skipped"] += 1
                continue

            session.add(BusService(
                service_id=svc_id,
                operator_name_en=_clean(svc.get("operator_name_en")) or None,
                operator_name_bn=_clean(svc.get("operator_name_bn")) or None,
                variant_no_for_operator=_int(svc.get("variant_no_for_operator")),
                start_stop_raw=_clean(svc.get("start_stop_raw")) or None,
                end_stop_raw=_clean(svc.get("end_stop_raw")) or None,
                stop_count=_int(svc.get("stop_count")),
                service_type=_clean(svc.get("service_type")) or None,
                time_text=_clean(svc.get("time_text")) or None,
                image_url=_clean(svc.get("image_url")) or None,
                current_status=_clean(svc.get("current_status")) or "needs_validation",
                source_id=_clean(svc.get("source_id")) or None,
            ))
            existing_service_ids.add(svc_id)
            stats["services_inserted"] += 1

        session.flush()

        # --- Bus service stops ---
        existing_stop_keys: set[tuple[str, int]] = set()
        result = session.execute(
            select(BusServiceStop.service_id, BusServiceStop.stop_sequence)
        )
        for row in result:
            existing_stop_keys.add((str(row[0]), int(row[1])))

        for stop in stops_rows:
            svc_id = _clean(stop.get("service_id"))
            seq = _int(stop.get("stop_sequence"))
            if not svc_id or seq is None:
                stats["skipped"] += 1
                continue
            if (svc_id, seq) in existing_stop_keys:
                stats["skipped"] += 1
                continue
            if svc_id not in existing_service_ids:
                stats["errors"].append(f"Stop references unknown service_id={svc_id}")
                stats["skipped"] += 1
                continue

            raw_place = _clean(stop.get("canonical_place_id"))
            canonical_place_id = raw_place if raw_place and raw_place in valid_place_ids else None

            session.add(BusServiceStop(
                service_id=svc_id,
                stop_sequence=seq,
                stop_name_raw=_clean(stop.get("stop_name_raw")) or None,
                normalized_stop_name=_clean(stop.get("normalized_stop_name")) or None,
                canonical_place_id=canonical_place_id,
                canonical_name_en=_clean(stop.get("canonical_name_en")) or None,
                source_id=_clean(stop.get("source_id")) or None,
            ))
            existing_stop_keys.add((svc_id, seq))
            stats["stops_inserted"] += 1

        session.commit()

    logger.info(
        "Bus seed import complete: services=%d, stops=%d, skipped=%d",
        stats["services_inserted"],
        stats["stops_inserted"],
        stats["skipped"],
    )
    return stats


__all__ = ["import_bus_seed", "SEED_DIR"]
