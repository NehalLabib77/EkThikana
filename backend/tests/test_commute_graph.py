"""Tests for the CommuteBD multimodal routing engine.

These pin route *quality*, not just "a path was returned". The graph module
is pure, so every scenario below is a hand-built network whose right answer is
obvious by inspection — which is the only way to tell a correct planner from
one that merely returns something.

Scenario naming follows the spec §47 verification matrix.
"""
from __future__ import annotations

import pytest

from app.services.commute.graph import (
    DEFAULT_POLICY,
    Edge,
    Mode,
    Node,
    Objective,
    RoutingPolicy,
    TransportGraph,
)


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------


def graph_with(*nodes: tuple[str, str], policy: RoutingPolicy | None = None):
    g = TransportGraph(policy=policy)
    for node_id, name in nodes:
        g.add_node(Node(node_id=node_id, name=name))
    return g


def edge(
    a: str,
    b: str,
    mode: Mode,
    *,
    km: float = 1.0,
    minutes: float = 10.0,
    fare: float = 0.0,
    fare_type: str = "estimated",
    service: str | None = None,
) -> Edge:
    return Edge(
        from_node=a,
        to_node=b,
        mode=mode,
        distance_km=km,
        minutes=minutes,
        fare_tk=fare,
        fare_type=fare_type,
        service_name=service,
    )


# ---------------------------------------------------------------------------
# The algorithm itself
# ---------------------------------------------------------------------------


class TestDijkstra:
    def test_finds_the_only_path(self):
        g = graph_with(("home", "Home"), ("stop", "Bus Stop"), ("uni", "University"))
        g.add_edge(edge("home", "stop", Mode.WALK, km=0.5, minutes=7))
        g.add_edge(edge("stop", "uni", Mode.BUS, km=8, minutes=25, fare=30))

        route = g.find_route("home", "uni")
        assert route is not None
        assert [e.mode for e in route.edges] == [Mode.WALK, Mode.BUS]
        assert route.total_fare == 30
        assert route.total_distance_km == pytest.approx(8.5)

    def test_returns_none_when_unreachable(self):
        g = graph_with(("a", "A place"), ("b", "B place"))
        assert g.find_route("a", "b") is None

    def test_returns_none_for_unknown_nodes(self):
        g = graph_with(("a", "A place"))
        assert g.find_route("a", "nope") is None
        assert g.find_route("nope", "a") is None

    def test_origin_equals_destination_is_not_a_route(self):
        g = graph_with(("a", "A place"))
        assert g.find_route("a", "a") is None

    def test_prefers_the_genuinely_shorter_path_not_the_first_found(self):
        # Direct is slow; the two-hop detour is faster. A greedy or
        # breadth-first walk would take the direct edge.
        g = graph_with(("a", "A"), ("b", "B"), ("c", "C"))
        g.add_edge(edge("a", "c", Mode.BUS, km=10, minutes=90, fare=20))
        g.add_edge(edge("a", "b", Mode.BUS, km=5, minutes=10, fare=20))
        g.add_edge(edge("b", "c", Mode.BUS, km=5, minutes=10, fare=20))

        route = g.find_route("a", "c", Objective.FASTEST)
        assert route is not None
        assert route.node_ids == ["a", "b", "c"]

    def test_does_not_loop(self):
        # A cycle with a cheap edge back is a classic way to make a naive
        # search spin.
        g = graph_with(("a", "A"), ("b", "B"), ("c", "C"))
        g.add_edge(edge("a", "b", Mode.BUS, minutes=5, fare=10))
        g.add_edge(edge("b", "a", Mode.BUS, minutes=5, fare=10))
        g.add_edge(edge("b", "c", Mode.BUS, minutes=5, fare=10))

        route = g.find_route("a", "c")
        assert route is not None
        assert route.node_ids == ["a", "b", "c"]

    def test_rejects_negative_weights_at_build_time(self):
        with pytest.raises(ValueError):
            edge("a", "b", Mode.BUS, minutes=-1)
        with pytest.raises(ValueError):
            edge("a", "b", Mode.BUS, fare=-5)

    def test_a_node_must_be_nameable(self):
        # Spec §1: a journey step must never render as an internal id.
        g = TransportGraph()
        with pytest.raises(ValueError):
            g.add_node(Node(node_id="node_123", name=""))

    def test_edge_to_unknown_node_is_rejected(self):
        g = graph_with(("a", "A"))
        with pytest.raises(KeyError):
            g.add_edge(edge("a", "ghost", Mode.WALK))


