"""Builds the CommuteBD transport graph from the real datasets.

Where each kind of edge comes from
----------------------------------

  BUS (BRTA)      ``brta_graph_edges`` — 2,398 directed stop-adjacency rows
                  along real BRTA routes, each with a segment distance. Fares
                  come from ``brta_fare_segments`` (official, 15,606 stop
                  pairs) and fall back to the route's per-km rule.

  BUS (services)  ``bus_service_stops`` — consecutive stops on each of the 156
                  named services. These add connectivity the BRTA table does
                  not have, and carry the operator name so a journey can say
                  which bus to board.

  METRO           ``metro_stations`` ordered by ``station_order`` gives the
                  line; ``metro_fares`` gives the official station-pair fare.

  WALK            Generated between nodes that are close enough to walk
                  between. Needs coordinates, which is why the geocode asset
                  exists.

  RICKSHAW / CNG  Generated as first- and last-mile connections from the
                  student's actual origin and destination to nearby network
                  nodes. Fares come from ``fare_rules``.

Nodes without coordinates are still useful: they can be ridden *through* on a
bus or metro edge. They simply cannot anchor a walking transfer or be snapped
to, because we do not know where they are.
"""
from __future__ import annotations

import csv
import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Iterable, Sequence

from app.services.commute.graph import (
    DEFAULT_POLICY,
    Edge,
    Mode,
    Node,
    RoutingPolicy,
    TransportGraph,
)

DERIVED = (
    Path(__file__).resolve().parent.parent.parent.parent
    / "data" / "commutebd" / "derived"
)

# --- Tunables specific to graph construction --------------------------------

# Two nodes closer than this are considered walkable between. 700 m is about
# a 9-minute walk — far enough to connect a metro station to the bus stops
# around it, short enough not to invent implausible connections.
WALK_TRANSFER_KM = 0.7

# How far from the student's actual position we will look for a place to
# start the journey. Beyond this, hailing something is not "first mile".
FIRST_MILE_KM = 4.0

# How many nearby nodes to connect the origin/destination to. Connecting to
# everything within range would explode the search for no benefit; the
# nearest handful covers the realistic options.
FIRST_MILE_FANOUT = 6

# Bus fare fallback when the official segment table has no entry for a pair.
DEFAULT_BUS_PER_KM_TK = 2.45
DEFAULT_BUS_MINIMUM_TK = 10.0

# Project rule from the CommuteBD master dataset's fare_rules_seed.csv.
# This is an estimation rule, not a claim that every operator charges it.
RICKSHAW_PER_KM_TK = 17.0
CNG_PER_KM_TK = 17.0
CNG_MINIMUM_TK = 60.0
RICKSHAW_MINIMUM_TK = 20.0

# Average speeds used to turn a distance into a duration for scheduled modes.
BUS_KMH = 16.0
METRO_KMH = 34.0


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371.0088
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    h = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))


# ---------------------------------------------------------------------------
# The rows the builder needs. Keeping this as a plain dataclass means the
# builder can be driven from PostgreSQL in production and from literals in
# tests, without either knowing about the other.
# ---------------------------------------------------------------------------


@dataclass
class GraphData:
    places: Sequence[dict]           # place_id, name_en
    brta_edges: Sequence[dict]       # from_place_id, to_place_id, segment_distance_km, route_id
    brta_fares: Sequence[dict]       # from_place_id, to_place_id, fare_tk
    service_stops: Sequence[dict]    # service_id, stop_sequence, canonical_place_id
    services: Sequence[dict]         # service_id, operator_name_en
    metro_stations: Sequence[dict]   # station_id, name_en, station_order, line_id
    metro_fares: Sequence[dict]      # from_station_id, to_station_id, single_journey_fare_tk
    coordinates: dict[str, tuple[float, float]]  # node_id -> (lat, lon)


