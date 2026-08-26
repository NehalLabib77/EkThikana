"""Import the supplied CommuteBD structured dataset into Supabase.

Prerequisites:
1. Run core_dataset/supabase_schema.sql
2. Run db/supabase_schema_ml_extension.sql
3. Run migrations/001_gochano_commutebd_production.sql
4. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.

The importer preserves source/status fields. It does not promote community
bus-service data to official status and does not import synthetic rickshaw
rows into fare-report/ML training tables.
"""
from __future__ import annotations

import csv
import math
import os
from pathlib import Path

from supabase import create_client

ROOT = Path(__file__).resolve().parents[1] / "data" / "commutebd" / "core_dataset" / "csv"

TABLES = [
    ("places", "places.csv", "place_id"),
    ("fare_rules", "fare_rules.csv", "fare_rule_id"),
    ("brta_routes", "brta_routes.csv", "route_id"),
    ("brta_route_stops", "brta_route_stops.csv", None),
    ("bus_services", "bus_services.csv", "service_id"),
    ("bus_service_stops", "bus_service_stops.csv", None),
    ("metro_stations", "metro_stations.csv", "station_id"),
    ("metro_fares", "metro_fares.csv", None),
]


def parse(value: str):
    raw = (value or "").strip()
    if raw == "":
        return None
    lower = raw.lower()
    if lower in {"yes", "true"}:
        return True
    if lower in {"no", "false"}:
        return False
    try:
        number = float(raw)
        if math.isfinite(number):
            return int(number) if number.is_integer() else number
    except Exception:
        pass
    return raw


def load(name: str) -> list[dict]:
    with (ROOT / name).open("r", encoding="utf-8-sig", newline="") as handle:
        return [{k: parse(v) for k, v in row.items()} for row in csv.DictReader(handle)]


def chunks(rows: list[dict], size: int = 500):
    for i in range(0, len(rows), size):
        yield rows[i : i + size]


def main():
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    client = create_client(url, key)

    for table, filename, conflict in TABLES:
        rows = load(filename)
        print(f"{table}: {len(rows)} rows")
        for batch in chunks(rows):
            query = client.table(table).upsert(batch, on_conflict=conflict) if conflict else client.table(table).upsert(batch)
            query.execute()
        print(f"  imported {table}")


if __name__ == "__main__":
    main()