# ---------------------------------------------------------------------------
# The three objectives genuinely differ
# ---------------------------------------------------------------------------


class TestObjectives:
    @staticmethod
    def three_way_graph() -> TransportGraph:
        """Home → University by three routes with a real trade-off.

          walk+bus : slow, cheap
          metro    : middling
          cng      : fast, expensive
        """
        g = graph_with(
            ("home", "Home"),
            ("busstop", "Farmgate Bus Stop"),
            ("metro", "Farmgate Metro Station"),
            ("uni", "University"),
        )
        # Cheap and slow.
        g.add_edge(edge("home", "busstop", Mode.WALK, km=0.6, minutes=8))
        g.add_edge(edge("busstop", "uni", Mode.BUS, km=12, minutes=55, fare=30))
        # Middle.
        g.add_edge(edge("home", "metro", Mode.WALK, km=0.4, minutes=5))
        g.add_edge(edge("metro", "uni", Mode.METRO, km=11, minutes=20, fare=60))
        # Fast and expensive.
        g.add_edge(edge("home", "uni", Mode.CNG, km=13, minutes=28, fare=250))
        return g

    def test_cheapest_is_actually_the_cheapest(self):
        g = self.three_way_graph()
        route = g.find_route("home", "uni", Objective.CHEAPEST)
        assert route is not None
        assert route.total_fare == 30
        assert Mode.BUS in route.modes

    def test_fastest_is_actually_the_fastest(self):
        g = self.three_way_graph()
        route = g.find_route("home", "uni", Objective.FASTEST)
        assert route is not None
        # CNG: 28 min + 3 wait = 31. Metro: 5 + 20 + 4 wait + transfer = ~32.
        assert route.modes == [Mode.CNG]

    def test_recommended_balances_rather_than_picking_an_extreme(self):
        g = self.three_way_graph()
        recommended = g.find_route("home", "uni", Objective.RECOMMENDED)
        cheapest = g.find_route("home", "uni", Objective.CHEAPEST)
        fastest = g.find_route("home", "uni", Objective.FASTEST)
        assert recommended is not None and cheapest is not None and fastest is not None

        # It should not be the ৳250 option, and it should beat the 55-minute
        # bus on time.
        assert recommended.total_fare < fastest.total_fare
        assert recommended.total_minutes < cheapest.total_minutes

    def test_the_three_objectives_can_produce_different_journeys(self):
        g = self.three_way_graph()
        signatures = {
            g.find_route("home", "uni", objective).signature()
            for objective in Objective
        }
        assert len(signatures) > 1, "objectives collapsed to one journey"

    def test_fastest_accounts_for_waiting_not_just_vehicle_time(self):
        # Spec §11: a faster vehicle with a long wait is not faster overall.
        # Train moves in 10 min but has a 15 min wait; bus moves in 20 with 8.
        g = graph_with(("a", "Kamalapur"), ("b", "Airport"))
        g.add_edge(edge("a", "b", Mode.TRAIN, km=15, minutes=10, fare=35))
        g.add_edge(edge("a", "b", Mode.BUS, km=15, minutes=20, fare=30))

        route = g.find_route("a", "b", Objective.FASTEST)
        assert route is not None
        # 10 + 15 = 25 for the train; 20 + 8 = 28 for the bus.
        assert route.modes == [Mode.TRAIN]

        # Make the wait dominate and the answer must flip.
        slow_train = RoutingPolicy(
            wait_minutes={**DEFAULT_POLICY.wait_minutes, Mode.TRAIN: 45.0}
        )
        g2 = graph_with(("a", "Kamalapur"), ("b", "Airport"), policy=slow_train)
        g2.add_edge(edge("a", "b", Mode.TRAIN, km=15, minutes=10, fare=35))
        g2.add_edge(edge("a", "b", Mode.BUS, km=15, minutes=20, fare=30))
        flipped = g2.find_route("a", "b", Objective.FASTEST)
        assert flipped is not None
        assert flipped.modes == [Mode.BUS]

    def test_cheapest_does_not_walk_across_the_city_for_free(self):
        # Walking is ৳0, so a naive fare-only weight would choose it. The
        # total-walk guard must reject it.
        g = graph_with(("a", "Home"), ("mid", "Halfway"), ("b", "University"))
        g.add_edge(edge("a", "mid", Mode.WALK, km=1.4, minutes=19))
        g.add_edge(edge("mid", "b", Mode.WALK, km=1.4, minutes=19))
        g.add_edge(edge("a", "b", Mode.BUS, km=3, minutes=12, fare=20))

        route = g.find_route("a", "b", Objective.CHEAPEST)
        assert route is not None
        # 2.8 km total walking exceeds max_total_walk_km (2.5).
        assert route.modes == [Mode.BUS]


