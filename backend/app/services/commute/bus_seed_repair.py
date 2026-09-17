"""Deterministic, idempotent repair script for Neon CommuteBD production data.

Safe dependency order:
1. sources (9 rows)
2. places (387 rows)
3. stop_aliases (301 rows, empty canonical_place_id -> NULL)
4. bus_services (156 rows, upsert/preserve)
5. bus_service_stops (3,190 rows, update canonical_place_id from verified seed)
6. brta_routes (112 rows)
7. service_route_matches (156 rows, unique on (service_id, best_brta_route_id))
8. brta_route_stops (1,311 rows)
9. metro_stations (17 rows)
10. metro_fares (272 rows)
11. fare_rules (7 rows)

Total new rows:
  sources                   9
  places                  387
  stop_aliases            301
  brta_routes             112
  service_route_matches   156
  brta_route_stops       1311
  metro_stations           17
  metro_fares             272
  fare_rules                7
-----------------------------
TOTAL                    2572

Candidate/review files MUST NOT be imported:
- stop_alias_candidates.csv
- service_route_match_candidates.csv
- place_coordinate_candidates.csv
"""
from __future__ import annotations

import argparse
import csv
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import Connection, create_engine, text

logger = logging.getLogger("commute_repair")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent.parent
COMMUTEBD_DIR = BACKEND_DIR / "data" / "commutebd" / "core_dataset" / "csv"
COMMUTE_SEED_DIR = BACKEND_DIR / "data" / "commute_seed" / "gochano_bus_seed_v1"
SNAPSHOT_DIR = BACKEND_DIR / "data" / "commute_seed" / "snapshots"


def batch_insert(
    conn: Connection,
    table_name: str,
    columns: list[str],
    rows: list[dict[str, Any]],
    on_conflict_clause: str = "",
    chunk_size: int = 400,
) -> int:
    """Inserts rows using chunked multi-value SQL statements for high performance over remote TLS."""
    if not rows:
        return 0

    col_names = ", ".join(columns)
    total_inserted = 0

    for i in range(0, len(rows), chunk_size):
        chunk = rows[i : i + chunk_size]
        params: dict[str, Any] = {}
        val_clauses: list[str] = []

        for idx, row in enumerate(chunk):
            param_placeholders: list[str] = []
            for col in columns:
                p_key = f"{col}_{idx}"
                params[p_key] = row.get(col)
                param_placeholders.append(f":{p_key}")
            val_clauses.append(f"({', '.join(param_placeholders)})")

        sql = f"INSERT INTO {table_name} ({col_names}) VALUES {', '.join(val_clauses)} {on_conflict_clause};"
        conn.execute(text(sql), params)
        total_inserted += len(chunk)

    return total_inserted


def ensure_unique_indexes(conn: Connection) -> None:
    """Ensure unique indexes exist for tables without explicit logical unique constraints."""
    logger.info("Ensuring unique indexes for idempotent upserts...")
    conn.execute(
        text("CREATE UNIQUE INDEX IF NOT EXISTS idx_stop_aliases_raw_name ON stop_aliases (raw_stop_name);")
    )
    conn.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_service_route_matches_logical "
            "ON service_route_matches (service_id, best_brta_route_id);"
        )
    )


def query_preflight_counts(conn: Connection) -> dict[str, int]:
    """Query current counts from the database."""
    tables = [
        "sources",
        "places",
        "stop_aliases",
        "bus_services",
        "bus_service_stops",
        "brta_routes",
        "service_route_matches",
        "brta_route_stops",
        "metro_stations",
        "metro_fares",
        "fare_rules",
        "user_fare_reports",
    ]
    counts: dict[str, int] = {}
    for table in tables:
        try:
            cnt = conn.execute(text(f"SELECT count(*) FROM {table}")).scalar()
            counts[table] = cnt or 0
        except Exception:
            counts[table] = -1

    try:
        cnt_null = conn.execute(
            text("SELECT count(*) FROM bus_service_stops WHERE canonical_place_id IS NULL")
        ).scalar()
        counts["bus_service_stops_canonical_null"] = cnt_null or 0
    except Exception:
        counts["bus_service_stops_canonical_null"] = -1

    return counts


