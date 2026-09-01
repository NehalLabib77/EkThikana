"""The CommuteBD multimodal transport graph and its shortest-path search.

This module is deliberately pure: it knows nothing about SQL, HTTP or the
Gochano data model. It takes nodes and edges, and answers "what is the best
way from A to B under this objective". That makes the routing logic testable
without a database, which is the only way the route quality can actually be
pinned by tests.

Design notes
------------

**State is (node, mode), not just node.** A plain node-keyed Dijkstra cannot
express "staying on the bus is free but changing to the metro costs a
transfer", because the cost of arriving somewhere depends on what you arrived
on. The search therefore expands over ``(node_id, arrival_mode)`` pairs and
charges the transfer penalty when the mode changes. This is what makes the
result a *journey* rather than a path.

**All weights are non-negative.** Dijkstra's correctness depends on it, and
every component here — time, fare, penalties — is a cost, never a credit. The
builder asserts this rather than trusting callers.

**Three objectives, one graph.** FASTEST, CHEAPEST and RECOMMENDED are three
weight functions over the same edges, so they are genuinely comparable and a
route that wins on one can lose on another.
"""
from __future__ import annotations

import heapq
import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Iterable


class Mode(str, Enum):
    """A way of moving between two nodes.

    Only modes Gochano has real data or a real rule for are listed. Adding a
    member here without a fare rule and a source of edges would produce
    journeys the app cannot justify.
    """

    WALK = "walk"
    RICKSHAW = "rickshaw"
    CNG = "cng"
    BUS = "bus"
    METRO = "metro"
    TRAIN = "train"
    BOAT = "boat"

    @property
    def is_transit(self) -> bool:
        """Scheduled/shared services, where boarding costs waiting time."""
        return self in {Mode.BUS, Mode.METRO, Mode.TRAIN, Mode.BOAT}

    @property
    def is_hired(self) -> bool:
        """Door-to-door hired vehicles — no fixed stops, no waiting queue."""
        return self in {Mode.RICKSHAW, Mode.CNG}


class Objective(str, Enum):
    FASTEST = "fastest"
    CHEAPEST = "cheapest"
    RECOMMENDED = "recommended"


@dataclass(frozen=True)
class Node:
    """A place a journey can pass through.

    ``node_id`` is internal and never shown to a student. ``name`` is the
    human-readable label the UI displays, and is required — a node without a
    name cannot be rendered as a journey step, so the builder refuses one.
    """

    node_id: str
    name: str
    kind: str = "place"
    lat: float | None = None
    lon: float | None = None

    @property
    def has_location(self) -> bool:
        return self.lat is not None and self.lon is not None


@dataclass(frozen=True)
class Edge:
    """One movement between two nodes by one mode."""

    from_node: str
    to_node: str
    mode: Mode
    distance_km: float
    minutes: float
    fare_tk: float
    fare_type: str = "estimated"
    fare_source: str = ""
    fare_confidence: str = "Low"
    service_id: str | None = None
    service_name: str | None = None
    route_id: str | None = None

    def __post_init__(self) -> None:
        # Dijkstra requires non-negative weights, and every component below
        # feeds a weight. Catch a bad edge at build time rather than letting
        # it silently corrupt a route.
        if self.minutes < 0:
            raise ValueError(f"negative minutes on {self.from_node}->{self.to_node}")
        if self.fare_tk < 0:
            raise ValueError(f"negative fare on {self.from_node}->{self.to_node}")
        if self.distance_km < 0:
            raise ValueError(f"negative distance on {self.from_node}->{self.to_node}")