# ---------------------------------------------------------------------------
# Multimodal journeys from the spec's verification matrix
# ---------------------------------------------------------------------------


class TestMultimodalScenarios:
    def test_walk_then_bus(self):
        g = graph_with(("home", "Home"), ("stop", "Airport Road Bus Stop"), ("uni", "University"))
        g.add_edge(edge("home", "stop", Mode.WALK, km=0.4, minutes=5))
        g.add_edge(edge("stop", "uni", Mode.BUS, km=9, minutes=30, fare=25))
        route = g.find_route("home", "uni")
        assert route is not None
        assert route.modes == [Mode.WALK, Mode.BUS]
        assert route.transfer_count == 1

    def test_rickshaw_then_bus(self):
        g = graph_with(("home", "Home"), ("stop", "Farmgate Bus Stop"), ("uni", "University"))
        g.add_edge(edge("home", "stop", Mode.RICKSHAW, km=1.4, minutes=8, fare=25))
        g.add_edge(edge("stop", "uni", Mode.BUS, km=9, minutes=30, fare=25))
        route = g.find_route("home", "uni")
        assert route is not None
        assert route.modes == [Mode.RICKSHAW, Mode.BUS]
        assert route.total_fare == 50

    def test_rickshaw_train_cng(self):
        # The spec's headline example.
        g = graph_with(
            ("home", "Home"),
            ("kamalapur", "Kamalapur Railway Station"),
            ("airport", "Airport Railway Station"),
            ("dest", "Destination"),
        )
        g.add_edge(edge("home", "kamalapur", Mode.RICKSHAW, km=1.4, minutes=7, fare=25))
        g.add_edge(edge("kamalapur", "airport", Mode.TRAIN, km=18, minutes=22, fare=35))
        g.add_edge(edge("airport", "dest", Mode.CNG, km=3.1, minutes=12, fare=80))

        route = g.find_route("home", "dest")
        assert route is not None
        assert route.modes == [Mode.RICKSHAW, Mode.TRAIN, Mode.CNG]
        assert route.total_fare == 140
        assert route.transfer_count == 2
        # Every step must be nameable — no internal ids in the journey.
        names = [g.nodes[n].name for n in route.node_ids]
        assert names == [
            "Home",
            "Kamalapur Railway Station",
            "Airport Railway Station",
            "Destination",
        ]

    def test_walk_metro_rickshaw(self):
        g = graph_with(
            ("home", "Home"),
            ("mirpur", "Mirpur 10 Metro Station"),
            ("farmgate", "Farmgate Metro Station"),
            ("uni", "University"),
        )
        g.add_edge(edge("home", "mirpur", Mode.WALK, km=0.7, minutes=9))
        g.add_edge(edge("mirpur", "farmgate", Mode.METRO, km=8.2, minutes=16, fare=40, fare_type="official"))
        g.add_edge(edge("farmgate", "uni", Mode.RICKSHAW, km=1.1, minutes=7, fare=30))
        route = g.find_route("home", "uni")
        assert route is not None
        assert route.modes == [Mode.WALK, Mode.METRO, Mode.RICKSHAW]
        assert route.total_walk_km == pytest.approx(0.7)

    def test_bus_metro_walk(self):
        g = graph_with(
            ("home", "Home"),
            ("stop", "Kalshi Bus Stop"),
            ("mirpur", "Mirpur 10 Metro Station"),
            ("motijheel", "Motijheel Metro Station"),
            ("office", "Destination"),
        )
        g.add_edge(edge("home", "stop", Mode.WALK, km=0.3, minutes=4))
        g.add_edge(edge("stop", "mirpur", Mode.BUS, km=3, minutes=14, fare=15))
        g.add_edge(edge("mirpur", "motijheel", Mode.METRO, km=11, minutes=22, fare=100, fare_type="official"))
        g.add_edge(edge("motijheel", "office", Mode.WALK, km=0.4, minutes=5))
        route = g.find_route("home", "office")
        assert route is not None
        assert route.modes == [Mode.WALK, Mode.BUS, Mode.METRO, Mode.WALK]
        assert route.transfer_count == 3
        assert route.total_walk_km == pytest.approx(0.7)

    def test_first_and_last_mile_are_both_used(self):
        g = graph_with(
            ("home", "Home"),
            ("a", "Kamalapur Railway Station"),
            ("b", "Airport Railway Station"),
            ("dest", "Destination"),
        )
        g.add_edge(edge("home", "a", Mode.RICKSHAW, km=1.2, minutes=7, fare=25))
        g.add_edge(edge("a", "b", Mode.TRAIN, km=18, minutes=22, fare=35))
        g.add_edge(edge("b", "dest", Mode.RICKSHAW, km=1.0, minutes=6, fare=20))
        route = g.find_route("home", "dest")
        assert route is not None
        assert route.edges[0].mode is Mode.RICKSHAW   # first mile
        assert route.edges[-1].mode is Mode.RICKSHAW  # last mile


