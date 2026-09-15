"""Production deployment audit for the bus seed import.

Reads the exact seed CSVs, queries production before/after import, and writes
durable JSON audit manifests to ``backend/data/commute_seed/deployment_audit/``.

The manifest records which seed service IDs and stop PK pairs already existed,
which were newly inserted, and whether any conflicts exist.  Expected identity
sets are derived directly from the CSVs — never from a hardcoded SVC range.

Usage::

    from app.services.commute.deployment_audit import (
        generate_preimport_manifest,
        generate_postimport_manifest,
    )
    pre = generate_preimport_manifest()
    # ... run import ...
    post = generate_postimport_manifest(pre)

No DATABASE_URL or secrets are written to the manifest.
"""
from __future__ import annotations

import csv
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import func, select

from app.database.connection import get_sessionmaker
from app.database.models import BusService, BusServiceStop, ServiceRouteMatch

logger = logging.getLogger("gochano.commute.deployment_audit")

AUDIT_DIR = Path(__file__).resolve().parents[3] / "data" / "commute_seed" / "deployment_audit"
SEED_DIR = Path(__file__).resolve().parents[3] / "data" / "commute_seed" / "gochano_bus_seed_v1"


# ---------------------------------------------------------------------------
# CSV reading helpers
# ---------------------------------------------------------------------------

def _read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def _clean(value: str | None) -> str:
    return (value or "").strip()


# ---------------------------------------------------------------------------
# Identity derivation from CSVs (§5: no hardcoded SVC range)
# ---------------------------------------------------------------------------

def derive_expected_service_ids(seed_dir: Path | None = None) -> set[str]:
    """Derive the complete expected service-ID set from bus_services_seed.csv."""
    d = seed_dir or SEED_DIR
    rows = _read_csv(d / "bus_services_seed.csv")
    return {_clean(r.get("service_id")) for r in rows if _clean(r.get("service_id"))}


def derive_expected_stop_pairs(seed_dir: Path | None = None) -> set[tuple[str, int]]:
    """Derive the complete expected (service_id, stop_sequence) set from CSV."""
    d = seed_dir or SEED_DIR
    rows = _read_csv(d / "bus_service_stops_seed.csv")
    pairs: set[tuple[str, int]] = set()
    for r in rows:
        svc = _clean(r.get("service_id"))
        seq_raw = (r.get("stop_sequence") or "").strip()
        if svc and seq_raw:
            try:
                seq = int(seq_raw)
                if seq > 0:
                    pairs.add((svc, seq))
            except (ValueError, TypeError):
                pass
    return pairs


def derive_expected_service_fields(seed_dir: Path | None = None) -> dict[str, dict[str, str]]:
    """Map service_id -> {csv field values} for conflict comparison."""
    d = seed_dir or SEED_DIR
    rows = _read_csv(d / "bus_services_seed.csv")
    result: dict[str, dict[str, str]] = {}
    for r in rows:
        sid = _clean(r.get("service_id"))
        if not sid:
            continue
        result[sid] = {
            "operator_name_en": _clean(r.get("operator_name_en")),
            "operator_name_bn": _clean(r.get("operator_name_bn")),
            "variant_no_for_operator": _clean(r.get("variant_no_for_operator")),
            "start_stop_raw": _clean(r.get("start_stop_raw")),
            "end_stop_raw": _clean(r.get("end_stop_raw")),
            "stop_count": _clean(r.get("stop_count")),
            "service_type": _clean(r.get("service_type")),
            "time_text": _clean(r.get("time_text")),
            "image_url": _clean(r.get("image_url")),
            "current_status": _clean(r.get("current_status")),
        }
    return result


def derive_expected_stop_fields(seed_dir: Path | None = None) -> dict[tuple[str, int], dict[str, str]]:
    """Map (service_id, stop_sequence) -> {csv field values} for conflict comparison."""
    d = seed_dir or SEED_DIR
    rows = _read_csv(d / "bus_service_stops_seed.csv")
    result: dict[tuple[str, int], dict[str, str]] = {}
    for r in rows:
        svc = _clean(r.get("service_id"))
        seq_raw = (r.get("stop_sequence") or "").strip()
        if not svc or not seq_raw:
            continue
        try:
            seq = int(seq_raw)
        except (ValueError, TypeError):
            continue
        result[(svc, seq)] = {
            "stop_name_raw": _clean(r.get("stop_name_raw")),
            "normalized_stop_name": _clean(r.get("normalized_stop_name")),
            "canonical_place_id": _clean(r.get("canonical_place_id")),
            "canonical_name_en": _clean(r.get("canonical_name_en")),
        }
    return result


