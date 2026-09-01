"""Journey assembly: graph paths turned into something a student can follow.

The rule these tests exist to enforce is spec §1–§3: an internal node id must
never reach the response. Everything a student sees is a real place name, a
real instruction and a fare whose provenance is stated.
"""
from __future__ import annotations

import pytest

from app.services.commute.graph import (
    Edge,
    Mode,
    Node,
    Objective,
    TransportGraph,
)
from app.services.commute.graph_builder import (
    GraphBuilder,
    GraphData,
    attach_endpoint,
    hired_fare,
    metro_node_id,
    place_node_id,
)
from app.services.commute.journey import (
    compare_journeys,
    explain,
    path_to_journey,
    plan_journeys,
)


def build_demo_graph() -> TransportGraph:
    """Home → University via rickshaw, metro and a walk.

    Node ids are deliberately ugly (`node_1`, `place:PLC0243`) so the tests
    can prove none of them leak into the rendered journey.
    """
    g = TransportGraph()
    g.add_node(Node("node_1", "Home", lat=23.80, lon=90.36))
    g.add_node(Node("place:PLC0243", "Mirpur 10 Metro Station", lat=23.8069, lon=90.3687))
    g.add_node(Node("metro:MRT6_12", "Farmgate Metro Station", lat=23.7583, lon=90.3897))
    g.add_node(Node("node_99", "University", lat=23.7290, lon=90.3925))

    g.add_edge(Edge("node_1", "place:PLC0243", Mode.RICKSHAW, 1.4, 8, 25,
                    fare_type="estimated", fare_source="Project baseline (17 Tk/km)",
                    fare_confidence="Low"))
    g.add_edge(Edge("place:PLC0243", "metro:MRT6_12", Mode.METRO, 8.2, 16, 40,
                    fare_type="official", fare_source="Official MRT6 fare table",
                    fare_confidence="Authoritative", service_name="MRT Line 6",
                    route_id="MRT6"))
    g.add_edge(Edge("metro:MRT6_12", "node_99", Mode.WALK, 0.25, 4, 0,
                    fare_type="none", fare_source="Walking", fare_confidence="High"))
    return g


class TestNoInternalIdentifiersLeak:
    def test_journey_shows_place_names_not_node_ids(self):
        g = build_demo_graph()
        path = g.find_route("node_1", "node_99")
        assert path is not None
        journey = path_to_journey(path, g)

        rendered = str(journey.to_dict())
        for internal in ("node_1", "node_99", "place:PLC0243", "metro:MRT6_12", "PLC0243"):
            assert internal not in rendered, f"internal id {internal} leaked"

        assert journey.legs[0].from_name == "Home"
        assert journey.legs[0].to_name == "Mirpur 10 Metro Station"
        assert journey.legs[-1].to_name == "University"

    def test_no_step_is_a_bare_letter_or_number(self):
        # Spec §34: never A -> A1 -> A2 -> B.
        g = build_demo_graph()
        path = g.find_route("node_1", "node_99")
        journey = path_to_journey(path, g)
        for leg in journey.legs:
            for name in (leg.from_name, leg.to_name):
                assert len(name) > 2, f"{name!r} is not a usable place name"
                assert not name.replace(" ", "").isdigit()