# ---------------------------------------------------------------------------
# Practicality guards (spec §15)
# ---------------------------------------------------------------------------


class TestPracticality:
    def test_a_very_long_single_walk_is_rejected(self):
        g = graph_with(("a", "Home"), ("b", "University"))
        g.add_edge(edge("a", "b", Mode.WALK, km=3.0, minutes=40))
        assert g.find_route("a", "b") is None

    def test_a_pointless_100m_rickshaw_hop_is_rejected(self):
        g = graph_with(("a", "Home"), ("b", "Corner"), ("c", "University"))
        g.add_edge(edge("a", "b", Mode.RICKSHAW, km=0.1, minutes=1, fare=10))
        g.add_edge(edge("b", "c", Mode.BUS, km=5, minutes=20, fare=20))
        # The only path starts with a 100 m rickshaw, which the guard rejects.
        assert g.find_route("a", "c") is None

    def test_five_transfers_to_save_a_little_is_not_recommended(self):
        # One direct bus at ৳40 vs five hops totalling ৳35.
        g = graph_with(
            ("a", "Start"), ("b", "Stop 1"), ("c", "Stop 2"),
            ("d", "Stop 3"), ("e", "Stop 4"), ("z", "Destination"),
        )
        g.add_edge(edge("a", "z", Mode.BUS, km=10, minutes=35, fare=40))
        chain = [("a", "b"), ("b", "c"), ("c", "d"), ("d", "e"), ("e", "z")]
        for i, (x, y) in enumerate(chain):
            # Alternate modes so each hop is a real transfer.
            mode = Mode.BUS if i % 2 == 0 else Mode.CNG
            g.add_edge(edge(x, y, mode, km=2, minutes=7, fare=7))

        recommended = g.find_route("a", "z", Objective.RECOMMENDED)
        assert recommended is not None
        assert recommended.transfer_count <= 1, (
            "the transfer penalty failed to discourage a 5-hop chain"
        )

        # But CHEAPEST is allowed to take it — that is its whole job.
        cheapest = g.find_route("a", "z", Objective.CHEAPEST)
        assert cheapest is not None
        assert cheapest.total_fare == 35

    def test_the_leg_cap_stops_pathological_chains(self):
        policy = RoutingPolicy(max_legs=3)
        ids = [(f"n{i}", f"Stop {i}") for i in range(8)]
        g = graph_with(*ids, policy=policy)
        for i in range(7):
            g.add_edge(edge(f"n{i}", f"n{i+1}", Mode.BUS, km=1, minutes=5, fare=5))
        assert g.find_route("n0", "n7") is None