# ---------------------------------------------------------------------------
# Pre-import manifest (§3)
# ---------------------------------------------------------------------------

def generate_preimport_manifest(seed_dir: Path | None = None) -> dict[str, Any]:
    """Query the DB and produce the pre-import identity manifest.

    Records which expected service IDs and stop pairs already exist, and
    captures the pre-deployment verified match state (§7).
    """
    expected_svc_ids = derive_expected_service_ids(seed_dir)
    expected_stop_pairs = derive_expected_stop_pairs(seed_dir)

    with get_sessionmaker()() as session:
        # Existing service IDs
        existing_svc_ids = set()
        for row in session.execute(select(BusService.service_id)):
            existing_svc_ids.add(str(row[0]))

        # Existing stop pairs
        existing_stop_pairs: set[tuple[str, int]] = set()
        for row in session.execute(
            select(BusServiceStop.service_id, BusServiceStop.stop_sequence)
        ):
            existing_stop_pairs.add((str(row[0]), int(row[1])))

        # Verified match state (§7)
        verified_count = session.execute(
            select(func.count()).select_from(ServiceRouteMatch).where(
                ServiceRouteMatch.verified.is_(True)  # type: ignore[union-attr]
            )
        ).scalar_one()

    pre_existing_svc = existing_svc_ids & expected_svc_ids
    missing_before_svc = expected_svc_ids - existing_svc_ids
    pre_existing_stop = existing_stop_pairs & expected_stop_pairs
    missing_before_stop = expected_stop_pairs - existing_stop_pairs

    manifest: dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "phase": "pre_import",
        "expectedServiceIds": sorted(expected_svc_ids),
        "expectedStopPairs": sorted(f"{s},{n}" for s, n in expected_stop_pairs),
        "preExistingServiceIds": sorted(pre_existing_svc),
        "missingServiceIdsBeforeImport": sorted(missing_before_svc),
        "preExistingStopPairs": sorted(f"{s},{n}" for s, n in pre_existing_stop),
        "missingStopPairsBeforeImport": sorted(f"{s},{n}" for s, n in missing_before_stop),
        "verifiedMatchCountPreDeploy": verified_count,
    }

    _write_manifest(manifest, "pre")
    return manifest


# ---------------------------------------------------------------------------
# Post-import manifest (§3, §4, §6)
# ---------------------------------------------------------------------------