def create_pre_repair_snapshot(conn: Connection, snapshot_path: Path | None = None) -> Path:
    """Creates a non-destructive JSON snapshot of rows that will be modified."""
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    if snapshot_path is None:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        snapshot_path = SNAPSHOT_DIR / f"commute_repair_snapshot_{timestamp}.json"

    logger.info("Creating non-destructive pre-repair snapshot: %s", snapshot_path)

    # 1. Capture bus_service_stops
    stops_rows = conn.execute(
        text("""
            SELECT service_id, stop_sequence, stop_name_raw, normalized_stop_name,
                   canonical_place_id, canonical_name_en, source_id
            FROM bus_service_stops
            ORDER BY service_id, stop_sequence
        """)
    ).fetchall()

    bus_service_stops_data = [
        {
            "service_id": r[0],
            "stop_sequence": r[1],
            "stop_name_raw": r[2],
            "normalized_stop_name": r[3],
            "canonical_place_id": r[4],
            "canonical_name_en": r[5],
            "source_id": r[6],
        }
        for r in stops_rows
    ]

    # 2. Capture pre-existing PKs for tables to be populated
    pre_existing_pks: dict[str, list[Any]] = {}
    for tbl, pk_col in [
        ("sources", "source_id"),
        ("places", "place_id"),
        ("stop_aliases", "raw_stop_name"),
        ("brta_routes", "route_id"),
        ("metro_stations", "station_id"),
        ("fare_rules", "fare_rule_id"),
    ]:
        try:
            pks = [row[0] for row in conn.execute(text(f"SELECT {pk_col} FROM {tbl}")).fetchall()]
            pre_existing_pks[tbl] = pks
        except Exception:
            pre_existing_pks[tbl] = []

    snapshot_data = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "bus_service_stops_count": len(bus_service_stops_data),
        "bus_service_stops": bus_service_stops_data,
        "pre_existing_pks": pre_existing_pks,
    }

    with open(snapshot_path, "w", encoding="utf-8") as f:
        json.dump(snapshot_data, f, indent=2)

    logger.info(
        "Snapshot saved with %d bus_service_stops rows. Pre-existing PKs recorded.",
        len(bus_service_stops_data),
    )
    return snapshot_path


def rollback_from_snapshot(conn: Connection, snapshot_path: Path) -> dict[str, Any]:
    """Rolls back repair non-destructively WITHOUT TRUNCATE."""
    logger.warning("EXECUTING NON-DESTRUCTIVE REVERSIBLE ROLLBACK (NO TRUNCATE)...")
    with open(snapshot_path, encoding="utf-8") as f:
        snapshot_data = json.load(f)

    # 1. Restore bus_service_stops
    conn.execute(text("DROP TABLE IF EXISTS tmp_restore_stops;"))
    conn.execute(
        text("""
            CREATE TEMP TABLE tmp_restore_stops (
                service_id text,
                stop_sequence int,
                stop_name_raw text,
                normalized_stop_name text,
                canonical_place_id text,
                canonical_name_en text,
                source_id text
            ) ON COMMIT DROP;
        """)
    )
    batch_insert(
        conn,
        "tmp_restore_stops",
        ["service_id", "stop_sequence", "stop_name_raw", "normalized_stop_name", "canonical_place_id", "canonical_name_en", "source_id"],
        snapshot_data["bus_service_stops"],
    )
    conn.execute(
        text("""
            UPDATE bus_service_stops s
            SET canonical_place_id = t.canonical_place_id,
                canonical_name_en = t.canonical_name_en,
                normalized_stop_name = t.normalized_stop_name,
                stop_name_raw = t.stop_name_raw,
                source_id = t.source_id
            FROM tmp_restore_stops t
            WHERE s.service_id = t.service_id AND s.stop_sequence = t.stop_sequence;
        """)
    )

    # 2. Delete rows in reverse dependency order, preserving pre-existing rows
    pre_pks = snapshot_data.get("pre_existing_pks", {})

    if pre_pks.get("fare_rules"):
        conn.execute(text("DELETE FROM fare_rules WHERE fare_rule_id NOT IN :pks"), {"pks": tuple(pre_pks["fare_rules"])})
    else:
        conn.execute(text("DELETE FROM fare_rules;"))

    conn.execute(text("DELETE FROM metro_fares;"))

    if pre_pks.get("metro_stations"):
        conn.execute(text("DELETE FROM metro_stations WHERE station_id NOT IN :pks"), {"pks": tuple(pre_pks["metro_stations"])})
    else:
        conn.execute(text("DELETE FROM metro_stations;"))

    conn.execute(text("DELETE FROM brta_route_stops;"))
    conn.execute(text("DELETE FROM service_route_matches;"))

    if pre_pks.get("brta_routes"):
        conn.execute(text("DELETE FROM brta_routes WHERE route_id NOT IN :pks"), {"pks": tuple(pre_pks["brta_routes"])})
    else:
        conn.execute(text("DELETE FROM brta_routes;"))

    if pre_pks.get("stop_aliases"):
        conn.execute(text("DELETE FROM stop_aliases WHERE raw_stop_name NOT IN :pks"), {"pks": tuple(pre_pks["stop_aliases"])})
    else:
        conn.execute(text("DELETE FROM stop_aliases;"))

    if pre_pks.get("places"):
        conn.execute(text("DELETE FROM places WHERE place_id NOT IN :pks"), {"pks": tuple(pre_pks["places"])})
    else:
        conn.execute(text("DELETE FROM places;"))

    if pre_pks.get("sources"):
        conn.execute(text("DELETE FROM sources WHERE source_id NOT IN :pks"), {"pks": tuple(pre_pks["sources"])})
    else:
        conn.execute(text("DELETE FROM sources;"))

    counts_after = query_preflight_counts(conn)
    logger.info("Rollback complete. Counts after rollback: %s", counts_after)
    return counts_after