# ---------------------------------------------------------------------------
# Routing policy — every tunable number in one place.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RoutingPolicy:
    """The weights and limits that shape route selection.

    Spec §9/§43: "Do not hard-code arbitrary unexplained numbers. Keep weights
    centralized/configurable." Each value below is stated with why it has the
    magnitude it has. They are travel-behaviour assumptions, not measurements,
    and the README says so.
    """

    # --- Speeds, for turning a distance into a duration -------------------
    walk_kmh: float = 4.5
    rickshaw_kmh: float = 10.0
    cng_kmh: float = 18.0

    # --- Waiting, charged once when boarding a shared service -------------
    # A student does not wait for a rickshaw the way they wait for a bus.
    wait_minutes: dict[Mode, float] = field(
        default_factory=lambda: {
            Mode.BUS: 8.0,
            Mode.METRO: 4.0,
            Mode.TRAIN: 15.0,
            Mode.BOAT: 20.0,
            Mode.RICKSHAW: 2.0,
            Mode.CNG: 3.0,
            Mode.WALK: 0.0,
        }
    )

    # --- Transfer -----------------------------------------------------------
    # Time actually spent changing service, on top of any walk edge.
    transfer_minutes: float = 3.0
    # Extra *perceived* cost of a transfer in the RECOMMENDED objective,
    # expressed in equivalent minutes. Travel-behaviour research consistently
    # finds a transfer feels worse than the clock time it costs; this is what
    # stops the planner proposing five changes to save a few taka.
    transfer_penalty_minutes: float = 10.0

    # --- Walking ------------------------------------------------------------
    # Walking feels longer than riding for the same minute.
    walk_discomfort_multiplier: float = 1.6
    # A single walking leg longer than this is rejected as impractical.
    max_walk_leg_km: float = 1.5
    # Total walking across a whole journey.
    max_total_walk_km: float = 2.5

    # --- Money vs time ------------------------------------------------------
    # How many taka a student would pay to save one minute. This is the one
    # number that decides RECOMMENDED's character. ~1.5 Tk/min is deliberately
    # low: for a student on an allowance, money matters more than for a
    # commuter on a salary, so RECOMMENDED leans toward cheaper journeys.
    taka_per_minute: float = 1.5

    # --- Practicality guards -----------------------------------------------
    # A hired vehicle for less than this is not worth hailing.
    min_hired_leg_km: float = 0.4
    # Hard cap on legs, to stop pathological chains.
    max_legs: int = 8

    def speed_kmh(self, mode: Mode) -> float:
        return {
            Mode.WALK: self.walk_kmh,
            Mode.RICKSHAW: self.rickshaw_kmh,
            Mode.CNG: self.cng_kmh,
        }.get(mode, 20.0)

    def waiting_for(self, mode: Mode) -> float:
        return self.wait_minutes.get(mode, 0.0)


DEFAULT_POLICY = RoutingPolicy()


# ---------------------------------------------------------------------------
# Weight functions
# ---------------------------------------------------------------------------

# A weight function scores one edge, given whether boarding it is a transfer.
WeightFn = Callable[[Edge, bool, RoutingPolicy], float]


def _boarding_minutes(edge: Edge, is_transfer: bool, policy: RoutingPolicy) -> float:
    """Waiting + transfer time incurred by starting this edge."""
    cost = policy.waiting_for(edge.mode)
    if is_transfer:
        cost += policy.transfer_minutes
    return cost


def weight_fastest(edge: Edge, is_transfer: bool, policy: RoutingPolicy) -> float:
    """Total elapsed minutes: in-vehicle + waiting + transfer.

    Spec §11: a faster train with a 25-minute wait is not actually faster.
    """
    return edge.minutes + _boarding_minutes(edge, is_transfer, policy)


def weight_cheapest(edge: Edge, is_transfer: bool, policy: RoutingPolicy) -> float:
    """Payable fare only. Walking is free.

    A pure-fare weight has a problem Dijkstra cannot see: hundreds of free
    walking edges all cost 0, so the search would happily propose walking
    across the city to save a taka. A tiny per-minute tiebreak keeps the
    result the *cheapest sensible* journey rather than the cheapest technically
    valid one, and the walk-distance guard rejects the rest.
    """
    tiebreak = 0.001 * (edge.minutes + _boarding_minutes(edge, is_transfer, policy))
    return edge.fare_tk + tiebreak