@lru_cache(maxsize=1)
def load_coordinates() -> dict[str, tuple[float, float]]:
    """Coordinates derived from the OSM master dataset.

    Returns an empty mapping when the asset has not been generated — the
    router then runs network-only, which is degraded but correct.
    """
    path = DERIVED / "place_coordinates.csv"
    if not path.exists():
        return {}
    out: dict[str, tuple[float, float]] = {}
    with path.open(encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            try:
                out[row["node_id"]] = (float(row["latitude"]), float(row["longitude"]))
            except (TypeError, ValueError, KeyError):
                continue
    return out


def _num(value, default: float = 0.0) -> float:
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def place_node_id(place_id: str) -> str:
    return f"place:{place_id}"


def metro_node_id(station_id: str) -> str:
    return f"metro:{station_id}"


class GraphBuilder:
    """Assembles a `TransportGraph` from dataset rows."""

    def __init__(self, policy: RoutingPolicy | None = None) -> None:
        self.policy = policy or DEFAULT_POLICY

    def build(self, data: GraphData) -> TransportGraph:
        graph = TransportGraph(policy=self.policy)

        self._add_place_nodes(graph, data)
        self._add_metro_nodes(graph, data)
        self._add_brta_bus_edges(graph, data)
        self._add_service_bus_edges(graph, data)
        self._add_metro_edges(graph, data)
        self._add_walk_transfers(graph)

        return graph

    # --- nodes ------------------------------------------------------------

    def _add_place_nodes(self, graph: TransportGraph, data: GraphData) -> None:
        for place in data.places:
            place_id = str(place.get("place_id") or "").strip()
            name = str(place.get("name_en") or "").strip()
            if not place_id or not name:
                # A place we cannot name cannot be shown as a journey step.
                continue
            lat_lon = data.coordinates.get(place_id)
            graph.add_node(
                Node(
                    node_id=place_node_id(place_id),
                    name=name,
                    kind="bus_stop",
                    lat=lat_lon[0] if lat_lon else None,
                    lon=lat_lon[1] if lat_lon else None,
                )
            )

    def _add_metro_nodes(self, graph: TransportGraph, data: GraphData) -> None:
        for station in data.metro_stations:
            station_id = str(station.get("station_id") or "").strip()
            name = str(station.get("name_en") or "").strip()
            if not station_id or not name:
                continue
            lat_lon = data.coordinates.get(station_id)
            graph.add_node(
                Node(
                    node_id=metro_node_id(station_id),
                    # Spec §22: name the service, not just the mode.
                    name=f"{name} Metro Station",
                    kind="metro_station",
                    lat=lat_lon[0] if lat_lon else None,
                    lon=lat_lon[1] if lat_lon else None,
                )
            )

    # --- bus --------------------------------------------------------------

    def _official_bus_fares(self, data: GraphData) -> dict[tuple[str, str], float]:
        fares: dict[tuple[str, str], float] = {}
        for row in data.brta_fares:
            a = str(row.get("from_place_id") or "").strip()
            b = str(row.get("to_place_id") or "").strip()
            fare = _num(row.get("fare_tk"))
            if a and b and fare > 0:
                # Keep the cheapest official fare when routes overlap.
                key = (a, b)
                if key not in fares or fare < fares[key]:
                    fares[key] = fare
        return fares

    def _bus_fare_for(
        self,
        official: dict[tuple[str, str], float],
        a: str,
        b: str,
        distance_km: float,
    ) -> tuple[float, str, str, str]:
        """Returns (fare, fare_type, source, confidence)."""
        fare = official.get((a, b)) or official.get((b, a))
        if fare:
            return fare, "official", "BRTA fare segment table", "Authoritative"
        # Deterministic per-km rule with the regulated minimum.
        computed = max(DEFAULT_BUS_MINIMUM_TK, distance_km * DEFAULT_BUS_PER_KM_TK)
        return (
            round(computed),
            "calculated",
            f"BRTA per-km rule ({DEFAULT_BUS_PER_KM_TK} Tk/km, min {DEFAULT_BUS_MINIMUM_TK:.0f} Tk)",
            "Medium",
        )

    def _add_brta_bus_edges(self, graph: TransportGraph, data: GraphData) -> None:
        official = self._official_bus_fares(data)
        for row in data.brta_edges:
            a = str(row.get("from_place_id") or "").strip()
            b = str(row.get("to_place_id") or "").strip()
            if not a or not b or a == b:
                continue
            from_id, to_id = place_node_id(a), place_node_id(b)
            if from_id not in graph.nodes or to_id not in graph.nodes:
                continue

            distance = _num(row.get("segment_distance_km")) or _num(row.get("distance_km"))
            if distance <= 0:
                distance = self._distance_between(graph, from_id, to_id) or 1.0

            fare, fare_type, source, confidence = self._bus_fare_for(
                official, a, b, distance
            )
            graph.add_edge(
                Edge(
                    from_node=from_id,
                    to_node=to_id,
                    mode=Mode.BUS,
                    distance_km=distance,
                    minutes=max(1.0, distance / BUS_KMH * 60),
                    fare_tk=fare,
                    fare_type=fare_type,
                    fare_source=source,
                    fare_confidence=confidence,
                    route_id=str(row.get("route_id") or "") or None,
                )
            )

    def _add_service_bus_edges(self, graph: TransportGraph, data: GraphData) -> None:
        names = {
            str(s.get("service_id")): str(s.get("operator_name_en") or "").strip()
            for s in data.services
        }
        sequences: dict[str, list[tuple[int, str]]] = {}
        for row in data.service_stops:
            place_id = str(row.get("canonical_place_id") or "").strip()
            service_id = str(row.get("service_id") or "").strip()
            if not place_id or not service_id:
                continue
            try:
                order = int(row.get("stop_sequence"))
            except (TypeError, ValueError):
                continue
            sequences.setdefault(service_id, []).append((order, place_id))

        official = self._official_bus_fares(data)

        for service_id, stops in sequences.items():
            stops.sort()
            operator = names.get(service_id, "")
            for (_, a), (_, b) in zip(stops, stops[1:]):
                if a == b:
                    continue
                from_id, to_id = place_node_id(a), place_node_id(b)
                if from_id not in graph.nodes or to_id not in graph.nodes:
                    continue

                distance = self._distance_between(graph, from_id, to_id)
                if distance is None:
                    # No coordinates for either end: assume a typical
                    # inter-stop hop rather than dropping real connectivity.
                    distance = 1.5
                if distance <= 0:
                    continue

                fare, fare_type, source, confidence = self._bus_fare_for(
                    official, a, b, distance
                )
                graph.add_edge(
                    Edge(
                        from_node=from_id,
                        to_node=to_id,
                        mode=Mode.BUS,
                        distance_km=distance,
                        minutes=max(1.0, distance / BUS_KMH * 60),
                        fare_tk=fare,
                        fare_type=fare_type,
                        fare_source=source,
                        fare_confidence=confidence,
                        service_id=service_id,
                        service_name=operator or None,
                    )
                )

    # --- metro ------------------------------------------------------------

    def _add_metro_edges(self, graph: TransportGraph, data: GraphData) -> None:
        """Metro edges are station *pairs*, not consecutive hops.

        This distinction is not cosmetic. A metro fare table is
        origin-to-destination: Mirpur 10 to Farmgate is a single 30 Tk fare,
        not the sum of the four hops between them. Modelling the line as
        consecutive edges and letting Dijkstra add them up produced 100 Tk for
        that ride — more than three times the real fare — and would have made
        CHEAPEST avoid the metro for bad reasons.

        Building one edge per priced station pair fixes the fare *and* the
        journey shape: riding the metro is one instruction ("board here, get
        off there"), not a list of every station passed through. 17 stations
        give at most a few hundred edges, which costs nothing.
        """
        fares: dict[tuple[str, str], float] = {}
        for row in data.metro_fares:
            a = str(row.get("from_station_id") or "").strip()
            b = str(row.get("to_station_id") or "").strip()
            fare = _num(row.get("single_journey_fare_tk"))
            if a and b and a != b and fare > 0:
                fares[(a, b)] = fare
                # A metro fare is symmetric: the ride costs the same either
                # way. The shipped table happens to list all 272 ordered
                # pairs, but a table listing each pair once must still yield
                # a usable line in both directions.
                fares.setdefault((b, a), fare)

        # Station order per line, so distance and time can scale with how far
        # apart two stations are even when we lack coordinates for them.
        order: dict[str, int] = {}
        line_of: dict[str, str] = {}
        for station in data.metro_stations:
            station_id = str(station.get("station_id") or "").strip()
            if not station_id:
                continue
            try:
                order[station_id] = int(station.get("station_order"))
            except (TypeError, ValueError):
                continue
            line_of[station_id] = str(station.get("line_id") or "").strip()

        # Typical spacing between adjacent MRT-6 stations, used only when
        # coordinates are missing for one of the two stations.
        NOMINAL_STATION_GAP_KM = 1.1

        for (start, end), fare in fares.items():
            from_id, to_id = metro_node_id(start), metro_node_id(end)
            if from_id not in graph.nodes or to_id not in graph.nodes:
                continue
            if line_of.get(start) and line_of.get(start) != line_of.get(end):
                # No interchange data exists yet; a cross-line fare would be
                # a guess.
                continue

            distance = self._distance_between(graph, from_id, to_id)
            if distance is None:
                hops = abs(order.get(start, 0) - order.get(end, 0)) or 1
                distance = hops * NOMINAL_STATION_GAP_KM

            hops = abs(order.get(start, 0) - order.get(end, 0)) or 1
            # Dwell time at each intermediate station, on top of run time.
            minutes = max(1.0, distance / METRO_KMH * 60 + (hops - 1) * 0.5)

            graph.add_edge(
                Edge(
                    from_node=from_id,
                    to_node=to_id,
                    mode=Mode.METRO,
                    distance_km=distance,
                    minutes=minutes,
                    fare_tk=fare,
                    fare_type="official",
                    fare_source=f"Official {line_of.get(start) or 'metro'} fare table",
                    fare_confidence="Authoritative",
                    service_name=_metro_line_name(line_of.get(start, "")),
                    route_id=line_of.get(start) or None,
                )
            )

    # --- walking ----------------------------------------------------------

    def _add_walk_transfers(self, graph: TransportGraph) -> None:
        """Connect nodes that are close enough to walk between.

        This is what makes the graph genuinely multimodal: without it, a metro
        station and the bus stop 200 m away are separate islands and no
        journey can ever change between them.
        """
        located = [n for n in graph.nodes.values() if n.has_location]
        # Bucket by a coarse grid so this stays near-linear instead of
        # comparing every node against every other.
        cell = WALK_TRANSFER_KM / 111.0  # ~degrees for the walk radius
        buckets: dict[tuple[int, int], list[Node]] = {}
        for node in located:
            key = (int(node.lat / cell), int(node.lon / cell))
            buckets.setdefault(key, []).append(node)

        for node in located:
            key = (int(node.lat / cell), int(node.lon / cell))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for other in buckets.get((key[0] + dx, key[1] + dy), ()):
                        if other.node_id == node.node_id:
                            continue
                        distance = haversine_km(node.lat, node.lon, other.lat, other.lon)
                        if distance > WALK_TRANSFER_KM:
                            continue
                        graph.add_edge(
                            Edge(
                                from_node=node.node_id,
                                to_node=other.node_id,
                                mode=Mode.WALK,
                                distance_km=round(distance, 3),
                                minutes=max(1.0, distance / self.policy.walk_kmh * 60),
                                fare_tk=0.0,
                                fare_type="none",
                                fare_source="Walking",
                                fare_confidence="High",
                            )
                        )

    # --- helpers ----------------------------------------------------------

    @staticmethod
    def _distance_between(graph: TransportGraph, a: str, b: str) -> float | None:
        node_a, node_b = graph.nodes.get(a), graph.nodes.get(b)
        if not node_a or not node_b or not node_a.has_location or not node_b.has_location:
            return None
        return round(haversine_km(node_a.lat, node_a.lon, node_b.lat, node_b.lon), 3)


# ---------------------------------------------------------------------------
# First and last mile
# ---------------------------------------------------------------------------


def hired_fare(mode: Mode, distance_km: float) -> tuple[float, str, str, str]:
    """Fare for a hired vehicle. Returns (fare, type, source, confidence)."""
    if mode is Mode.RICKSHAW:
        fare = max(RICKSHAW_MINIMUM_TK, distance_km * RICKSHAW_PER_KM_TK)
        source = f"Project baseline ({RICKSHAW_PER_KM_TK:.0f} Tk/km)"
    else:
        fare = max(CNG_MINIMUM_TK, distance_km * CNG_PER_KM_TK)
        source = f"Project baseline ({CNG_PER_KM_TK:.0f} Tk/km)"
    # Round to the nearest 5 Tk — nobody negotiates in single taka.
    return round(fare / 5) * 5, "estimated", source, "Low"


def attach_endpoint(
    graph: TransportGraph,
    *,
    node_id: str,
    name: str,
    lat: float,
    lon: float,
    is_origin: bool,
    max_km: float = FIRST_MILE_KM,
    fanout: int = FIRST_MILE_FANOUT,
) -> int:
    """Add the student's origin or destination and connect it to the network.

    Spec §5/§41: the student's actual position is almost never a transport
    node, so a journey has to start with a first-mile connection — walk for
    something close, rickshaw or CNG for something further. Returns the number
    of connections made; 0 means the point is not reachable from the network.
    """
    graph.add_node(Node(node_id=node_id, name=name, kind="endpoint", lat=lat, lon=lon))

    candidates: list[tuple[float, Node]] = []
    for node in graph.nodes.values():
        if node.node_id == node_id or not node.has_location:
            continue
        distance = haversine_km(lat, lon, node.lat, node.lon)
        if distance <= max_km:
            candidates.append((distance, node))
    candidates.sort(key=lambda pair: pair[0])

    made = 0
    for distance, node in candidates[:fanout]:
        for mode in _endpoint_modes(distance):
            if mode is Mode.WALK:
                fare, fare_type, source, confidence = 0.0, "none", "Walking", "High"
            else:
                fare, fare_type, source, confidence = hired_fare(mode, distance)

            speed = graph.policy.speed_kmh(mode)
            edge = Edge(
                from_node=node_id if is_origin else node.node_id,
                to_node=node.node_id if is_origin else node_id,
                mode=mode,
                distance_km=round(distance, 3),
                minutes=max(1.0, distance / speed * 60),
                fare_tk=fare,
                fare_type=fare_type,
                fare_source=source,
                fare_confidence=confidence,
            )
            graph.add_edge(edge)
            made += 1
    return made


def _endpoint_modes(distance_km: float) -> Iterable[Mode]:
    """Which first/last-mile modes are plausible for this distance."""
    if distance_km <= 1.2:
        yield Mode.WALK
    if 0.4 <= distance_km <= 4.0:
        yield Mode.RICKSHAW
    if distance_km >= 1.5:
        yield Mode.CNG


def _metro_line_name(line_id: str) -> str:
    """Human-readable metro line name (spec §22)."""
    normalised = (line_id or "").upper().replace("_", "").replace("-", "")
    if normalised.startswith("MRT"):
        suffix = normalised[3:].lstrip("0") or normalised[3:]
        if suffix:
            return f"MRT Line {suffix}"
    return line_id or "Metro"