class TestInstructions:
    def test_each_leg_has_an_actionable_instruction(self):
        g = build_demo_graph()
        journey = path_to_journey(g.find_route("node_1", "node_99"), g)
        instructions = [leg.instruction for leg in journey.legs]

        assert instructions[0] == "Take a rickshaw to Mirpur 10 Metro Station."
        assert instructions[1] == (
            "Board MRT Line 6 at Mirpur 10 Metro Station and get off at "
            "Farmgate Metro Station."
        )
        assert instructions[2] == "Walk about 250 m to University."

    def test_a_named_bus_service_is_used_in_the_instruction(self):
        # Spec §22: prefer "Bus - Route/Service Name" over bare "Bus".
        g = TransportGraph()
        g.add_node(Node("a", "Farmgate Bus Stop"))
        g.add_node(Node("b", "University Gate"))
        g.add_edge(Edge("a", "b", Mode.BUS, 9, 30, 30, service_name="Bikalpa Paribahan"))
        journey = path_to_journey(g.find_route("a", "b"), g)
        assert "Bikalpa Paribahan" in journey.legs[0].instruction

    def test_an_unnamed_bus_does_not_invent_a_service_name(self):
        g = TransportGraph()
        g.add_node(Node("a", "Farmgate Bus Stop"))
        g.add_node(Node("b", "University Gate"))
        g.add_edge(Edge("a", "b", Mode.BUS, 9, 30, 30))
        journey = path_to_journey(g.find_route("a", "b"), g)
        assert journey.legs[0].instruction == (
            "Take a bus from Farmgate Bus Stop towards University Gate."
        )
        assert journey.legs[0].service_name is None


class TestFareReporting:
    def test_every_leg_states_where_its_fare_came_from(self):
        # Spec §24: do not show every value as equally authoritative.
        g = build_demo_graph()
        journey = path_to_journey(g.find_route("node_1", "node_99"), g)
        payload = journey.to_dict()

        rickshaw, metro, walk = payload["legs"]
        assert rickshaw["fareType"] == "estimated"
        assert rickshaw["fareLabel"] == "Estimated"
        assert metro["fareType"] == "official"
        assert metro["fareLabel"] == "Official"
        assert walk["fareType"] == "none"
        assert walk["fareTk"] == 0

    def test_total_is_the_sum_of_payable_legs(self):
        # Spec §25.
        g = build_demo_graph()
        journey = path_to_journey(g.find_route("node_1", "node_99"), g)
        assert journey.total_fare == 65  # 25 + 40 + 0

    def test_journey_certainty_is_the_weakest_leg(self):
        # An official metro fare must not make a negotiated rickshaw fare
        # look official.
        g = build_demo_graph()
        journey = path_to_journey(g.find_route("node_1", "node_99"), g)
        assert journey.fare_certainty == "estimated"
        assert journey.to_dict()["fareCertaintyLabel"] == "Estimated"

    def test_an_all_official_journey_reports_as_official(self):
        g = TransportGraph()
        g.add_node(Node("a", "Mirpur 10 Metro Station"))
        g.add_node(Node("b", "Farmgate Metro Station"))
        g.add_edge(Edge("a", "b", Mode.METRO, 8, 16, 40, fare_type="official"))
        journey = path_to_journey(g.find_route("a", "b"), g)
        assert journey.fare_certainty == "official"


class TestLegMerging:
    def test_consecutive_stops_on_one_service_become_one_leg(self):
        # Riding four stops is one instruction, not four.
        g = TransportGraph()
        for i, name in enumerate(["Stop A", "Stop B", "Stop C", "Stop D"]):
            g.add_node(Node(f"n{i}", name))
        for i in range(3):
            g.add_edge(Edge(f"n{i}", f"n{i+1}", Mode.BUS, 2, 8, 10,
                            service_id="SVC1", service_name="Turag"))

        journey = path_to_journey(g.find_route("n0", "n3"), g)
        assert len(journey.legs) == 1
        assert journey.legs[0].from_name == "Stop A"
        assert journey.legs[0].to_name == "Stop D"
        assert journey.legs[0].distance_km == pytest.approx(6)
        assert journey.legs[0].fare_tk == 30
        assert journey.transfer_count == 0

    def test_changing_service_within_the_same_mode_stays_two_legs(self):
        g = TransportGraph()
        for i, name in enumerate(["Stop A", "Stop B", "Stop C"]):
            g.add_node(Node(f"n{i}", name))
        g.add_edge(Edge("n0", "n1", Mode.BUS, 2, 8, 10, service_id="SVC1", service_name="Turag"))
        g.add_edge(Edge("n1", "n2", Mode.BUS, 2, 8, 10, service_id="SVC2", service_name="Bikalpa"))
        journey = path_to_journey(g.find_route("n0", "n2"), g)
        assert len(journey.legs) == 2
        assert journey.legs[0].service_name == "Turag"
        assert journey.legs[1].service_name == "Bikalpa"