def weight_recommended(edge: Edge, is_transfer: bool, policy: RoutingPolicy) -> float:
    """Generalised cost in taka-equivalent units.

        fare
      + time            × taka_per_minute
      + walking time    × extra discomfort
      + transfer        × perceived penalty

    Everything is converted into taka so the objective is a single
    interpretable quantity rather than an opaque score.
    """
    minutes = edge.minutes + _boarding_minutes(edge, is_transfer, policy)
    if edge.mode is Mode.WALK:
        minutes *= policy.walk_discomfort_multiplier

    cost = edge.fare_tk + minutes * policy.taka_per_minute
    if is_transfer:
        cost += policy.transfer_penalty_minutes * policy.taka_per_minute
    return cost


WEIGHTS: dict[Objective, WeightFn] = {
    Objective.FASTEST: weight_fastest,
    Objective.CHEAPEST: weight_cheapest,
    Objective.RECOMMENDED: weight_recommended,
}


# ---------------------------------------------------------------------------
# Graph
# ---------------------------------------------------------------------------


class TransportGraph:
    """Nodes plus outgoing edges, with the search over them."""

    def __init__(self, policy: RoutingPolicy | None = None) -> None:
        self.policy = policy or DEFAULT_POLICY
        self.nodes: dict[str, Node] = {}
        self._out: dict[str, list[Edge]] = {}

    # --- building ---------------------------------------------------------

    def add_node(self, node: Node) -> None:
        if not node.name or not node.name.strip():
            # Spec §1/§2: a route step must be nameable. A node with no name
            # could only ever be rendered as an internal id.
            raise ValueError(f"node {node.node_id} has no display name")
        self.nodes[node.node_id] = node
        self._out.setdefault(node.node_id, [])

    def add_edge(self, edge: Edge) -> None:
        if edge.from_node not in self.nodes or edge.to_node not in self.nodes:
            raise KeyError(
                f"edge {edge.from_node}->{edge.to_node} references an unknown node"
            )
        self._out.setdefault(edge.from_node, []).append(edge)

    def edges_from(self, node_id: str) -> list[Edge]:
        return self._out.get(node_id, [])

    @property
    def edge_count(self) -> int:
        return sum(len(v) for v in self._out.values())

    def __len__(self) -> int:
        return len(self.nodes)

    # --- search -----------------------------------------------------------

    def find_route(
        self,
        origin: str,
        destination: str,
        objective: Objective = Objective.RECOMMENDED,
        *,
        banned_edges: frozenset[tuple[str, str, Mode]] | None = None,
    ) -> "RoutePath | None":
        """Dijkstra over ``(node, arrival_mode)`` states.

        Returns None when the destination is unreachable, or when every path
        to it violates a practicality guard.

        ``banned_edges`` lets a caller re-run the search with specific edges
        removed, which is how alternative routes are generated without
        inventing them.
        """
        if origin not in self.nodes or destination not in self.nodes:
            return None
        if origin == destination:
            return None

        weight = WEIGHTS[objective]
        policy = self.policy
        banned = banned_edges or frozenset()

        # State: (node_id, arrival_mode or None at the origin).
        start: tuple[str, Mode | None] = (origin, None)
        best: dict[tuple[str, Mode | None], float] = {start: 0.0}
        # How we got to each state, for reconstruction.
        came: dict[tuple[str, Mode | None], tuple[tuple[str, Mode | None], Edge]] = {}
        # Journey-level accumulators, carried per state so the guards can see
        # the whole journey rather than one edge.
        walk_km: dict[tuple[str, Mode | None], float] = {start: 0.0}
        legs: dict[tuple[str, Mode | None], int] = {start: 0}

        # Counter keeps the heap total-ordered without comparing states.
        counter = 0
        queue: list[tuple[float, int, tuple[str, Mode | None]]] = [(0.0, 0, start)]
        settled: set[tuple[str, Mode | None]] = set()

        while queue:
            cost, _, state = heapq.heappop(queue)
            if state in settled:
                continue
            settled.add(state)

            node_id, arrived_by = state
            if node_id == destination:
                return self._reconstruct(state, came, objective, cost)

            if legs[state] >= policy.max_legs:
                continue

            for edge in self.edges_from(node_id):
                if (edge.from_node, edge.to_node, edge.mode) in banned:
                    continue

                # --- practicality guards (spec §15) -----------------------
                if edge.mode is Mode.WALK and edge.distance_km > policy.max_walk_leg_km:
                    continue
                if (
                    edge.mode.is_hired
                    and edge.distance_km < policy.min_hired_leg_km
                ):
                    # Hailing a rickshaw for 200 m then changing again.
                    continue

                next_walk = walk_km[state] + (
                    edge.distance_km if edge.mode is Mode.WALK else 0.0
                )
                if next_walk > policy.max_total_walk_km:
                    continue

                # A transfer is a change of mode, or a change of service
                # within the same mode (bus A to bus B is still a transfer).
                is_transfer = arrived_by is not None and edge.mode != arrived_by
                next_state = (edge.to_node, edge.mode)
                next_cost = cost + weight(edge, is_transfer, policy)

                if next_cost < best.get(next_state, math.inf):
                    best[next_state] = next_cost
                    came[next_state] = (state, edge)
                    walk_km[next_state] = next_walk
                    legs[next_state] = legs[state] + 1
                    counter += 1
                    heapq.heappush(queue, (next_cost, counter, next_state))

        return None

    def _reconstruct(
        self,
        end_state: tuple[str, Mode | None],
        came: dict[tuple[str, Mode | None], tuple[tuple[str, Mode | None], Edge]],
        objective: Objective,
        cost: float,
    ) -> "RoutePath":
        edges: list[Edge] = []
        state = end_state
        while state in came:
            prev_state, edge = came[state]
            edges.append(edge)
            state = prev_state
        edges.reverse()
        return RoutePath(edges=edges, objective=objective, score=cost, graph=self)


