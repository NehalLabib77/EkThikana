"""Multimodal journey planning as a service.

Holds the built graph so the cost of assembling it is paid once per process
rather than once per request, and turns a pair of coordinates into
Recommended / Cheapest / Fastest journeys.

The graph is immutable once built, so the cached copy is shared safely. Each
request gets a *shallow working copy* with only its own origin and destination
attached — attaching endpoints to the shared graph would leak one student's
location into the next student's routing.
"""
from __future__ import annotations

import logging
import threading
from typing import Any

from app.services.commute.graph import Mode, Node, TransportGraph
from app.services.commute.graph_builder import (
    FIRST_MILE_KM,
    GraphBuilder,
    GraphData,
    attach_endpoint,
    haversine_km,
)
from app.services.commute.journey import compare_journeys, explain, plan_journeys

logger = logging.getLogger("gochano.commute.journey")

_lock = threading.Lock()
_cached_graph: TransportGraph | None = None
_cached_stats: dict[str, Any] | None = None


def build_graph(data: GraphData) -> TransportGraph:
    return GraphBuilder().build(data)


def get_graph(repo) -> TransportGraph | None:
    """The shared network graph, built on first use.

    Returns None when the dataset is unavailable — the caller then reports
    that routing is unavailable rather than inventing a journey.
    """
    global _cached_graph, _cached_stats
    if _cached_graph is not None:
        return _cached_graph

    with _lock:
        if _cached_graph is not None:
            return _cached_graph
        try:
            data = repo.load_graph_data()
        except Exception:
            logger.exception("Could not load the CommuteBD graph dataset")
            return None

        graph = build_graph(data)
        located = sum(1 for n in graph.nodes.values() if n.has_location)
        _cached_stats = {
            "nodes": len(graph),
            "edges": graph.edge_count,
            "nodesWithCoordinates": located,
        }
        logger.info(
            "CommuteBD graph built | nodes=%s edges=%s located=%s",
            len(graph), graph.edge_count, located,
        )
        _cached_graph = graph
        return _cached_graph


def reset_graph_cache() -> None:
    """Drop the cached graph. Used by tests and after a dataset reimport."""
    global _cached_graph, _cached_stats
    with _lock:
        _cached_graph = None
        _cached_stats = None


def graph_stats() -> dict[str, Any] | None:
    return dict(_cached_stats) if _cached_stats else None


def _working_copy(graph: TransportGraph) -> TransportGraph:
    """A copy that can take per-request endpoint edges.

    Nodes and edges are immutable frozen dataclasses, so they are shared by
    reference; only the adjacency lists are rebuilt. That keeps this cheap
    while making it impossible for one request to mutate another's graph.
    """
    copy = TransportGraph(policy=graph.policy)
    copy.nodes = dict(graph.nodes)
    copy._out = {node_id: list(edges) for node_id, edges in graph._out.items()}
    return copy


def plan(
    repo,
    *,
    origin_name: str,
    origin_lat: float,
    origin_lon: float,
    destination_name: str,
    destination_lat: float,
    destination_lon: float,
) -> dict[str, Any]:
    """Plan a complete multimodal journey.

    The return shape always tells the caller what happened:

      ``available`` false with a ``reason`` — routing could not run, and why.
      ``journeys`` empty                   — routing ran and found nothing.

    Those are different situations and the UI says different things about
    them (spec §30 vs §31).
    """
    graph = get_graph(repo)
    if graph is None or len(graph) == 0:
        return {
            "available": False,
            "reason": "dataset_unavailable",
            "journeys": [],
        }

    working = _working_copy(graph)

    origin_links = attach_endpoint(
        working,
        node_id="__origin__",
        name=origin_name or "Your location",
        lat=origin_lat,
        lon=origin_lon,
        is_origin=True,
    )
    destination_links = attach_endpoint(
        working,
        node_id="__destination__",
        name=destination_name or "Destination",
        lat=destination_lat,
        lon=destination_lon,
        is_origin=False,
    )

    if origin_links == 0 or destination_links == 0:
        # Spec §30: say which end is off-network instead of a generic failure.
        which = []
        if origin_links == 0:
            which.append("origin")
        if destination_links == 0:
            which.append("destination")
        return {
            "available": False,
            "reason": "outside_network_coverage",
            "outsideCoverage": which,
            "coverageRadiusKm": FIRST_MILE_KM,
            "journeys": [],
        }

    journeys = plan_journeys(working, "__origin__", "__destination__")
    if not journeys:
        return {"available": True, "reason": "no_route", "journeys": []}

    payloads = compare_journeys(journeys)
    reason = explain(journeys[0], journeys)
    if reason:
        payloads[0]["whyRecommended"] = reason

    return {
        "available": True,
        "reason": None,
        "journeys": payloads,
        "graph": graph_stats(),
    }


def direct_distance_km(
    origin_lat: float, origin_lon: float, destination_lat: float, destination_lon: float
) -> float:
    return haversine_km(origin_lat, origin_lon, destination_lat, destination_lon)


__all__ = [
    "build_graph",
    "get_graph",
    "graph_stats",
    "plan",
    "reset_graph_cache",
]
