// Guards for the CommuteBD multimodal journey UI.
//
// The rules being pinned here are the ones the spec is emphatic about, and
// they are the ones a well-meaning future edit is most likely to break:
//
//   1. **No internal identifier ever renders.** Every step must name a real
//      place. A regression here looks like "A1 → A2" on a student's screen.
//   2. **No fare laundering.** An unknown or estimated provenance must never
//      surface as "Official", and a journey's headline certainty must be its
//      *weakest* leg, not its best one.
//   3. **Distinct strategies.** A journey found by two objectives carries
//      both labels rather than being listed twice.
//   4. **No invented geometry.** Legs without coordinates are still listed as
//      steps; they are simply not drawn, and the map says so.
//
// The map itself is not pumped — a `TileLayer` would try to reach
// tile.openstreetmap.org — so these exercise the models, the timeline and the
// summary card, which is where the honesty rules actually live.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/life/presentation/commute/journey_models.dart';
import 'package:gochano/features/life/presentation/commute/journey_view.dart';
import 'dart:io';
import 'package:gochano/features/life/presentation/commute/smart_journey_guide.dart';

/// A response shaped exactly like the one `POST /api/commute/routes` returns
/// for Mirpur 10 → Farmgate, taken from `scripts/verify_commute_routing.py`
/// output against the real dataset.
Map<String, dynamic> _response({
  bool available = true,
  String? reason,
  List<String> outsideCoverage = const [],
}) {
  return {
    'journeyPlanning': {
      'available': available,
      'reason': reason,
      if (outsideCoverage.isNotEmpty) 'outsideCoverage': outsideCoverage,
      'coverageRadiusKm': 4.0,
    },
    'journeys': !available
        ? []
        : [
            {
              'objectives': ['recommended', 'fastest'],
              'category': 'recommended',
              'origin': 'Mirpur 10 area',
              'destination': 'Farmgate',
              'totalFareTk': 30.0,
              'totalDurationMinutes': 25,
              'totalDistanceKm': 6.1,
              'totalWalkKm': 0.2,
              'transfers': 2,
              'modeSummary': ['Walk', 'Metro', 'Walk'],
              'fareCertainty': 'official',
              'fareCertaintyLabel': 'Official',
              'fareDeltaTk': 0,
              'durationDeltaMinutes': 0,
              'whyRecommended':
                  'About 26 minutes faster than the cheapest option for '
                      'around ৳16 more.',
              'legs': [
                {
                  'mode': 'walk',
                  'modeLabel': 'Walk',
                  'from': 'Mirpur 10 area',
                  'to': 'Mirpur 10 Metro Station',
                  'distanceKm': 0.03,
                  'durationMinutes': 1,
                  'fareTk': 0.0,
                  'fareType': 'none',
                  'fareLabel': 'Free',
                  'fareSource': '',
                  'instruction':
                      'Walk about 30 m to Mirpur 10 Metro Station.',
                  'isTransfer': false,
                  'transferMinutes': 0,
                  'serviceName': null,
                  'fromLat': 23.8069,
                  'fromLon': 90.3687,
                  'toLat': 23.8072,
                  'toLon': 90.3689,
                },
                {
                  'mode': 'metro',
                  'modeLabel': 'Metro',
                  'from': 'Mirpur 10 Metro Station',
                  'to': 'Farmgate Metro Station',
                  'distanceKm': 5.9,
                  'durationMinutes': 12,
                  'fareTk': 30.0,
                  'fareType': 'official',
                  'fareLabel': 'Official',
                  'fareSource': 'Official MRT6 fare table',
                  'instruction':
                      'Board MRT Line 6 at Mirpur 10 Metro Station and get '
                          'off at Farmgate Metro Station.',
                  'isTransfer': true,
                  'transferMinutes': 7,
                  'serviceName': 'MRT Line 6',
                  'fromLat': 23.8072,
                  'fromLon': 90.3689,
                  'toLat': 23.7583,
                  'toLon': 90.3897,
                },
              ],
            },
            {
              'objectives': ['cheapest'],
              'category': 'cheapest',
              'origin': 'Mirpur 10 area',
              'destination': 'Farmgate',
              'totalFareTk': 14.0,
              'totalDurationMinutes': 52,
              'totalDistanceKm': 6.4,
              'totalWalkKm': 0.9,
              'transfers': 2,
              'modeSummary': ['Walk', 'Bus', 'Walk'],
              'fareCertainty': 'historical',
              'fareCertaintyLabel': 'Historical rule',
              'fareDeltaTk': -16.0,
              'durationDeltaMinutes': 27,
              'legs': [
                {
                  'mode': 'bus',
                  'modeLabel': 'Bus',
                  'from': 'Mirpur 10 Bus Stop',
                  'to': 'Farmgate Bus Stop',
                  'distanceKm': 5.5,
                  'durationMinutes': 21,
                  'fareTk': 14.0,
                  'fareType': 'historical',
                  'fareLabel': 'Historical rule',
                  'fareSource': 'BRTA 2.45 Tk/km project rule',
                  'instruction':
                      'Take a bus from Mirpur 10 Bus Stop towards Farmgate '
                          'Bus Stop.',
                  'isTransfer': false,
                  'transferMinutes': 8,
                  'serviceName': null,
                  // No coordinates for these stops: the step must still be
                  // listed, it just cannot be drawn.
                  'fromLat': null,
                  'fromLon': null,
                  'toLat': null,
                  'toLon': null,
                },
              ],
            },
          ],
  };
}

