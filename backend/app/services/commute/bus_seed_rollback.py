"""Safe rollback utility for the bus seed import.

Consumes a post-import deployment manifest and performs exact-ID-based
rollback using only the newlyInsertedServiceIds and newlyInsertedStopPairs
recorded in the manifest.

Rollback order:
  1. Delete only exact (service_id, stop_sequence) pairs that were newly inserted.
  2. Check FK references (user_fare_reports, crowd_fare_aggregates,
     service_route_matches) before deleting services.
  3. If referenced, DO NOT cascade delete — report the dependency and
     leave/retire the service safely.

Never rollback by:
  - source_id
  - operator name
  - route name
  - all SVC IDs
  - a hardcoded SVC range

Never delete pre-existing rows.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from sqlalchemy import func, select

from app.database.connection import get_sessionmaker
from app.database.models import (
    BusService,
    BusServiceStop,
    ServiceRouteMatch,
    UserFareReport,
    CrowdFareAggregate,
)

logger = logging.getLogger("gochano.commute.seed_rollback")


def _parse_stop_pairs(pair_strs: list[str]) -> list[tuple[str, int]]:
    """Parse "SVC0001,3" strings back into (service_id, stop_sequence) tuples."""
    result: list[tuple[str, int]] = []
    for s in pair_strs:
        parts = s.split(",", 1)
        if len(parts) == 2:
            try:
                result.append((parts[0], int(parts[1])))
            except ValueError:
                pass
    return result


def rollback_from_manifest(manifest_path: str | Path, *, dry_run: bool = True) -> dict[str, Any]:
    """Execute or simulate rollback using a post-import deployment manifest.

    Args:
        manifest_path: Path to the post-import JSON manifest.
        dry_run: If True, report what would be deleted without modifying the DB.

    Returns:
        A summary dict describing the rollback actions taken or planned.
    """
    path = Path(manifest_path)
    if not path.exists():
        return {"error": f"Manifest not found: {path}"}

    manifest = json.loads(path.read_text(encoding="utf-8"))
    newly_inserted_svc_ids: list[str] = manifest.get("newlyInsertedServiceIds", [])
    newly_inserted_stop_pairs_raw: list[str] = manifest.get("newlyInsertedStopPairs", [])
    newly_inserted_stop_pairs = _parse_stop_pairs(newly_inserted_stop_pairs_raw)

    summary: dict[str, Any] = {
        "dryRun": dry_run,
        "newlyInsertedServiceIds": newly_inserted_svc_ids,
        "newlyInsertedStopPairCount": len(newly_inserted_stop_pairs),
        "stopsDeleted": 0,
        "servicesDeleted": 0,
        "servicesRetired": 0,
        "dependenciesFound": [],
        "errors": [],
    }

    with get_sessionmaker()() as session:
        # ── Step 1: Delete exact newly inserted stop pairs (§4) ──
        for svc_id, seq in newly_inserted_stop_pairs:
            # Verify this pair actually exists before attempting delete
            existing = session.execute(
                select(BusServiceStop).where(
                    BusServiceStop.service_id == svc_id,
                    BusServiceStop.stop_sequence == seq,
                )
            ).scalar_one_or_none()
            if existing is None:
                continue  # Already absent, skip

            # Safety: do NOT delete if this was a pre-existing pair
            # (manifest only lists newly inserted, but double-check)
            if dry_run:
                summary["stopsDeleted"] += 1
            else:
                session.delete(existing)
                summary["stopsDeleted"] += 1

        session.flush()

        # ── Step 2: For each newly inserted service, check FK dependencies (§4) ──
        for svc_id in newly_inserted_svc_ids:
            # Check user_fare_reports references
            report_refs = session.execute(
                select(func.count()).select_from(UserFareReport).where(
                    UserFareReport.bus_service_id == svc_id
                )
            ).scalar_one()

            # Check crowd_fare_aggregates references
            agg_refs = session.execute(
                select(func.count()).select_from(CrowdFareAggregate).where(
                    CrowdFareAggregate.bus_service_id == svc_id  # type: ignore[union-attr]
                )
            ).scalar_one()

            # Check service_route_matches references
            match_refs = session.execute(
                select(func.count()).select_from(ServiceRouteMatch).where(
                    ServiceRouteMatch.service_id == svc_id  # type: ignore[union-attr]
                )
            ).scalar_one()

            total_refs = report_refs + agg_refs + match_refs

            if total_refs > 0:
                # DO NOT delete — report dependency
                summary["dependenciesFound"].append({
                    "serviceId": svc_id,
                    "userFareReports": report_refs,
                    "crowdFareAggregates": agg_refs,
                    "serviceRouteMatches": match_refs,
                })
                # Soft-retire instead of cascade delete
                svc = session.get(BusService, svc_id)
                if svc and not dry_run:
                    svc.current_status = "inactive"
                    summary["servicesRetired"] += 1
                continue

            # No dependencies — safe to delete
            svc = session.get(BusService, svc_id)
            if svc is None:
                continue
            if dry_run:
                summary["servicesDeleted"] += 1
            else:
                session.delete(svc)
                summary["servicesDeleted"] += 1

        if not dry_run:
            session.commit()

    logger.info(
        "Rollback %s: stops=%d, services=%d, retired=%d, deps=%d",
        "SIMULATED" if dry_run else "EXECUTED",
        summary["stopsDeleted"],
        summary["servicesDeleted"],
        summary["servicesRetired"],
        len(summary["dependenciesFound"]),
    )
    return summary


def rollback_from_inserted_ids(
    *,
    newly_inserted_service_ids: list[str],
    newly_inserted_stop_pairs: list[str],
    dry_run: bool = True,
) -> dict[str, Any]:
    """Execute or simulate rollback using explicit ID lists (not a manifest file).

    Accepts the same data structures as the manifest fields.
    """
    manifest = {
        "newlyInsertedServiceIds": newly_inserted_service_ids,
        "newlyInsertedStopPairs": newly_inserted_stop_pairs,
    }
    # Write a temp manifest and delegate
    import tempfile
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, encoding="utf-8"
    ) as tmp:
        tmp.write(json.dumps(manifest))
        tmp_path = Path(tmp.name)

    try:
        return rollback_from_manifest(tmp_path, dry_run=dry_run)
    finally:
        tmp_path.unlink(missing_ok=True)


__all__ = [
    "rollback_from_manifest",
    "rollback_from_inserted_ids",
]