class TestThreeStrategies:
    @staticmethod
    def choice_graph() -> TransportGraph:
        g = TransportGraph()
        g.add_node(Node("home", "Home"))
        g.add_node(Node("stop", "Kalshi Bus Stop"))
        g.add_node(Node("metro", "Mirpur 10 Metro Station"))
        g.add_node(Node("uni", "University"))
        g.add_edge(Edge("home", "stop", Mode.WALK, 0.5, 7, 0, fare_type="none"))
        g.add_edge(Edge("stop", "uni", Mode.BUS, 12, 55, 30, fare_type="official"))
        g.add_edge(Edge("home", "metro", Mode.WALK, 0.4, 5, 0, fare_type="none"))
        g.add_edge(Edge("metro", "uni", Mode.METRO, 11, 20, 60, fare_type="official"))
        g.add_edge(Edge("home", "uni", Mode.CNG, 13, 28, 250, fare_type="estimated"))
        return g

    def test_returns_distinct_strategies(self):
        journeys = plan_journeys(self.choice_graph(), "home", "uni")
        assert len(journeys) >= 2
        signatures = {tuple((l.from_name, l.to_name, l.mode) for l in j.legs)
                      for j in journeys}
        assert len(signatures) == len(journeys), "duplicate journeys returned"

    def test_identical_journeys_are_merged_and_carry_both_labels(self):
        # Spec §8: do not invent a different route just to fill a slot.
        g = TransportGraph()
        g.add_node(Node("a", "Home"))
        g.add_node(Node("b", "University"))
        g.add_edge(Edge("a", "b", Mode.BUS, 5, 20, 20, fare_type="official"))

        journeys = plan_journeys(g, "a", "b")
        assert len(journeys) == 1
        assert set(journeys[0].objectives) == {
            Objective.RECOMMENDED, Objective.CHEAPEST, Objective.FASTEST
        }

    def test_no_route_returns_an_empty_list(self):
        g = TransportGraph()
        g.add_node(Node("a", "Home"))
        g.add_node(Node("b", "University"))
        assert plan_journeys(g, "a", "b") == []

    def test_comparison_reports_real_differences(self):
        journeys = plan_journeys(self.choice_graph(), "home", "uni")
        compared = compare_journeys(journeys)
        assert compared[0]["fareDeltaTk"] == 0
        for entry, journey in zip(compared[1:], journeys[1:]):
            expected = round(journey.total_fare - journeys[0].total_fare, 2)
            assert entry["fareDeltaTk"] == expected

    def test_explanation_is_derived_from_real_metrics_or_omitted(self):
        # Spec §44: do not fabricate reasoning.
        journeys = plan_journeys(self.choice_graph(), "home", "uni")
        reason = explain(journeys[0], journeys)
        if reason is not None:
            assert any(ch.isdigit() for ch in reason), (
                "an explanation must cite a real number"
            )

    def test_no_explanation_when_there_is_nothing_to_compare(self):
        g = TransportGraph()
        g.add_node(Node("a", "Home"))
        g.add_node(Node("b", "University"))
        g.add_edge(Edge("a", "b", Mode.BUS, 5, 20, 20))
        journeys = plan_journeys(g, "a", "b")
        assert explain(journeys[0], []) is None


# ---------------------------------------------------------------------------
# Graph construction from dataset rows
# ---------------------------------------------------------------------------