@dataclass
class RoutePath:
    """A found journey, with the totals a student actually cares about."""

    edges: list[Edge]
    objective: Objective
    score: float
    graph: TransportGraph

    @property
    def total_fare(self) -> float:
        """Sum of payable legs. Walking contributes nothing (spec §25)."""
        return sum(e.fare_tk for e in self.edges)

    @property
    def total_distance_km(self) -> float:
        return sum(e.distance_km for e in self.edges)

    @property
    def total_walk_km(self) -> float:
        return sum(e.distance_km for e in self.edges if e.mode is Mode.WALK)

    @property
    def total_minutes(self) -> float:
        """In-vehicle + waiting + transfer time across the whole journey."""
        policy = self.graph.policy
        total = 0.0
        previous: Mode | None = None
        for edge in self.edges:
            is_transfer = previous is not None and edge.mode != previous
            total += edge.minutes + _boarding_minutes(edge, is_transfer, policy)
            previous = edge.mode
        return total

    @property
    def transfer_count(self) -> int:
        """Mode changes between consecutive legs."""
        changes = 0
        previous: Mode | None = None
        for edge in self.edges:
            if previous is not None and edge.mode != previous:
                changes += 1
            previous = edge.mode
        return changes

    @property
    def modes(self) -> list[Mode]:
        """The mode sequence, collapsing consecutive same-mode legs."""
        out: list[Mode] = []
        for edge in self.edges:
            if not out or out[-1] != edge.mode:
                out.append(edge.mode)
        return out

    @property
    def node_ids(self) -> list[str]:
        if not self.edges:
            return []
        return [self.edges[0].from_node] + [e.to_node for e in self.edges]

    def signature(self) -> tuple:
        """Identity used to detect that two objectives found the same journey.

        Spec §8: do not return three identical routes under different labels.
        """
        return tuple((e.from_node, e.to_node, e.mode) for e in self.edges)

    def uses_only(self, modes: Iterable[Mode]) -> bool:
        allowed = set(modes)
        return all(e.mode in allowed for e in self.edges)
