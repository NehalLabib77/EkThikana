"""Build the CommuteBD graph from the real dataset and plan real journeys.

Unit tests use hand-built fixtures, which prove the algorithm is correct but
not that the *shipped data* produces usable journeys. This script builds the
graph from the actual CSVs and plans a few real Dhaka trips, printing each as
a student would see it.

    python scripts/verify_commute_routing.py

It reads the CSV dataset directly rather than PostgreSQL, so it runs without
a database and reflects exactly what an import would load.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

# Journey text contains the taka sign; a Windows console defaults to cp1252.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from app.services.commute.graph_builder import (  # noqa: E402
    GraphBuilder,
    GraphData,
    attach_endpoint,
    load_coordinates,
)
from app.services.commute.journey import explain, plan_journeys  # noqa: E402

CORE = BACKEND / "data" / "commutebd" / "core_dataset" / "csv"


def read(name: str) -> list[dict]:
    path = CORE / name
    if not path.exists():
        return []
    with path.open(encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def load_dataset() -> GraphData:
    return GraphData(
        places=read("places.csv"),
        brta_edges=read("brta_graph_edges.csv"),
        brta_fares=read("brta_fare_segments.csv"),
        service_stops=read("bus_service_stops.csv"),
        services=read("bus_services.csv"),
        metro_stations=read("metro_stations.csv"),
        metro_fares=read("metro_fares.csv"),
        coordinates=load_coordinates(),
    )


# Real Dhaka origin/destination pairs, chosen to exercise different parts of
# the network. Coordinates are approximate street locations, not stop
# coordinates, so the first/last-mile logic has to do real work.
TRIPS = [
    ("Mirpur 10 area", 23.8069, 90.3687, "Farmgate", 23.7583, 90.3897),
    ("Uttara", 23.8690, 90.3985, "Motijheel", 23.7330, 90.4172),
    ("Mohammadpur", 23.7660, 90.3590, "Kamalapur", 23.7330, 90.4264),
]


def main() -> int:
    print("Loading the CommuteBD dataset ...")
    data = load_dataset()
    print(f"  places          {len(data.places)}")
    print(f"  BRTA edges      {len(data.brta_edges)}")
    print(f"  BRTA fares      {len(data.brta_fares)}")
    print(f"  service stops   {len(data.service_stops)}")
    print(f"  metro stations  {len(data.metro_stations)}")
    print(f"  metro fares     {len(data.metro_fares)}")
    print(f"  coordinates     {len(data.coordinates)}")

    if not data.places:
        print("\nDataset CSVs not found; nothing to verify.")
        return 1

    print("\nBuilding the graph ...")
    graph = GraphBuilder().build(data)
    located = sum(1 for n in graph.nodes.values() if n.has_location)
    walk_edges = sum(
        1
        for node in graph.nodes
        for e in graph.edges_from(node)
        if e.mode.value == "walk"
    )
    print(f"  nodes                 {len(graph)}")
    print(f"  edges                 {graph.edge_count}")
    print(f"  nodes with location   {located}")
    print(f"  walking transfers     {walk_edges}")

    planned = 0
    for origin_name, olat, olon, dest_name, dlat, dlon in TRIPS:
        print()
        print("=" * 68)
        print(f"{origin_name}  ->  {dest_name}")
        print("=" * 68)

        working = GraphBuilder().build(data)
        made_o = attach_endpoint(
            working, node_id="__origin__", name=origin_name,
            lat=olat, lon=olon, is_origin=True,
        )
        made_d = attach_endpoint(
            working, node_id="__destination__", name=dest_name,
            lat=dlat, lon=dlon, is_origin=False,
        )
        if not made_o or not made_d:
            missing = "origin" if not made_o else "destination"
            print(f"  no network connection near the {missing}")
            continue

        journeys = plan_journeys(working, "__origin__", "__destination__")
        if not journeys:
            print("  no complete route found")
            continue

        planned += 1
        for journey in journeys:
            labels = " / ".join(o.value.upper() for o in journey.objectives)
            print()
            print(f"  [{labels}]")
            print(
                f"  {int(round(journey.total_minutes))} min"
                f"   ~{journey.total_fare:.0f} Tk"
                f"   {journey.total_distance_km:.1f} km"
                f"   {journey.transfer_count} transfers"
            )
            print(f"  {' -> '.join(journey.mode_summary)}")
            reason = explain(journey, journeys)
            if reason:
                print(f"  {reason}")
            print()
            print(f"  * {journey.legs[0].from_name}")
            for leg in journey.legs:
                print(f"  |   {leg.instruction}")
                fare_text = "free" if leg.fare_tk == 0 else f"~{leg.fare_tk:.0f} Tk"
                print(
                    f"  |   {leg.distance_km:.1f} km"
                    f" - {int(round(leg.minutes))} min"
                    f" - {fare_text} ({leg.fare_type})"
                )
                print(f"  * {leg.to_name}")

    print()
    print("=" * 68)
    print(f"planned {planned}/{len(TRIPS)} trips")
    return 0 if planned else 1


if __name__ == "__main__":
    raise SystemExit(main())