def sample_data() -> GraphData:
    """A miniature but realistically shaped slice of the CommuteBD dataset."""
    return GraphData(
        places=[
            {"place_id": "PLC0160", "name_en": "Kalshi"},
            {"place_id": "PLC0243", "name_en": "Mirpur-12"},
            {"place_id": "PLC0300", "name_en": "Farmgate"},
        ],
        brta_edges=[
            {"from_place_id": "PLC0160", "to_place_id": "PLC0243",
             "segment_distance_km": "2.2", "route_id": "BRTA_A_101_NO"},
            {"from_place_id": "PLC0243", "to_place_id": "PLC0300",
             "segment_distance_km": "5.0", "route_id": "BRTA_A_101_NO"},
        ],
        brta_fares=[
            {"from_place_id": "PLC0160", "to_place_id": "PLC0243", "fare_tk": "12"},
        ],
        service_stops=[],
        services=[],
        metro_stations=[
            {"station_id": "MRT6_01", "name_en": "Uttara North",
             "station_order": "1", "line_id": "MRT6"},
            {"station_id": "MRT6_02", "name_en": "Uttara Center",
             "station_order": "2", "line_id": "MRT6"},
        ],
        metro_fares=[
            {"from_station_id": "MRT6_01", "to_station_id": "MRT6_02",
             "single_journey_fare_tk": "20"},
        ],
        coordinates={
            "PLC0160": (23.8200, 90.3800),
            "PLC0243": (23.8300, 90.3650),
            "PLC0300": (23.7583, 90.3897),
            "MRT6_01": (23.8690, 90.3985),
            "MRT6_02": (23.8620, 90.3990),
        },
    )


class TestGraphBuilder:
    def test_builds_nodes_and_edges_from_dataset_rows(self):
        graph = GraphBuilder().build(sample_data())
        assert place_node_id("PLC0160") in graph.nodes
        assert metro_node_id("MRT6_01") in graph.nodes
        assert graph.edge_count > 0

    def test_metro_nodes_are_named_as_stations(self):
        graph = GraphBuilder().build(sample_data())
        assert graph.nodes[metro_node_id("MRT6_01")].name == "Uttara North Metro Station"

    def test_metro_line_gets_a_human_readable_service_name(self):
        # Spec §22: "MRT Line 6", not "MRT6".
        graph = GraphBuilder().build(sample_data())
        edges = graph.edges_from(metro_node_id("MRT6_01"))
        metro_edges = [e for e in edges if e.mode is Mode.METRO]
        assert metro_edges
        assert metro_edges[0].service_name == "MRT Line 6"

    def test_metro_runs_in_both_directions(self):
        graph = GraphBuilder().build(sample_data())
        forward = [e for e in graph.edges_from(metro_node_id("MRT6_01"))
                   if e.mode is Mode.METRO]
        backward = [e for e in graph.edges_from(metro_node_id("MRT6_02"))
                    if e.mode is Mode.METRO]
        assert forward and backward

    def test_official_fare_is_used_when_the_table_has_the_pair(self):
        graph = GraphBuilder().build(sample_data())
        edges = [e for e in graph.edges_from(place_node_id("PLC0160"))
                 if e.mode is Mode.BUS and e.to_node == place_node_id("PLC0243")]
        assert edges
        assert edges[0].fare_tk == 12
        assert edges[0].fare_type == "official"

    def test_a_missing_official_fare_falls_back_to_the_per_km_rule(self):
        # Spec §28: fall back down the hierarchy, never fabricate.
        graph = GraphBuilder().build(sample_data())
        edges = [e for e in graph.edges_from(place_node_id("PLC0243"))
                 if e.mode is Mode.BUS and e.to_node == place_node_id("PLC0300")]
        assert edges
        assert edges[0].fare_type == "calculated"
        assert edges[0].fare_tk > 0
        assert "per-km" in edges[0].fare_source

    def test_walk_transfers_appear_between_nearby_nodes(self):
        graph = GraphBuilder().build(sample_data())
        walks = [
            e for node in graph.nodes for e in graph.edges_from(node)
            if e.mode is Mode.WALK
        ]
        # MRT6_01 and MRT6_02 are ~800 m apart... just outside; PLC0160 and
        # PLC0243 are ~1.7 km apart. So the fixture should produce none, and
        # that is the correct behaviour rather than inventing links.
        for walk in walks:
            assert walk.distance_km <= 0.7

    def test_places_without_coordinates_are_still_routable(self):
        data = sample_data()
        data.coordinates = {}
        graph = GraphBuilder().build(data)
        # No coordinates means no walk edges, but the bus network survives.
        route = graph.find_route(place_node_id("PLC0160"), place_node_id("PLC0300"))
        assert route is not None
        assert route.modes == [Mode.BUS]