def generate_postimport_manifest(
    pre_manifest: dict[str, Any],
    insert_result: dict[str, Any] | None = None,
    seed_dir: Path | None = None,
) -> dict[str, Any]:
    """After import, compare DB state against CSV expectations.

    Produces a manifest with newlyInsertedServiceIds, newlyInsertedStopPairs,
    conflicts, and missingExpectedIds.
    """
    expected_svc_ids = derive_expected_service_ids(seed_dir)
    expected_stop_pairs = derive_expected_stop_pairs(seed_dir)
    svc_fields = derive_expected_service_fields(seed_dir)
    stop_fields = derive_expected_stop_fields(seed_dir)

    with get_sessionmaker()() as session:
        # Current service IDs
        current_svc_ids: set[str] = set()
        for row in session.execute(select(BusService.service_id)):
            current_svc_ids.add(str(row[0]))

        # Current stop pairs
        current_stop_pairs: set[tuple[str, int]] = set()
        for row in session.execute(
            select(BusServiceStop.service_id, BusServiceStop.stop_sequence)
        ):
            current_stop_pairs.add((str(row[0]), int(row[1])))

        # Verified match state (§7)
        verified_count = session.execute(
            select(func.count()).select_from(ServiceRouteMatch).where(
                ServiceRouteMatch.verified.is_(True)  # type: ignore[union-attr]
            )
        ).scalar_one()

        # --- Conflict detection (§6) ---
        service_conflicts: list[dict[str, Any]] = []
        stop_conflicts: list[dict[str, Any]] = []

        # Check service conflicts for pre-existing IDs
        pre_existing_svc = set(pre_manifest.get("preExistingServiceIds", []))
        for sid in sorted(pre_existing_svc & current_svc_ids):
            if sid not in svc_fields:
                continue
            db_svc = session.get(BusService, sid)
            if not db_svc:
                continue
            csv_row = svc_fields[sid]
            diffs: dict[str, str] = {}
            for field in csv_row:
                db_val = str(getattr(db_svc, field, "") or "")
                csv_val = csv_row[field]
                if db_val != csv_val:
                    diffs[field] = f"db={db_val!r} csv={csv_val!r}"
            if diffs:
                service_conflicts.append({"serviceId": sid, "differences": diffs})

        # Check stop conflicts for pre-existing PK pairs
        pre_existing_stop_raw = set(pre_manifest.get("preExistingStopPairs", []))
        pre_existing_stop: set[tuple[str, int]] = set()
        for s in pre_existing_stop_raw:
            parts = s.split(",", 1)
            if len(parts) == 2:
                try:
                    pre_existing_stop.add((parts[0], int(parts[1])))
                except ValueError:
                    pass

        for svc_id, seq in sorted(pre_existing_stop & current_stop_pairs):
            if (svc_id, seq) not in stop_fields:
                continue
            csv_row = stop_fields[(svc_id, seq)]
            db_stop = session.execute(
                select(BusServiceStop).where(
                    BusServiceStop.service_id == svc_id,
                    BusServiceStop.stop_sequence == seq,
                )
            ).scalar_one_or_none()
            if not db_stop:
                continue
            diffs: dict[str, str] = {}
            for field in csv_row:
                db_val = str(getattr(db_stop, field, "") or "")
                csv_val = csv_row[field]
                if db_val != csv_val:
                    diffs[field] = f"db={db_val!r} csv={csv_val!r}"
            if diffs:
                stop_conflicts.append({
                    "serviceId": svc_id,
                    "stopSequence": seq,
                    "differences": diffs,
                })

    newly_inserted_svc = sorted(expected_svc_ids - set(pre_manifest.get("preExistingServiceIds", [])))
    newly_inserted_stop = sorted(
        f"{s},{n}" for s, n in expected_stop_pairs
        if f"{s},{n}" not in set(pre_manifest.get("preExistingStopPairs", []))
    )

    manifest: dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "phase": "post_import",
        "preImportTimestamp": pre_manifest.get("timestamp"),
        "newlyInsertedServiceIds": newly_inserted_svc,
        "newlyInsertedStopPairs": newly_inserted_stop,
        "missingExpectedServiceIds": sorted(expected_svc_ids - current_svc_ids),
        "missingExpectedStopPairs": sorted(
            f"{s},{n}" for s, n in expected_stop_pairs
            if (s, n) not in current_stop_pairs
        ),
        "serviceConflicts": service_conflicts,
        "stopConflicts": stop_conflicts,
        "unresolvedConflicts": len(service_conflicts) + len(stop_conflicts),
        "verifiedMatchCountPostImport": verified_count,
        "verifiedMatchStateUnchanged": (
            verified_count == pre_manifest.get("verifiedMatchCountPreDeploy", 0)
        ),
        "insertResult": insert_result,
    }

    _write_manifest(manifest, "post")
    return manifest


# ---------------------------------------------------------------------------
# Manifest I/O
# ---------------------------------------------------------------------------

def _write_manifest(manifest: dict[str, Any], phase: str) -> Path:
    """Write the manifest to the audit directory."""
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    filename = f"bus_seed_{phase}_import_{ts}.json"
    path = AUDIT_DIR / filename
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    logger.info("Deployment manifest written: %s", path)
    return path


__all__ = [
    "derive_expected_service_ids",
    "derive_expected_stop_pairs",
    "derive_expected_service_fields",
    "derive_expected_stop_fields",
    "generate_preimport_manifest",
    "generate_postimport_manifest",
    "AUDIT_DIR",
    "SEED_DIR",
]