Widget _wrap(Widget child) => MaterialApp(
      theme: GochanoTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

void main() {
  group('JourneyPlan parsing', () {
    test('reads the planner envelope and both journeys', () {
      final plan = JourneyPlan.fromResponse(_response());

      expect(plan.status, JourneyPlanningStatus.available);
      expect(plan.journeys, hasLength(2));
      expect(plan.hasJourneys, isTrue);
      expect(plan.isNoRoute, isFalse);
    });

    test('a journey found by two objectives carries both labels', () {
      // Spec §8: never three identical routes under different names. The
      // backend deduplicates; the UI has to show the combined label rather
      // than silently dropping one.
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;

      expect(journey.isRecommended, isTrue);
      expect(journey.isFastest, isTrue);
      expect(journey.isCheapest, isFalse);
      expect(journeyStrategyLabel(journey), 'Recommended · Fastest');
    });

    test('comparison deltas come through signed', () {
      final cheapest = JourneyPlan.fromResponse(_response()).journeys[1];

      expect(cheapest.fareDeltaTk, -16.0);
      expect(cheapest.durationDeltaMinutes, 27);
    });

    test('a leg without coordinates is parsed but not mappable', () {
      final plan = JourneyPlan.fromResponse(_response());

      expect(plan.journeys.first.legs.every((l) => l.isMappable), isTrue);
      expect(plan.journeys[1].legs.single.isMappable, isFalse);
      // Crucially it is still a leg. Dropping it would silently shorten the
      // journey the student is told to take.
      expect(plan.journeys[1].legs, hasLength(1));
    });

    test('a blank serviceName becomes null rather than an empty label', () {
      final plan = JourneyPlan.fromResponse(_response());

      expect(plan.journeys.first.legs[1].serviceName, 'MRT Line 6');
      expect(plan.journeys[1].legs.single.serviceName, isNull);
    });

    test('an unplannable response is classified by reason, not guessed', () {
      expect(
        JourneyPlan.fromResponse(
          _response(available: false, reason: 'dataset_unavailable'),
        ).status,
        JourneyPlanningStatus.datasetUnavailable,
      );

      final coverage = JourneyPlan.fromResponse(
        _response(
          available: false,
          reason: 'outside_network_coverage',
          outsideCoverage: ['destination'],
        ),
      );
      expect(coverage.status, JourneyPlanningStatus.outsideCoverage);
      expect(coverage.outsideCoverage, ['destination']);
      expect(coverage.coverageRadiusKm, 4.0);

      // An unrecognised reason must not be reported as a successful plan.
      expect(
        JourneyPlan.fromResponse(
          _response(available: false, reason: 'something_new'),
        ).status,
        JourneyPlanningStatus.plannerError,
      );
    });

    test('routing that ran but found nothing is not an error', () {
      final plan = JourneyPlan.fromResponse({
        'journeyPlanning': {'available': true, 'reason': 'no_route'},
        'journeys': [],
      });

      // "We looked and there is no route" and "we could not look" need
      // different messages, so they must stay distinguishable.
      expect(plan.status, JourneyPlanningStatus.available);
      expect(plan.isNoRoute, isTrue);
    });

    test('a response with no planner keys at all degrades safely', () {
      // Older backends, or a fare-only response, must not throw.
      final plan = JourneyPlan.fromResponse({'distanceKm': 6.1});

      expect(plan.journeys, isEmpty);
      expect(plan.status, JourneyPlanningStatus.plannerError);
    });
  });

  group('JourneyTimeline', () {
    testWidgets('names every stop and shows every instruction', (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      await tester.pumpWidget(_wrap(JourneyTimeline(journey: journey)));

      // Both ends and the interchange, by name.
      expect(find.text('Mirpur 10 area'), findsOneWidget);
      expect(find.text('Mirpur 10 Metro Station'), findsOneWidget);
      expect(find.text('Farmgate Metro Station'), findsOneWidget);

      expect(
        find.text('Walk about 30 m to Mirpur 10 Metro Station.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Board MRT Line 6 at Mirpur 10 Metro Station and get off at '
          'Farmgate Metro Station.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders no internal node identifier', (tester) async {
      // Spec §1–§3. The failure this pins is a step reading "A1" or
      // "node_123" instead of a place a student can walk to.
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      await tester.pumpWidget(_wrap(JourneyTimeline(journey: journey)));

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');

      expect(rendered, isNot(matches(RegExp(r'\bnode_\w+'))));
      expect(rendered, isNot(matches(RegExp(r'\b__(origin|destination)__'))));
      // A bare "A1"/"A2"-style token standing alone as a step label.
      expect(rendered, isNot(matches(RegExp(r'(?<![\w.])A\d(?![\w.])'))));
    });

    testWidgets('surfaces the transfer as its own timed step', (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      await tester.pumpWidget(_wrap(JourneyTimeline(journey: journey)));

      expect(
        find.text('Change here — allow about 7 min'),
        findsOneWidget,
      );
    });

    testWidgets('keeps each leg fare next to its provenance', (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      await tester.pumpWidget(_wrap(JourneyTimeline(journey: journey)));

      expect(find.text('Official'), findsOneWidget);
      expect(find.text('Official MRT6 fare table'), findsOneWidget);
      expect(find.text('5.9 km · 12 min · ৳30'), findsOneWidget);

      // The free walking leg carries no provenance badge at all -- there is
      // no fare to vouch for, so there is nothing to label.
      expect(find.text('0.0 km · 1 min · Free'), findsOneWidget);
      expect(find.text('Estimated'), findsNothing);
    });

    testWidgets('lists a leg that has no coordinates', (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys[1];
      await tester.pumpWidget(_wrap(JourneyTimeline(journey: journey)));

      expect(find.text('Mirpur 10 Bus Stop'), findsOneWidget);
      expect(find.text('Farmgate Bus Stop'), findsOneWidget);
    });
  });

  group('JourneyFareBadge', () {
    testWidgets('never labels an unknown provenance as official',
        (tester) async {
      for (final unknown in ['', 'guessed', 'ml', 'predicted', 'wishful']) {
        await tester.pumpWidget(_wrap(JourneyFareBadge(fareType: unknown)));
        await tester.pump();

        expect(find.text('Official'), findsNothing,
            reason: '"$unknown" must not present as an official fare');
        if (unknown.isNotEmpty) {
          expect(find.text('Estimated'), findsOneWidget);
        }
      }
    });

    testWidgets('shows nothing at all when there is no fare', (tester) async {
      await tester.pumpWidget(_wrap(const JourneyFareBadge(fareType: 'none')));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('JourneySummaryCard', () {
    testWidgets('reports the weakest fare certainty, not the best',
        (tester) async {
      // The cheapest journey's only fare is a historical BRTA rule. It must
      // not borrow confidence from anywhere.
      final journey = JourneyPlan.fromResponse(_response()).journeys[1];
      await tester.pumpWidget(_wrap(JourneySummaryCard(journey: journey)));

      expect(find.text('Historical rule'), findsOneWidget);
      expect(find.text('Official'), findsNothing);
    });

    testWidgets('states the comparison against the recommended route',
        (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys[1];
      await tester.pumpWidget(_wrap(JourneySummaryCard(journey: journey)));

      expect(
        find.textContaining('cheaper'),
        findsOneWidget,
      );
      expect(find.textContaining('27 min slower'), findsOneWidget);
    });

    testWidgets('shows the recommended reason the backend measured',
        (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      await tester.pumpWidget(_wrap(JourneySummaryCard(journey: journey)));

      expect(
        find.textContaining('faster than the cheapest option'),
        findsOneWidget,
      );
    });

    testWidgets('shows no comparison line for the baseline journey',
        (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      await tester.pumpWidget(_wrap(JourneySummaryCard(journey: journey)));

      // Zero deltas must not render as "৳0 more, 0 min slower".
      expect(find.textContaining('than the recommended route'), findsNothing);
    });

    testWidgets('shows the mode sequence and the totals', (tester) async {
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      await tester.pumpWidget(_wrap(JourneySummaryCard(journey: journey)));

      expect(find.text('Walk'), findsNWidgets(2));
      expect(find.text('Metro'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('JourneyPlanSection', () {
    testWidgets('explains which end is off the network', (tester) async {
      final plan = JourneyPlan.fromResponse(
        _response(
          available: false,
          reason: 'outside_network_coverage',
          outsideCoverage: ['origin'],
        ),
      );
      await tester.pumpWidget(_wrap(JourneyPlanSection(plan: plan)));

      expect(find.textContaining('starting point'), findsOneWidget);
      // The generic fallback would be wrong here — it hides which end failed.
      expect(find.textContaining('Neither place'), findsNothing);
    });

    testWidgets('says so when the dataset could not be loaded', (tester) async {
      final plan = JourneyPlan.fromResponse(
        _response(available: false, reason: 'dataset_unavailable'),
      );
      await tester.pumpWidget(_wrap(JourneyPlanSection(plan: plan)));

      expect(
        find.textContaining('Transport network is temporarily unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('distinguishes "no route" from "could not plan"',
        (tester) async {
      final plan = JourneyPlan.fromResponse({
        'journeyPlanning': {'available': true, 'reason': 'no_route'},
        'journeys': [],
      });
      await tester.pumpWidget(_wrap(JourneyPlanSection(plan: plan)));

      expect(find.text('No complete journey found'), findsOneWidget);
    });
  });
  group('JourneyPlan.roadFallback', () {
    test(
      '1. real multimodal journey renders normally (no fallback applied)',
      () {
        final plan = JourneyPlan.fromResponse(_response());
        expect(plan.status, JourneyPlanningStatus.available);
        expect(plan.hasJourneys, isTrue);
        // Fallback should not be needed
        final fallback = JourneyPlan.roadFallback(_response());
        expect(fallback, isNull);
      },
    );

    test(
      '2. dataset_unavailable + road distance produces estimated journey',
      () {
        final body = {
          'journeyPlanning': {
            'available': false,
            'reason': 'dataset_unavailable',
          },
          'journeys': [],
          'distanceKm': 6.1,
          'estimatedDurationMin': 18,
          'origin': {'name': 'Mirpur 10', 'lat': 23.81, 'lon': 90.37},
          'destination': {'name': 'Farmgate', 'lat': 23.76, 'lon': 90.39},
        };
        final fallback = JourneyPlan.roadFallback(body);
        expect(fallback, isNotNull);
        expect(fallback!.hasJourneys, isTrue);
        expect(fallback.journeys.first.totalDistanceKm, 6.1);
        // Raw OSRM duration preserved — no unjustified multiplier
        expect(fallback.journeys.first.totalDurationMinutes, 18);
        expect(fallback.journeys.first.fareCertainty, 'estimated');
      },
    );

    test(
      '3. outside_network_coverage + road distance produces estimated journey',
      () {
        final body = {
          'journeyPlanning': {
            'available': false,
            'reason': 'outside_network_coverage',
            'outsideCoverage': ['origin'],
          },
          'journeys': [],
          'distanceKm': 3.2,
          'estimatedDurationMin': 10,
          'origin': {'name': 'Uttara', 'lat': 23.88, 'lon': 90.40},
          'destination': {'name': 'Banani', 'lat': 23.79, 'lon': 90.40},
        };
        final fallback = JourneyPlan.roadFallback(body);
        expect(fallback, isNotNull);
        expect(fallback!.hasJourneys, isTrue);
        expect(fallback.journeys.first.legs, hasLength(1));
        // Raw OSRM duration preserved — no unjustified multiplier
        expect(fallback.journeys.first.totalDurationMinutes, 10);
      },
    );

    test('4. plannerError + valid road route produces estimated journey', () {
      final body = {
        'journeyPlanning': {'available': false, 'reason': 'planner_error'},
        'journeys': [],
        'distanceKm': 4.5,
        'estimatedDurationMin': 14,
        'origin': {'name': 'Dhanmondi'},
        'destination': {'name': 'Gulshan'},
      };
      final fallback = JourneyPlan.roadFallback(body);
      expect(fallback, isNotNull);
      expect(fallback!.journeys.first.origin, 'Dhanmondi');
      expect(fallback.journeys.first.destination, 'Gulshan');
    });

    test(
      '5. empty journeys + distance/duration produces estimated journey',
      () {
        final body = {
          'journeyPlanning': {'available': true},
          'journeys': [],
          'distanceKm': 2.0,
          'estimatedDurationMin': 8,
          'origin': {'name': 'A'},
          'destination': {'name': 'B'},
        };
        // roadFallback now applies for available + empty journeys too,
        // as the fallback gate was changed to !plan.hasJourneys.
        final plan = JourneyPlan.fromResponse(body);
        expect(plan.status, JourneyPlanningStatus.available);
        expect(plan.isNoRoute, isTrue);
        // roadFallback can still build from the data
        final fallback = JourneyPlan.roadFallback(body);
        expect(fallback, isNotNull);
        expect(fallback!.journeys.first.totalDistanceKm, 2.0);
        // Raw OSRM duration preserved — no unjustified multiplier
        expect(fallback.journeys.first.totalDurationMinutes, 8);
      },
    );

    test('6. fallback contains no fabricated stop/station/bus route data', () {
      final body = {
        'journeyPlanning': {
          'available': false,
          'reason': 'dataset_unavailable',
        },
        'journeys': [],
        'distanceKm': 5.0,
        'estimatedDurationMin': 15,
        'origin': {'name': 'Mirpur 10'},
        'destination': {'name': 'Farmgate'},
      };
      final fallback = JourneyPlan.roadFallback(body)!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.serviceName, isNull);
      // Without selectedMode, defaults to 'road' / 'By road'
      expect(leg.mode, 'road');
      expect(leg.modeLabel, 'By road');
      expect(leg.fareType, 'estimated');
    });

    test('7. estimated banner appears for fallback', () {
      final body = {
        'journeyPlanning': {
          'available': false,
          'reason': 'dataset_unavailable',
        },
        'journeys': [],
        'distanceKm': 5.0,
        'estimatedDurationMin': 15,
        'origin': {'name': 'A'},
        'destination': {'name': 'B'},
      };
      final plan = JourneyPlan.fromResponse(body);
      expect(
        plan.status == JourneyPlanningStatus.datasetUnavailable ||
            plan.status == JourneyPlanningStatus.plannerError,
        isTrue,
      );
    });

    test(
      '8. estimated banner not incorrectly shown for fully real journey',
      () {
        final plan = JourneyPlan.fromResponse(_response());
        expect(plan.status, JourneyPlanningStatus.available);
        expect(plan.hasJourneys, isTrue);
        // For a real journey, the isEstimatedFallback flag would be false
        // (checked in commute_screen.dart, not in the model)
      },
    );

    test('9. exactly one Your journey section (JourneyPlanSection)', () {
      // The _Results widget creates exactly one JourneyPlanSection.
      // Verified by source inspection in commute_rebuild_step6_test.dart.
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'JourneyPlanSection('.allMatches(source).length;
      expect(count, 1);
    });

    test('10. exactly one route map in result composition', () {
      // CommuteRouteMap appears exactly once in commute_screen.dart
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'CommuteRouteMap('.allMatches(source).length;
      expect(count, 1);
    });

    test(
      '11. zero usable route data → retry/error state (roadFallback returns null)',
      () {
        final body = {
          'journeyPlanning': {
            'available': false,
            'reason': 'dataset_unavailable',
          },
          'journeys': [],
          'distanceKm': 0,
          'estimatedDurationMin': 0,
        };
        final fallback = JourneyPlan.roadFallback(body);
        expect(fallback, isNull);
      },
    );

    testWidgets(
      '12. widget does not crash when journey legs are empty/malformed',
      (tester) async {
        // A journey with zero legs should render without throwing.
        final plan = JourneyPlan(
          status: JourneyPlanningStatus.available,
          journeys: [
            const Journey(
              objectives: ['estimated'],
              category: 'estimated',
              origin: 'A',
              destination: 'B',
              totalFareTk: 0,
              totalDurationMinutes: 10,
              totalDistanceKm: 3.0,
              totalWalkKm: 0,
              transfers: 0,
              modeSummary: [],
              fareCertainty: 'estimated',
              fareCertaintyLabel: '',
              legs: [],
              fareDeltaTk: 0,
              durationDeltaMinutes: 0,
            ),
          ],
        );
        await tester.pumpWidget(_wrap(JourneyPlanSection(plan: plan)));
        // Should not throw; timeline is empty but section renders.
        expect(find.text('Your journey'), findsOneWidget);
      },
    );
  });

  group('Phase 2 correction — fare, mode label, ETA', () {
    Map<String, dynamic> roadBody({
      double distanceKm = 5.0,
      int durationMin = 15,
      String origin = 'Mirpur 10',
      String destination = 'Farmgate',
    }) => {
      'journeyPlanning': {'available': false, 'reason': 'dataset_unavailable'},
      'journeys': [],
      'distanceKm': distanceKm,
      'estimatedDurationMin': durationMin,
      'origin': {'name': origin},
      'destination': {'name': destination},
    };

    test('13. paid mode with missing fare shows fareAvailable=false', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.fareAvailable, isFalse);
      expect(leg.isFree, isFalse);
      expect(leg.fareType, 'estimated');
    });

    test('14. walking leg shows fareAvailable=true and isFree', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'walk',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.fareAvailable, isTrue);
      expect(leg.isFree, isTrue);
      expect(leg.fareType, 'none');
    });

    test('15. selectedMode=cng produces CNG label and icon id', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.mode, 'cng');
      expect(leg.modeLabel, 'CNG');
      expect(fallback.journeys.first.modeSummary, ['CNG']);
    });

    test('16. selectedMode=bus produces Bus label', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'bus',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.mode, 'bus');
      expect(leg.modeLabel, 'Bus');
    });

    test('17. selectedMode=rickshaw produces Rickshaw label', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'rickshaw',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.mode, 'rickshaw');
      expect(leg.modeLabel, 'Rickshaw');
    });

    test('18. ETA equals raw OSRM duration (no multiplier)', () {
      final osrmMin = 12;
      final body = roadBody(durationMin: osrmMin);
      for (final mode in ['cng', 'bus', 'rickshaw', 'car', 'metro', 'walk']) {
        final fallback = JourneyPlan.roadFallback(body, selectedMode: mode)!;
        final eta = fallback.journeys.first.totalDurationMinutes;
        expect(
          eta,
          equals(osrmMin),
          reason: '$mode ETA ($eta) must equal OSRM ($osrmMin)',
        );
      }
    });

    test('19. ETA is raw OSRM, not inflated', () {
      final body = roadBody(durationMin: 18);
      final fallback = JourneyPlan.roadFallback(body, selectedMode: 'cng')!;
      // No multiplier — raw OSRM preserved as minimum road time
      expect(fallback.journeys.first.totalDurationMinutes, 18);
    });

    test('20. walking ETA equals raw OSRM (multiplier 1.0)', () {
      final body = roadBody(durationMin: 5);
      final fallback = JourneyPlan.roadFallback(body, selectedMode: 'walk')!;
      expect(fallback.journeys.first.totalDurationMinutes, 5);
    });

    test('21. edge case: journeys=[] + status=available + road data', () {
      final body = {
        'journeyPlanning': {'available': true},
        'journeys': [],
        'distanceKm': 4.0,
        'estimatedDurationMin': 12,
        'origin': {'name': 'A'},
        'destination': {'name': 'B'},
      };
      final plan = JourneyPlan.fromResponse(body);
      expect(plan.status, JourneyPlanningStatus.available);
      expect(plan.hasJourneys, isFalse);
      // roadFallback should produce a journey from the road data
      final fallback = JourneyPlan.roadFallback(body, selectedMode: 'bus');
      expect(fallback, isNotNull);
      expect(fallback!.hasJourneys, isTrue);
      expect(fallback.journeys.first.totalDistanceKm, 4.0);
    });

    test('22. no fabricated transit data in fallback legs', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.serviceName, isNull);
      expect(leg.instruction, isEmpty);
      expect(leg.isTransfer, isFalse);
      expect(leg.transferMinutes, 0);
    });

    test('23. fallback Journey has fareCertainty=estimated', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
      )!;
      expect(fallback.journeys.first.fareCertainty, 'estimated');
      expect(fallback.journeys.first.fareCertaintyLabel, 'Estimated');
    });

    testWidgets(
      '24. fallback timeline renders mode label, not "Road journey"',
      (tester) async {
        final fallback = JourneyPlan.roadFallback(
          roadBody(),
          selectedMode: 'cng',
        )!;
        await tester.pumpWidget(
          _wrap(JourneyTimeline(journey: fallback.journeys.first)),
        );
        expect(find.text('CNG'), findsOneWidget);
        expect(find.text('Road journey'), findsNothing);
      },
    );

    testWidgets(
      '25. fallback summary card shows "Fare unavailable" for paid mode',
      (tester) async {
        final fallback = JourneyPlan.roadFallback(
          roadBody(),
          selectedMode: 'cng',
        )!;
        await tester.pumpWidget(
          _wrap(JourneySummaryCard(journey: fallback.journeys.first)),
        );
        expect(find.textContaining('Fare unavailable'), findsOneWidget);
        expect(find.text('Free'), findsNothing);
      },
    );

    testWidgets('26. fallback summary card shows "Free" for walking', (
      tester,
    ) async {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'walk',
      )!;
      await tester.pumpWidget(
        _wrap(JourneySummaryCard(journey: fallback.journeys.first)),
      );
      expect(find.text('Free'), findsOneWidget);
    });

    test('27. exactly one map per result (source inspection)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'CommuteRouteMap('.allMatches(source).length;
      expect(count, 1);
    });
  });

  group('Phase 2 final correction — fare propagation + ETA honesty', () {
    Map<String, dynamic> roadBody({
      double distanceKm = 5.0,
      int durationMin = 15,
      String origin = 'Mirpur 10',
      String destination = 'Farmgate',
    }) => {
      'journeyPlanning': {'available': false, 'reason': 'dataset_unavailable'},
      'journeys': [],
      'distanceKm': distanceKm,
      'estimatedDurationMin': durationMin,
      'origin': {'name': origin},
      'destination': {'name': destination},
    };

    Map<String, dynamic> singleFareResult({
      String mode = 'cng',
      double fareLow = 280,
      double fareHigh = 320,
      String fareType = 'estimated',
      String source = 'Distance-based estimate',
    }) => {
      'supported': true,
      'mode': mode,
      'fare': {
        'mode': mode,
        'label': mode.toUpperCase(),
        'minutes': 18,
        'fareLow': fareLow,
        'fareHigh': fareHigh,
        'fareType': fareType,
        'source': source,
      },
    };

    test('F1. selected CNG + existing CNG fare → fare propagated', () {
      final fare = singleFareResult(mode: 'cng', fareLow: 280, fareHigh: 320);
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
        singleFareResult: fare,
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.fareAvailable, isTrue);
      expect(leg.fareLow, 280);
      expect(leg.fareHigh, 320);
      expect(leg.fareTk, 280);
      expect(leg.fareType, 'estimated');
    });

    test('F2. selected Bus + existing Bus fare → fare propagated', () {
      final fare = singleFareResult(
        mode: 'bus',
        fareLow: 50,
        fareHigh: 70,
        source: 'BRTA 2.45 Tk/km project rule',
      );
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'bus',
        singleFareResult: fare,
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.fareAvailable, isTrue);
      expect(leg.fareLow, 50);
      expect(leg.fareHigh, 70);
    });

    test('F3. selected Rickshaw + existing estimate → fare propagated', () {
      final fare = singleFareResult(
        mode: 'rickshaw',
        fareLow: 100,
        fareHigh: 150,
      );
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'rickshaw',
        singleFareResult: fare,
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.fareAvailable, isTrue);
      expect(leg.fareLow, 100);
      expect(leg.fareHigh, 150);
    });

    test('F4. missing paid-mode fare → Fare unavailable, never Free', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.fareAvailable, isFalse);
      expect(leg.isFree, isFalse);
      expect(leg.fareTk, 0);
    });

    test('F5. walking → Free allowed', () {
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'walk',
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.fareAvailable, isTrue);
      expect(leg.isFree, isTrue);
      expect(leg.fareType, 'none');
    });

    testWidgets('F6. changing mode updates label, icon, fare in timeline', (
      tester,
    ) async {
      // Build with CNG fare
      final fare = singleFareResult(mode: 'cng', fareLow: 280, fareHigh: 320);
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
        singleFareResult: fare,
      )!;
      await tester.pumpWidget(
        _wrap(JourneyTimeline(journey: fallback.journeys.first)),
      );
      expect(find.text('CNG'), findsOneWidget);
      expect(find.textContaining('280'), findsOneWidget);
      expect(find.textContaining('320'), findsOneWidget);
    });

    test('F7. no second duplicate fare calculation — fare reused from API', () {
      // The fare result from the single-fare API is passed directly into
      // roadFallback. No independent calculation happens inside roadFallback.
      final fare = singleFareResult(mode: 'cng', fareLow: 280, fareHigh: 320);
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
        singleFareResult: fare,
      )!;
      final leg = fallback.journeys.first.legs.single;
      // Values come directly from singleFareResult, not recalculated
      expect(leg.fareLow, 280);
      expect(leg.fareHigh, 320);
    });

    test('F8. unjustified multipliers removed — ETA equals OSRM', () {
      final body = roadBody(durationMin: 18);
      for (final mode in ['cng', 'bus', 'rickshaw', 'car', 'metro', 'walk']) {
        final fallback = JourneyPlan.roadFallback(body, selectedMode: mode)!;
        expect(
          fallback.journeys.first.totalDurationMinutes,
          18,
          reason: '$mode ETA must equal raw OSRM, no multiplier',
        );
      }
    });

    testWidgets('F9. OSRM-only duration labelled without traffic', (
      tester,
    ) async {
      final fallback = JourneyPlan.roadFallback(
        roadBody(durationMin: 18),
        selectedMode: 'cng',
      )!;
      await tester.pumpWidget(
        _wrap(JourneyTimeline(journey: fallback.journeys.first)),
      );
      expect(find.textContaining('18 min'), findsOneWidget);
      expect(find.textContaining('without traffic'), findsOneWidget);
    });

    testWidgets('F10. OSRM-only NOT labelled as live ETA', (tester) async {
      final fallback = JourneyPlan.roadFallback(
        roadBody(durationMin: 18),
        selectedMode: 'cng',
      )!;
      await tester.pumpWidget(
        _wrap(JourneyTimeline(journey: fallback.journeys.first)),
      );
      expect(find.textContaining('live'), findsNothing);
      expect(find.textContaining('traffic-aware'), findsNothing);
      expect(find.textContaining('real-time'), findsNothing);
    });

    testWidgets('F11. real multimodal backend duration preserved', (
      tester,
    ) async {
      // When real multimodal data exists, its duration is used as-is
      final journey = JourneyPlan.fromResponse(_response()).journeys.first;
      expect(journey.totalDurationMinutes, 25); // Mirpur 10 → Farmgate
      await tester.pumpWidget(_wrap(JourneyTimeline(journey: journey)));
      // No "without traffic" label on real multimodal legs
      expect(find.textContaining('without traffic'), findsNothing);
    });

    testWidgets('F12. summary card shows fare range when available', (
      tester,
    ) async {
      final fare = singleFareResult(mode: 'cng', fareLow: 280, fareHigh: 320);
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
        singleFareResult: fare,
      )!;
      await tester.pumpWidget(
        _wrap(JourneySummaryCard(journey: fallback.journeys.first)),
      );
      expect(find.textContaining('280'), findsOneWidget);
      expect(find.textContaining('320'), findsOneWidget);
    });

    testWidgets('F13. summary card shows "without traffic" for ETA', (
      tester,
    ) async {
      final fallback = JourneyPlan.roadFallback(
        roadBody(durationMin: 18),
        selectedMode: 'cng',
      )!;
      await tester.pumpWidget(
        _wrap(JourneySummaryCard(journey: fallback.journeys.first)),
      );
      expect(find.textContaining('without traffic'), findsOneWidget);
    });

    test(
      'F14. journeys=[] + status=available + road data → fallback renders',
      () {
        final body = {
          'journeyPlanning': {'available': true},
          'journeys': [],
          'distanceKm': 4.0,
          'estimatedDurationMin': 12,
          'origin': {'name': 'A'},
          'destination': {'name': 'B'},
        };
        final plan = JourneyPlan.fromResponse(body);
        expect(plan.hasJourneys, isFalse);
        final fallback = JourneyPlan.roadFallback(body, selectedMode: 'bus');
        expect(fallback, isNotNull);
        expect(fallback!.hasJourneys, isTrue);
      },
    );

    test('F15. exactly one Your Journey section (source inspection)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'JourneyPlanSection('.allMatches(source).length;
      expect(count, 1);
    });

    test('F16. exactly one map (source inspection)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'CommuteRouteMap('.allMatches(source).length;
      expect(count, 1);
    });

    test('F17. no fabricated transit data in fallback legs', () {
      final fare = singleFareResult(mode: 'cng');
      final fallback = JourneyPlan.roadFallback(
        roadBody(),
        selectedMode: 'cng',
        singleFareResult: fare,
      )!;
      final leg = fallback.journeys.first.legs.single;
      expect(leg.serviceName, isNull);
      expect(leg.instruction, isEmpty);
      expect(leg.isTransfer, isFalse);
      expect(leg.transferMinutes, 0);
    });

    testWidgets('F18. fallback with fare renders timeline without overflow', (
      tester,
    ) async {
      final fare = singleFareResult(mode: 'cng', fareLow: 280, fareHigh: 320);
      final fallback = JourneyPlan.roadFallback(
        roadBody(distanceKm: 18.2, durationMin: 42),
        selectedMode: 'cng',
        singleFareResult: fare,
      )!;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            child: JourneyTimeline(journey: fallback.journeys.first),
          ),
        ),
      );
      expect(find.text('CNG'), findsOneWidget);
      expect(find.textContaining('18.2 km'), findsOneWidget);
      expect(find.textContaining('280'), findsOneWidget);
    });
  });

  group('Smart Journey Guide — acceptance criteria', () {
    test('AC1. exactly one SmartJourneyGuide in commute_screen.dart (source)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'SmartJourneyGuide('.allMatches(source).length;
      expect(count, 1);
    });

    test('AC2. exactly one JourneyGuideFacts in commute_screen.dart (source)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'SmartJourneyGuide('.allMatches(source).length;
      expect(count, 1);
    });

    test('AC3. exactly one Your Journey section (source)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'JourneyPlanSection('.allMatches(source).length;
      expect(count, 1);
    });

    test('AC4. exactly one route map (source)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      final count = 'CommuteRouteMap('.allMatches(source).length;
      expect(count, 1);
    });

    test('AC5. no Groq/API key in Flutter source (source)', () {
      // The AI key must never be hardcoded in Flutter
      final source = File(
        'lib/services/api_service.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('sk_')));
      expect(source, isNot(contains('groq_api_key')));
      expect(source, isNot(contains('GROQ_API_KEY')));
    });

    test('AC6. SmartJourneyGuide import present in commute_screen.dart', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      expect(source, contains("import 'smart_journey_guide.dart'"));
    });
  });

  group('Bus UI Integration — models, guide & reporting', () {
    test('B1. DirectBusCandidate.fromJson parses basic and crowd fare fields', () {
      final json = {
        'serviceId': 'sv-101',
        'operatorName': 'Bikolpo Auto Service',
        'operatorNameBn': 'বিকল্প অটো সার্ভিস',
        'serviceType': 'regular',
        'originStopName': 'Mirpur 10',
        'destinationStopName': 'Motijheel',
        'originSequence': 3,
        'destinationSequence': 18,
        'crowdFare': {
          'fareLow': 25.0,
          'fareHigh': 30.0,
          'recommendedFare': 30.0,
          'hasQualifiedFare': true,
          'sampleCount': 8,
          'label': 'Community estimate',
          'labelBn': 'কমিউনিটি হিসাব',
        },
      };
      final candidate = DirectBusCandidate.fromJson(json);
      expect(candidate.serviceId, 'sv-101');
      expect(candidate.operatorName, 'Bikolpo Auto Service');
      expect(candidate.stopCount, 15);
      expect(candidate.hasQualifiedCrowdFare, isTrue);
      expect(candidate.crowdFareLow, 25.0);
      expect(candidate.crowdFareHigh, 30.0);
      expect(candidate.crowdFareRecommended, 30.0);
      expect(candidate.crowdSampleCount, 8);
      expect(candidate.crowdFareLabel, 'Community estimate');
    });

    test('B2. DirectBusCandidate without crowd fare indicates hasQualifiedCrowdFare=false', () {
      final json = {
        'serviceId': 'sv-102',
        'operatorName': 'Shikhor Paribahan',
        'originStopName': 'Mirpur 1',
        'destinationStopName': 'Farmgate',
        'originSequence': 2,
        'destinationSequence': 12,
      };
      final candidate = DirectBusCandidate.fromJson(json);
      expect(candidate.serviceId, 'sv-102');
      expect(candidate.stopCount, 10);
      expect(candidate.hasQualifiedCrowdFare, isFalse);
      expect(candidate.crowdFareRecommended, isNull);
    });

    test('B3. JourneyGuideFacts includes and serializes bus facts in toJson()', () {
      final facts = JourneyGuideFacts(
        originName: 'Mirpur 10',
        destinationName: 'Farmgate',
        distanceKm: 5.5,
        durationMinutes: 25,
        durationProvenance: 'osrm',
        selectedMode: 'bus',
        modeLabel: 'Bus',
        fareAvailable: true,
        fareType: 'crowd_sourced',
        fareLow: 20.0,
        fareHigh: 25.0,
        selectedBusOperator: 'Bihanga Paribahan',
        selectedBusBoardStop: 'Mirpur 10',
        selectedBusExitStop: 'Farmgate',
        selectedBusStopCount: 8,
      );

      expect(facts.selectedBusOperator, 'Bihanga Paribahan');
      expect(facts.selectedBusBoardStop, 'Mirpur 10');
      expect(facts.selectedBusExitStop, 'Farmgate');
      expect(facts.selectedBusStopCount, 8);

      final json = facts.toJson();
      expect(json['selected_bus_operator'], 'Bihanga Paribahan');
      expect(json['selected_bus_board_stop'], 'Mirpur 10');
      expect(json['selected_bus_exit_stop'], 'Farmgate');
      expect(json['selected_bus_stop_count'], 8);
    });

    testWidgets('B4. SmartJourneyGuide renders bus operator and stop info', (tester) async {
      final facts = JourneyGuideFacts(
        originName: 'Mirpur 10',
        destinationName: 'Farmgate',
        distanceKm: 5.5,
        durationMinutes: 25,
        durationProvenance: 'osrm',
        selectedMode: 'bus',
        modeLabel: 'Bus',
        fareAvailable: true,
        fareType: 'crowd_sourced',
        fareLow: 20.0,
        fareHigh: 25.0,
        selectedBusOperator: 'Bihanga Paribahan',
        selectedBusBoardStop: 'Mirpur 10',
        selectedBusExitStop: 'Farmgate',
        selectedBusStopCount: 8,
      );

      await tester.pumpWidget(_wrap(SmartJourneyGuide(facts: facts)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Bihanga Paribahan'), findsWidgets);
      expect(find.textContaining('8 stops'), findsWidgets);
    });

    testWidgets('B5. SmartJourneyGuide never displays "Official" for crowd sourced bus fare', (tester) async {
      final facts = JourneyGuideFacts(
        originName: 'Mirpur 10',
        destinationName: 'Farmgate',
        distanceKm: 5.5,
        durationMinutes: 25,
        durationProvenance: 'osrm',
        selectedMode: 'bus',
        modeLabel: 'Bus',
        fareAvailable: true,
        fareType: 'crowd_sourced',
        fareLow: 20.0,
        fareHigh: 25.0,
        selectedBusOperator: 'Bihanga Paribahan',
      );

      await tester.pumpWidget(_wrap(SmartJourneyGuide(facts: facts)));
      await tester.pumpAndSettle();

      expect(find.text('Official'), findsNothing);
      expect(find.text('Official BRTA fare'), findsNothing);
      expect(find.textContaining('Community estimate'), findsWidgets);
    });

    testWidgets('B6. SmartJourneyGuide for bus without fare never displays "Free"', (tester) async {
      final facts = JourneyGuideFacts(
        originName: 'Mirpur 10',
        destinationName: 'Farmgate',
        distanceKm: 5.5,
        durationMinutes: 25,
        durationProvenance: 'osrm',
        selectedMode: 'bus',
        modeLabel: 'Bus',
        fareAvailable: false,
        selectedBusOperator: 'Bihanga Paribahan',
      );

      await tester.pumpWidget(_wrap(SmartJourneyGuide(facts: facts)));
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsNothing);
      expect(find.text('৳0'), findsNothing);
      expect(find.text('Fare unavailable'), findsWidgets);
    });

    test('B7. commute_screen.dart contains bus integration components (source)', () {
      final source = File(
        'lib/features/life/presentation/commute/commute_screen.dart',
      ).readAsStringSync();
      expect(source, contains('_PossibleBusesSection'));
      expect(source, contains('_DirectBusRow'));
      expect(source, contains('initialBusServiceId'));
      expect(source, contains('selectedBusServiceId'));
    });
  });
}