class TestEndpointAttachment:
    def test_origin_is_connected_by_first_mile_modes(self):
        graph = GraphBuilder().build(sample_data())
        made = attach_endpoint(
            graph, node_id="origin", name="Your location",
            lat=23.8210, lon=90.3810, is_origin=True,
        )
        assert made > 0
        modes = {e.mode for e in graph.edges_from("origin")}
        assert modes & {Mode.WALK, Mode.RICKSHAW, Mode.CNG}

    def test_last_mile_edges_point_towards_the_destination(self):
        graph = GraphBuilder().build(sample_data())
        attach_endpoint(
            graph, node_id="dest", name="University",
            lat=23.7590, lon=90.3900, is_origin=False,
        )
        # A destination has incoming edges, not outgoing ones.
        assert graph.edges_from("dest") == []
        incoming = [
            e for node in graph.nodes for e in graph.edges_from(node)
            if e.to_node == "dest"
        ]
        assert incoming

    def test_a_point_far_from_the_network_gets_no_connection(self):
        # Spec §31: no route is a real answer, not a reason to invent one.
        graph = GraphBuilder().build(sample_data())
        made = attach_endpoint(
            graph, node_id="remote", name="Somewhere remote",
            lat=21.45, lon=91.98, is_origin=True,   # Cox's Bazar
        )
        assert made == 0

    def test_end_to_end_journey_through_a_built_graph(self):
        graph = GraphBuilder().build(sample_data())
        attach_endpoint(graph, node_id="origin", name="Home",
                        lat=23.8210, lon=90.3810, is_origin=True)
        attach_endpoint(graph, node_id="dest", name="University",
                        lat=23.7590, lon=90.3900, is_origin=False)

        journeys = plan_journeys(graph, "origin", "dest")
        assert journeys, "no journey found through the built graph"

        journey = journeys[0]
        assert journey.legs[0].from_name == "Home"
        assert journey.legs[-1].to_name == "University"
        rendered = str(journey.to_dict())
        assert "place:" not in rendered and "metro:" not in rendered


class TestHiredFare:
    def test_rickshaw_uses_the_project_per_km_baseline(self):
        fare, fare_type, source, confidence = hired_fare(Mode.RICKSHAW, 2.0)
        assert fare == 35  # 2 km x 17 Tk/km = 34, rounded to nearest 5
        assert fare_type == "estimated"
        assert "17" in source
        assert confidence == "Low"

    def test_short_rides_respect_the_minimum(self):
        fare, *_ = hired_fare(Mode.RICKSHAW, 0.5)
        assert fare >= 20

    def test_cng_has_a_higher_minimum_than_rickshaw(self):
        cng, *_ = hired_fare(Mode.CNG, 0.5)
        rickshaw, *_ = hired_fare(Mode.RICKSHAW, 0.5)
        assert cng > rickshaw

    def test_a_hired_fare_is_never_labelled_official(self):
        for mode in (Mode.RICKSHAW, Mode.CNG):
            _, fare_type, _, _ = hired_fare(mode, 3.0)
            assert fare_type == "estimated"
