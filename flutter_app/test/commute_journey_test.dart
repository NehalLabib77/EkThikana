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
        find.textContaining('transport network could not be loaded'),
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
}