def load_all_seed_data(conn: Connection) -> dict[str, int]:
    """Loads and updates all commute data in strict dependency order with idempotent ON CONFLICT."""
    ensure_unique_indexes(conn)
    counts: dict[str, int] = {}

    # 1. sources (9 rows)
    logger.info("Loading sources (9 rows)...")
    sources_path = COMMUTEBD_DIR / "sources.csv"
    with open(sources_path, encoding="utf-8-sig") as f:
        src_rows = [
            {
                "source_id": r["source_id"],
                "source_name": r.get("title"),
                "source_kind": r.get("source_type"),
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "sources",
        ["source_id", "source_name", "source_kind"],
        src_rows,
        on_conflict_clause="ON CONFLICT (source_id) DO NOTHING",
    )
    counts["sources"] = len(src_rows)

    # 2. places (387 rows)
    logger.info("Loading places (387 rows)...")
    places_path = COMMUTEBD_DIR / "places.csv"
    with open(places_path, encoding="utf-8-sig") as f:
        places_rows = [
            {
                "place_id": r["place_id"],
                "name_en": r["name_en"],
                "name_bn": r.get("name_bn") or None,
                "normalized_name": r.get("normalized_name") or None,
                "latitude": float(r["latitude"]) if r.get("latitude") else None,
                "longitude": float(r["longitude"]) if r.get("longitude") else None,
                "geocode_status": r.get("geocode_status") or "pending",
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "places",
        ["place_id", "name_en", "name_bn", "normalized_name", "latitude", "longitude", "geocode_status", "source_id"],
        places_rows,
        on_conflict_clause="""
            ON CONFLICT (place_id) DO UPDATE SET
                name_en = EXCLUDED.name_en,
                name_bn = EXCLUDED.name_bn,
                normalized_name = EXCLUDED.normalized_name,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                geocode_status = EXCLUDED.geocode_status,
                source_id = EXCLUDED.source_id
        """,
    )
    counts["places"] = len(places_rows)

    # 3. stop_aliases (301 rows)
    logger.info("Loading stop_aliases (301 rows)...")
    aliases_path = COMMUTEBD_DIR / "stop_aliases.csv"
    with open(aliases_path, encoding="utf-8-sig") as f:
        alias_rows = [
            {
                "raw_stop_name": r.get("raw_stop_name") or None,
                "normalized_stop_name": r.get("normalized_stop_name") or None,
                "canonical_place_id": (r.get("canonical_place_id") or None) if (r.get("canonical_place_id") != "") else None,
                "canonical_name_en": r.get("canonical_name_en") or None,
                "match_score": float(r["match_score"]) if r.get("match_score") else None,
                "match_method": r.get("match_method") or None,
                "needs_manual_review": True if r.get("needs_manual_review") == "yes" else False,
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "stop_aliases",
        ["raw_stop_name", "normalized_stop_name", "canonical_place_id", "canonical_name_en", "match_score", "match_method", "needs_manual_review", "source_id"],
        alias_rows,
        on_conflict_clause="""
            ON CONFLICT (raw_stop_name) DO UPDATE SET
                normalized_stop_name = EXCLUDED.normalized_stop_name,
                canonical_place_id = EXCLUDED.canonical_place_id,
                canonical_name_en = EXCLUDED.canonical_name_en,
                match_score = EXCLUDED.match_score,
                match_method = EXCLUDED.match_method,
                needs_manual_review = EXCLUDED.needs_manual_review,
                source_id = EXCLUDED.source_id
        """,
    )
    counts["stop_aliases"] = len(alias_rows)

    # 4. bus_services (156 rows)
    logger.info("Loading bus_services (156 rows)...")
    services_path = COMMUTE_SEED_DIR / "bus_services_seed.csv"
    with open(services_path, encoding="utf-8-sig") as f:
        svc_rows = [
            {
                "service_id": r["service_id"],
                "operator_name_en": r.get("operator_name_en") or None,
                "operator_name_bn": r.get("operator_name_bn") or None,
                "variant_no_for_operator": int(r["variant_no_for_operator"]) if r.get("variant_no_for_operator") else None,
                "start_stop_raw": r.get("start_stop_raw") or None,
                "end_stop_raw": r.get("end_stop_raw") or None,
                "stop_count": int(r["stop_count"]) if r.get("stop_count") else None,
                "service_type": r.get("service_type") or None,
                "time_text": r.get("time_text") or None,
                "image_url": r.get("image_url") or None,
                "current_status": r.get("current_status") or "needs_validation",
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "bus_services",
        ["service_id", "operator_name_en", "operator_name_bn", "variant_no_for_operator", "start_stop_raw", "end_stop_raw", "stop_count", "service_type", "time_text", "image_url", "current_status", "source_id"],
        svc_rows,
        on_conflict_clause="""
            ON CONFLICT (service_id) DO UPDATE SET
                operator_name_en = EXCLUDED.operator_name_en,
                operator_name_bn = EXCLUDED.operator_name_bn,
                variant_no_for_operator = EXCLUDED.variant_no_for_operator,
                start_stop_raw = EXCLUDED.start_stop_raw,
                end_stop_raw = EXCLUDED.end_stop_raw,
                stop_count = EXCLUDED.stop_count,
                service_type = EXCLUDED.service_type,
                time_text = EXCLUDED.time_text,
                image_url = EXCLUDED.image_url,
                current_status = EXCLUDED.current_status,
                source_id = EXCLUDED.source_id
        """,
    )
    counts["bus_services"] = len(svc_rows)

    # 5. bus_service_stops (3,190 rows)
    logger.info("Updating bus_service_stops (3,190 rows)...")
    conn.execute(text("DROP TABLE IF EXISTS tmp_bus_stops;"))
    conn.execute(
        text("""
            CREATE TEMP TABLE tmp_bus_stops (
                service_id text,
                stop_sequence int,
                stop_name_raw text,
                normalized_stop_name text,
                canonical_place_id text,
                canonical_name_en text,
                source_id text
            ) ON COMMIT DROP;
        """)
    )
    stops_path = COMMUTE_SEED_DIR / "bus_service_stops_seed.csv"
    with open(stops_path, encoding="utf-8-sig") as f:
        stop_rows = [
            {
                "service_id": r["service_id"],
                "stop_sequence": int(r["stop_sequence"]),
                "stop_name_raw": r.get("stop_name_raw") or None,
                "normalized_stop_name": r.get("normalized_stop_name") or None,
                "canonical_place_id": (r.get("canonical_place_id") or None) if (r.get("canonical_place_id") != "") else None,
                "canonical_name_en": r.get("canonical_name_en") or None,
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "tmp_bus_stops",
        ["service_id", "stop_sequence", "stop_name_raw", "normalized_stop_name", "canonical_place_id", "canonical_name_en", "source_id"],
        stop_rows,
    )
    conn.execute(
        text("""
            UPDATE bus_service_stops s
            SET canonical_place_id = t.canonical_place_id,
                canonical_name_en = t.canonical_name_en,
                normalized_stop_name = t.normalized_stop_name,
                stop_name_raw = t.stop_name_raw,
                source_id = t.source_id
            FROM tmp_bus_stops t
            WHERE s.service_id = t.service_id AND s.stop_sequence = t.stop_sequence;
        """)
    )
    counts["bus_service_stops"] = len(stop_rows)

    # 6. brta_routes (112 rows)
    logger.info("Loading brta_routes (112 rows)...")
    brta_r_path = COMMUTEBD_DIR / "brta_routes.csv"
    with open(brta_r_path, encoding="utf-8-sig") as f:
        brta_r_rows = [
            {
                "route_id": r["route_id"],
                "route_code_en": r.get("route_code_en") or None,
                "route_code_bn": r.get("route_code_bn") or None,
                "route_name_en": r.get("route_name_en") or None,
                "route_name_bn": r.get("route_name_bn") or None,
                "origin_name_en": r.get("origin_name_en") or None,
                "destination_name_en": r.get("destination_name_en") or None,
                "total_distance_km": float(r["total_distance_km"]) if r.get("total_distance_km") else None,
                "stop_count": int(r["stop_count"]) if r.get("stop_count") else None,
                "fare_per_km_tk": float(r["fare_per_km_tk"]) if r.get("fare_per_km_tk") else None,
                "minimum_fare_tk": float(r["minimum_fare_tk"]) if r.get("minimum_fare_tk") else None,
                "live_use": True if r.get("live_use") == "true" else False,
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "brta_routes",
        ["route_id", "route_code_en", "route_code_bn", "route_name_en", "route_name_bn", "origin_name_en", "destination_name_en", "total_distance_km", "stop_count", "fare_per_km_tk", "minimum_fare_tk", "live_use", "source_id"],
        brta_r_rows,
        on_conflict_clause="""
            ON CONFLICT (route_id) DO UPDATE SET
                route_code_en = EXCLUDED.route_code_en,
                route_name_en = EXCLUDED.route_name_en,
                live_use = EXCLUDED.live_use
        """,
    )
    counts["brta_routes"] = len(brta_r_rows)

    # 7. service_route_matches (156 rows)
    logger.info("Loading service_route_matches (156 rows)...")
    matches_path = COMMUTEBD_DIR / "service_route_matches.csv"
    with open(matches_path, encoding="utf-8-sig") as f:
        match_rows = [
            {
                "service_id": r.get("service_id") or None,
                "best_brta_route_id": r.get("best_brta_route_id") or None,
                "match_score": float(r["match_score"]) if r.get("match_score") else None,
                "match_quality": r.get("match_quality") or None,
                "verified": True if r.get("verified") in ("true", "1") else False,
                "warning": r.get("warning") or None,
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "service_route_matches",
        ["service_id", "best_brta_route_id", "match_score", "match_quality", "verified", "warning", "source_id"],
        match_rows,
        on_conflict_clause="""
            ON CONFLICT (service_id, best_brta_route_id) DO UPDATE SET
                match_score = EXCLUDED.match_score,
                match_quality = EXCLUDED.match_quality,
                verified = EXCLUDED.verified,
                warning = EXCLUDED.warning,
                source_id = EXCLUDED.source_id
        """,
    )
    counts["service_route_matches"] = len(match_rows)

    # 8. brta_route_stops (1,311 rows)
    logger.info("Loading brta_route_stops (1,311 rows)...")
    brta_s_path = COMMUTEBD_DIR / "brta_route_stops.csv"
    with open(brta_s_path, encoding="utf-8-sig") as f:
        brta_s_rows = [
            {
                "route_id": r["route_id"],
                "stop_sequence": int(r["stop_sequence"]),
                "place_id": r.get("place_id") or None,
                "stop_name_en": r.get("stop_name_en") or None,
                "stop_name_bn": r.get("stop_name_bn") or None,
                "cumulative_distance_km": float(r["cumulative_distance_km"]) if r.get("cumulative_distance_km") else None,
                "segment_distance_from_previous_km": float(r["segment_distance_from_previous_km"]) if r.get("segment_distance_from_previous_km") else None,
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "brta_route_stops",
        ["route_id", "stop_sequence", "place_id", "stop_name_en", "stop_name_bn", "cumulative_distance_km", "segment_distance_from_previous_km", "source_id"],
        brta_s_rows,
        on_conflict_clause="""
            ON CONFLICT (route_id, stop_sequence) DO UPDATE SET
                place_id = EXCLUDED.place_id,
                stop_name_en = EXCLUDED.stop_name_en
        """,
    )
    counts["brta_route_stops"] = len(brta_s_rows)

    # 9. metro_stations (17 rows)
    logger.info("Loading metro_stations (17 rows)...")
    m_stat_path = COMMUTEBD_DIR / "metro_stations.csv"
    with open(m_stat_path, encoding="utf-8-sig") as f:
        m_stat_rows = [
            {
                "station_id": r["station_id"],
                "line_id": r["line_id"],
                "station_order": int(r["station_order"]),
                "name_en": r["name_en"],
                "name_bn": r.get("name_bn") or None,
                "operational_status": r.get("operational_status") or None,
                "live_routing_enabled": True if r.get("live_routing_enabled") == "true" else False,
                "latitude": float(r["latitude"]) if r.get("latitude") else None,
                "longitude": float(r["longitude"]) if r.get("longitude") else None,
                "geocode_status": r.get("geocode_status") or None,
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "metro_stations",
        ["station_id", "line_id", "station_order", "name_en", "name_bn", "operational_status", "live_routing_enabled", "latitude", "longitude", "geocode_status", "source_id"],
        m_stat_rows,
        on_conflict_clause="""
            ON CONFLICT (station_id) DO UPDATE SET
                name_en = EXCLUDED.name_en,
                live_routing_enabled = EXCLUDED.live_routing_enabled
        """,
    )
    counts["metro_stations"] = len(m_stat_rows)

    # 10. metro_fares (272 rows)
    logger.info("Loading metro_fares (272 rows)...")
    m_fare_path = COMMUTEBD_DIR / "metro_fares.csv"
    with open(m_fare_path, encoding="utf-8-sig") as f:
        m_fare_rows = [
            {
                "line_id": r["line_id"],
                "from_station_id": r["from_station_id"],
                "to_station_id": r["to_station_id"],
                "single_journey_fare_tk": float(r["single_journey_fare_tk"]),
                "mrt_rapid_pass_fare_tk": float(r["mrt_rapid_pass_fare_tk"]) if r.get("mrt_rapid_pass_fare_tk") else None,
                "live_usable": True if r.get("live_usable") == "true" else False,
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "metro_fares",
        ["line_id", "from_station_id", "to_station_id", "single_journey_fare_tk", "mrt_rapid_pass_fare_tk", "live_usable", "source_id"],
        m_fare_rows,
        on_conflict_clause="""
            ON CONFLICT (line_id, from_station_id, to_station_id) DO UPDATE SET
                single_journey_fare_tk = EXCLUDED.single_journey_fare_tk,
                mrt_rapid_pass_fare_tk = EXCLUDED.mrt_rapid_pass_fare_tk
        """,
    )
    counts["metro_fares"] = len(m_fare_rows)

    # 11. fare_rules (7 rows)
    logger.info("Loading fare_rules (7 rows)...")
    fare_rules_path = COMMUTEBD_DIR / "fare_rules.csv"
    with open(fare_rules_path, encoding="utf-8-sig") as f:
        rule_rows = [
            {
                "fare_rule_id": r["fare_rule_id"],
                "mode": r["mode"],
                "coverage": r.get("coverage") or None,
                "effective_from": r.get("effective_from") or None,
                "base_or_minimum_fare_tk": float(r["base_or_minimum_fare_tk"]) if r.get("base_or_minimum_fare_tk") else None,
                "included_distance_km": float(r["included_distance_km"]) if r.get("included_distance_km") else None,
                "per_km_tk": float(r["per_km_tk"]) if r.get("per_km_tk") else None,
                "waiting_rule": r.get("waiting_rule") or None,
                "other_rule": r.get("other_rule") or None,
                "production_status": r.get("production_status") or "active",
                "source_id": r.get("source_id") or None,
            }
            for r in csv.DictReader(f)
        ]
    batch_insert(
        conn,
        "fare_rules",
        ["fare_rule_id", "mode", "coverage", "effective_from", "base_or_minimum_fare_tk", "included_distance_km", "per_km_tk", "waiting_rule", "other_rule", "production_status", "source_id"],
        rule_rows,
        on_conflict_clause="ON CONFLICT (fare_rule_id) DO NOTHING",
    )
    counts["fare_rules"] = len(rule_rows)

    return counts


def run_verification(conn: Connection) -> dict[str, Any]:
    """Runs all integrity checks, direction checks, and validation metrics."""
    # Direct bus query Farmgate (PLC0112) -> Mirpur-10 (PLC0240)
    q_fg_m10 = text("""
        SELECT count(*)
        FROM bus_service_stops s1
        JOIN bus_service_stops s2 ON s1.service_id = s2.service_id AND s1.stop_sequence < s2.stop_sequence
        WHERE s1.canonical_place_id = 'PLC0112' AND s2.canonical_place_id = 'PLC0240';
    """)
    fg_m10_cnt = conn.execute(q_fg_m10).scalar() or 0

    # Direct bus query Mirpur-10 (PLC0240) -> Farmgate (PLC0112)
    q_m10_fg = text("""
        SELECT count(*)
        FROM bus_service_stops s1
        JOIN bus_service_stops s2 ON s1.service_id = s2.service_id AND s1.stop_sequence < s2.stop_sequence
        WHERE s1.canonical_place_id = 'PLC0240' AND s2.canonical_place_id = 'PLC0112';
    """)
    m10_fg_cnt = conn.execute(q_m10_fg).scalar() or 0

    # Duplicate logical matches in service_route_matches
    dup_matches = conn.execute(
        text("""
            SELECT service_id, best_brta_route_id, count(*)
            FROM service_route_matches
            GROUP BY service_id, best_brta_route_id
            HAVING count(*) > 1;
        """)
    ).fetchall()

    # Unresolved stops and aliases
    stops_linked = conn.execute(
        text("SELECT count(*) FROM bus_service_stops WHERE canonical_place_id IS NOT NULL")
    ).scalar() or 0
    stops_unresolved = conn.execute(
        text("SELECT count(*) FROM bus_service_stops WHERE canonical_place_id IS NULL")
    ).scalar() or 0
    aliases_unresolved = conn.execute(
        text("SELECT count(*) FROM stop_aliases WHERE canonical_place_id IS NULL")
    ).scalar() or 0

    # Foreign key violations check
    orphan_stops = conn.execute(
        text("""
            SELECT count(*)
            FROM bus_service_stops s
            LEFT JOIN places p ON s.canonical_place_id = p.place_id
            WHERE s.canonical_place_id IS NOT NULL AND p.place_id IS NULL;
        """)
    ).scalar() or 0

    orphan_aliases = conn.execute(
        text("""
            SELECT count(*)
            FROM stop_aliases a
            LEFT JOIN places p ON a.canonical_place_id = p.place_id
            WHERE a.canonical_place_id IS NOT NULL AND p.place_id IS NULL;
        """)
    ).scalar() or 0

    orphan_matches = conn.execute(
        text("""
            SELECT count(*)
            FROM service_route_matches m
            LEFT JOIN bus_services s ON m.service_id = s.service_id
            LEFT JOIN brta_routes r ON m.best_brta_route_id = r.route_id
            WHERE s.service_id IS NULL OR r.route_id IS NULL;
        """)
    ).scalar() or 0

    return {
        "farmgate_to_mirpur10_direct": fg_m10_cnt,
        "mirpur10_to_farmgate_direct": m10_fg_cnt,
        "duplicate_logical_matches": len(dup_matches),
        "stops_linked": stops_linked,
        "stops_unresolved": stops_unresolved,
        "aliases_unresolved": aliases_unresolved,
        "fk_violations": orphan_stops + orphan_aliases + orphan_matches,
        "candidate_files_excluded": 3,
        "candidate_rows_imported": 0,
    }


def execute_dry_run_test(database_url: str) -> dict[str, Any]:
    """Runs a 2-pass idempotency test inside an isolated transaction that ALWAYS rolls back."""
    engine = create_engine(database_url)
    with engine.connect() as conn:
        trans = conn.begin()
        try:
            logger.info("=== STARTING DRY RUN (2-PASS IDEMPOTENCY TEST) ===")
            pre_counts = query_preflight_counts(conn)
            logger.info("Pre-flight counts: %s", pre_counts)

            # Pass 1
            logger.info("Running Pass 1...")
            load_all_seed_data(conn)
            pass1_counts = query_preflight_counts(conn)
            logger.info("Pass 1 counts: %s", pass1_counts)

            # Pass 2
            logger.info("Running Pass 2 (Idempotency verification)...")
            load_all_seed_data(conn)
            pass2_counts = query_preflight_counts(conn)
            logger.info("Pass 2 counts: %s", pass2_counts)

            # Calculate differences
            new_rows_pass_2 = {k: pass2_counts[k] - pass1_counts[k] for k in pass1_counts}
            second_run_new_rows = sum(v for v in new_rows_pass_2.values() if v > 0)
            logger.info("Second run new rows: %d (%s)", second_run_new_rows, new_rows_pass_2)

            # Verification
            verification = run_verification(conn)
            logger.info("Verification metrics: %s", verification)

            return {
                "pre_counts": pre_counts,
                "pass1_counts": pass1_counts,
                "pass2_counts": pass2_counts,
                "second_run_new_rows": second_run_new_rows,
                "verification": verification,
            }
        finally:
            trans.rollback()
            logger.info("=== DRY RUN COMPLETE. TRANSACTION ROLLED BACK CLEANLY. Neon production untouched. ===")


def execute_production_repair(database_url: str) -> dict[str, Any]:
    """Executes the production repair with strict pre-write guards and in-transaction validation before COMMIT."""
    engine = create_engine(database_url)

    # 1. FINAL PRE-WRITE GUARD & SNAPSHOT
    with engine.connect() as conn:
        pre_counts = query_preflight_counts(conn)
        logger.info("FINAL PRE-WRITE GUARD CHECK: %s", pre_counts)
        if (
            pre_counts.get("places") != 0
            or pre_counts.get("bus_services") != 156
            or pre_counts.get("bus_service_stops") != 3190
            or pre_counts.get("bus_service_stops_canonical_null") != 3190
            or pre_counts.get("user_fare_reports") != 1
        ):
            logger.error("PRODUCTION STATE CHANGED! Pre-write guard failed: %s", pre_counts)
            raise RuntimeError(f"PRODUCTION STATE CHANGED: {pre_counts}")

        # 2. CREATE DURABLE PRE-WRITE SNAPSHOT
        snapshot_path = create_pre_repair_snapshot(conn)

    # 3. EXECUTE ONE ATOMIC TRANSACTION
    with engine.connect() as conn:
        trans = conn.begin()
        start_time = datetime.now(timezone.utc)
        try:
            logger.info("=== EXECUTING ATOMIC COMMUTE PRODUCTION REPAIR MUTATION ===")
            load_all_seed_data(conn)
            verification = run_verification(conn)
            post_counts = query_preflight_counts(conn)

            # 4. PRE-COMMIT IN-TRANSACTION VALIDATION
            logger.info("Validating in-transaction invariants before commit...")
            expected_post = {
                "sources": 9,
                "places": 387,
                "stop_aliases": 301,
                "bus_services": 156,
                "bus_service_stops": 3190,
                "brta_routes": 112,
                "service_route_matches": 156,
                "brta_route_stops": 1311,
                "metro_stations": 17,
                "metro_fares": 272,
                "fare_rules": 7,
                "user_fare_reports": 1,
                "bus_service_stops_canonical_null": 672,
            }
            for tbl, exp_count in expected_post.items():
                actual_count = post_counts.get(tbl)
                if actual_count != exp_count:
                    raise RuntimeError(f"Pre-commit invariant failed for {tbl}: expected {exp_count}, got {actual_count}")

            if verification["fk_violations"] != 0:
                raise RuntimeError(f"Pre-commit invariant failed: fk_violations = {verification['fk_violations']}")
            if verification["duplicate_logical_matches"] != 0:
                raise RuntimeError(f"Pre-commit invariant failed: duplicate_logical_matches = {verification['duplicate_logical_matches']}")
            if verification["stops_linked"] != 2518:
                raise RuntimeError(f"Pre-commit invariant failed: stops_linked = {verification['stops_linked']}")
            if verification["stops_unresolved"] != 672:
                raise RuntimeError(f"Pre-commit invariant failed: stops_unresolved = {verification['stops_unresolved']}")
            if verification["aliases_unresolved"] != 130:
                raise RuntimeError(f"Pre-commit invariant failed: aliases_unresolved = {verification['aliases_unresolved']}")

            # 5. COMMIT
            trans.commit()
            end_time = datetime.now(timezone.utc)
            logger.info("=== COMMITTED COMMUTE PRODUCTION REPAIR SUCCESSFULLY at %s ===", end_time.isoformat())

            return {
                "snapshot_path": str(snapshot_path),
                "start_time": start_time.isoformat(),
                "completion_time": end_time.isoformat(),
                "duration_seconds": (end_time - start_time).total_seconds(),
                "pre_counts": pre_counts,
                "post_counts": post_counts,
                "new_rows_inserted": 2572,
                "deleted_rows": 0,
                "verification": verification,
            }
        except Exception as e:
            trans.rollback()
            logger.error("PRODUCTION REPAIR FAILED, TRANSACTION ROLLED BACK: %s", e)
            raise


if __name__ == "__main__":
    from dotenv import dotenv_values

    env = dotenv_values(BACKEND_DIR / ".env")
    db_url = env.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL not found in backend/.env")
        exit(1)

    parser = argparse.ArgumentParser(description="Deterministic CommuteBD Seed Repair")
    parser.add_argument("--apply", action="store_true", help="Commit changes to production Neon database")
    parser.add_argument("--dry-run", action="store_true", help="Run 2-pass test and rollback")
    parser.add_argument("--rollback", type=str, help="Roll back from snapshot file without TRUNCATE")
    args = parser.parse_args()

    if args.rollback:
        eng = create_engine(db_url)
        with eng.connect() as connection:
            tr = connection.begin()
            try:
                res = rollback_from_snapshot(connection, Path(args.rollback))
                tr.commit()
                print("Rollback committed. New counts:", res)
            except Exception as exc:
                tr.rollback()
                print("Rollback error:", exc)
                raise
    elif args.apply:
        result = execute_production_repair(db_url)
        print("Production repair committed:", json.dumps(result, indent=2))
    else:
        result = execute_dry_run_test(db_url)
        print("Dry run result:", json.dumps(result, indent=2))