# ---------------------------------------------------------------------------
# Totals and reporting
# ---------------------------------------------------------------------------


class TestTotals:
    def test_fare_is_the_sum_of_payable_legs_and_walking_is_free(self):
        # Spec §25.
        g = graph_with(("a", "Home"), ("b", "Station"), ("c", "Stop"), ("d", "Destination"))
        g.add_edge(edge("a", "b", Mode.RICKSHAW, km=1.2, minutes=7, fare=30))
        g.add_edge(edge("b", "c", Mode.TRAIN, km=18, minutes=22, fare=45))
        g.add_edge(edge("c", "d", Mode.CNG, km=3, minutes=12, fare=80))
        route = g.find_route("a", "d")
        assert route is not None
        assert route.total_fare == 155

    def test_total_minutes_includes_waiting_and_transfers(self):
        g = graph_with(("a", "Home"), ("b", "Stop"), ("c", "University"))
        g.add_edge(edge("a", "b", Mode.WALK, km=0.4, minutes=5))
        g.add_edge(edge("b", "c", Mode.BUS, km=8, minutes=25, fare=30))
        route = g.find_route("a", "c")
        assert route is not None
        # 5 (walk) + 25 (bus) + 8 (bus wait) + 3 (transfer) = 41
        assert route.total_minutes == pytest.approx(41.0)

    def test_mode_sequence_collapses_consecutive_same_mode_legs(self):
        g = graph_with(("a", "A"), ("b", "B"), ("c", "C"))
        g.add_edge(edge("a", "b", Mode.BUS, km=3, minutes=10, fare=10))
        g.add_edge(edge("b", "c", Mode.BUS, km=3, minutes=10, fare=10))
        route = g.find_route("a", "c")
        assert route is not None
        assert route.modes == [Mode.BUS]
        assert route.transfer_count == 0

    def test_signature_identifies_an_identical_journey(self):
        g = TestObjectives.three_way_graph()
        a = g.find_route("home", "uni", Objective.CHEAPEST)
        b = g.find_route("home", "uni", Objective.CHEAPEST)
        assert a is not None and b is not None
        assert a.signature() == b.signature()


# ---------------------------------------------------------------------------
# Alternatives
# ---------------------------------------------------------------------------


class TestAlternatives:
    def test_banning_an_edge_produces_a_genuinely_different_route(self):
        g = TestObjectives.three_way_graph()
        first = g.find_route("home", "uni", Objective.FASTEST)
        assert first is not None

        banned = frozenset(
            (e.from_node, e.to_node, e.mode) for e in first.edges
        )
        second = g.find_route("home", "uni", Objective.FASTEST, banned_edges=banned)
        assert second is not None
        assert second.signature() != first.signature()
        assert second.total_minutes >= first.total_minutes


# ---------------------------------------------------------------------------
# Policy
# ---------------------------------------------------------------------------


class TestPolicy:
    def test_weights_live_in_one_place_and_changing_them_changes_routes(self):
        # Spec §9/§43: weights must be centralised and configurable, which is
        # only meaningful if they actually drive the outcome.
        g_cheap_time = TestObjectives.three_way_graph()
        thrifty = RoutingPolicy(taka_per_minute=0.2)
        g_thrifty = TransportGraph(policy=thrifty)
        for node in g_cheap_time.nodes.values():
            g_thrifty.add_node(node)
        for node_id in g_cheap_time.nodes:
            for e in g_cheap_time.edges_from(node_id):
                g_thrifty.add_edge(e)

        # Valuing time very low should push RECOMMENDED toward the cheap bus.
        recommended = g_thrifty.find_route("home", "uni", Objective.RECOMMENDED)
        assert recommended is not None
        assert recommended.total_fare == 30

    def test_all_default_weights_are_non_negative(self):
        # Dijkstra's correctness precondition.
        policy = DEFAULT_POLICY
        assert policy.walk_kmh > 0 and policy.rickshaw_kmh > 0 and policy.cng_kmh > 0
        assert policy.transfer_minutes >= 0
        assert policy.transfer_penalty_minutes >= 0
        assert policy.taka_per_minute >= 0
        assert all(v >= 0 for v in policy.wait_minutes.values())
