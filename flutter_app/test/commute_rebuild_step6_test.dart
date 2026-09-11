import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/life/presentation/commute/journey_models.dart';
import 'package:gochano/features/life/presentation/commute/journey_view.dart';
import 'package:gochano/features/life/presentation/commute/plan_trip_sheet.dart';
import 'package:gochano/features/life/presentation/commute/planned_trip_models.dart';
import 'package:gochano/services/notification_service.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: child,
      ),
    ),
  );
}

void main() {
  group('PlannedCommuteTrip model', () {
    test('serializes to map and calculates reminderTime', () {
      final departure = DateTime.now().add(const Duration(hours: 2));
      final trip = PlannedCommuteTrip(
        id: 'test_trip_1',
        ownerId: 'user_abc',
        originName: 'Mirpur 10',
        destinationName: 'Dhanmondi 27',
        departureTime: departure,
        reminderMinutes: 30,
      );

      expect(trip.isUpcoming, isTrue);
      expect(trip.reminderTime, departure.subtract(const Duration(minutes: 30)));

      final map = trip.toMap();
      expect(map['originName'], 'Mirpur 10');
      expect(map['destinationName'], 'Dhanmondi 27');
      expect(map['reminderMinutes'], 30);
    });

    test('reminderTime is null when reminderMinutes <= 0', () {
      final trip = PlannedCommuteTrip(
        id: 'test_trip_2',
        ownerId: 'user_abc',
        originName: 'Uttara',
        destinationName: 'Motijheel',
        departureTime: DateTime.now().add(const Duration(hours: 1)),
        reminderMinutes: 0,
      );

      expect(trip.reminderTime, isNull);
    });
  });

  group('StrategyChooser layout and IntrinsicHeight audit', () {
    test('journey_view.dart does not use IntrinsicHeight or CrossAxisAlignment.stretch in _StrategyChooser', () {
      final file = File('lib/features/life/presentation/commute/journey_view.dart');
      final content = file.readAsStringSync();

      expect(content.contains('class _StrategyChooser'), isTrue);
      final chooserSection = content.split('class _StrategyChooser')[1].split('class ')[0];
      expect(chooserSection.contains('IntrinsicHeight'), isFalse,
          reason: '_StrategyChooser must never use IntrinsicHeight');
      expect(chooserSection.contains('CrossAxisAlignment.stretch'), isFalse,
          reason: '_StrategyChooser must use natural CrossAxisAlignment.start');
    });

    testWidgets('renders in an unconstrained scroll view without layout errors', (tester) async {
      final plan = JourneyPlan.fromResponse({
        'journeyPlanning': {'available': true},
        'journeys': [
          {
            'objectives': ['recommended'],
            'category': 'recommended',
            'origin': 'Mirpur 10',
            'destination': 'Farmgate',
            'totalFareTk': 30.0,
            'totalDurationMinutes': 25,
            'totalDistanceKm': 6.1,
            'totalWalkKm': 0.2,
            'transfers': 1,
            'modeSummary': ['Metro'],
            'fareCertainty': 'official',
            'fareCertaintyLabel': 'Official',
            'fareDeltaTk': 0,
            'durationDeltaMinutes': 0,
            'legs': [],
          },
          {
            'objectives': ['cheapest'],
            'category': 'cheapest',
            'origin': 'Mirpur 10',
            'destination': 'Farmgate',
            'totalFareTk': 15.0,
            'totalDurationMinutes': 45,
            'totalDistanceKm': 6.5,
            'totalWalkKm': 0.5,
            'transfers': 0,
            'modeSummary': ['Bus'],
            'fareCertainty': 'official',
            'fareCertaintyLabel': 'Official',
            'fareDeltaTk': -15,
            'durationDeltaMinutes': 20,
            'legs': [],
          },
        ],
      });

      // Pumping inside an unbounded ListView / SingleChildScrollView
      await tester.pumpWidget(_wrap(JourneyPlanSection(plan: plan, hideMap: true)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Recommended'), findsWidgets);
      expect(find.textContaining('Cheapest'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Planned commute trip notification policy', () {
    test('generates deterministic positive integer notification id per tripId', () {
      final id1 = NotificationService.debugCommuteTripNotificationId('trip_123');
      final id2 = NotificationService.debugCommuteTripNotificationId('trip_123');
      final id3 = NotificationService.debugCommuteTripNotificationId('trip_456');

      expect(id1, equals(id2));
      expect(id1, isNonNegative);
      expect(id1, isNot(equals(id3)));
    });
  });

  group('PlanTripSheet edit and delete surface', () {
    testWidgets('renders Create mode with Save button when existingTrip is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlanTripForm(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plan a future trip'), findsOneWidget);
      expect(find.text('Save planned trip'), findsOneWidget);
      expect(find.text('Delete trip'), findsNothing);
    });

    testWidgets('renders Edit mode with Update and Delete buttons when existingTrip is provided', (tester) async {
      final departure = DateTime.now().add(const Duration(days: 2));
      final trip = PlannedCommuteTrip(
        id: 'trip_edit_test',
        ownerId: 'user_1',
        originName: 'Dhanmondi',
        destinationName: 'Gulshan',
        departureTime: departure,
        reminderMinutes: 30,
      );

      await tester.pumpWidget(
        _wrap(
          PlanTripForm(existingTrip: trip),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit planned trip'), findsOneWidget);
      expect(find.text('Dhanmondi'), findsOneWidget);
      expect(find.text('Gulshan'), findsOneWidget);
      expect(find.text('Update trip'), findsOneWidget);
      expect(find.text('Delete trip'), findsOneWidget);
    });
  });

  group('Firestore rules contract for planned_commute_trips', () {
    test('firestore.rules contains owner-only rules for planned_commute_trips', () {
      final rulesFile = File('../firebase/firestore.rules');
      if (rulesFile.existsSync()) {
        final rules = rulesFile.readAsStringSync();
        expect(rules.contains('match /planned_commute_trips/{id}'), isTrue);
        expect(rules.contains('allow create: if ownedCreate();'), isTrue);
        expect(rules.contains('allow read, delete: if ownedReadDelete();'), isTrue);
        expect(rules.contains('allow update: if ownedUpdate();'), isTrue);
      }
    });
  });

  group('Commute fallback behavior and alternatives', () {
    test('dataset_unavailable or plannerError yields non-null fallback plan without crash', () {
      final response = {
        'journeyPlanning': {
          'available': false,
          'reason': 'dataset_unavailable',
        },
        'journeys': [],
      };
      final plan = JourneyPlan.fromResponse(response);
      expect(plan.status, equals(JourneyPlanningStatus.datasetUnavailable));
      expect(plan.hasJourneys, isFalse);
    });

    test('outside_network_coverage correctly captures off-network endpoints', () {
      final response = {
        'journeyPlanning': {
          'available': false,
          'reason': 'outside_network_coverage',
          'outsideCoverage': ['origin', 'destination'],
          'coverageRadiusKm': 5.0,
        },
        'journeys': [],
      };
      final plan = JourneyPlan.fromResponse(response);
      expect(plan.status, equals(JourneyPlanningStatus.outsideCoverage));
      expect(plan.outsideCoverage, contains('origin'));
      expect(plan.outsideCoverage, contains('destination'));
      expect(plan.coverageRadiusKm, equals(5.0));
    });

    testWidgets('renders unavailable explanation banner instead of blocking network crash', (tester) async {
      final plan = JourneyPlan.fromResponse({
        'journeyPlanning': {
          'available': false,
          'reason': 'dataset_unavailable',
        },
        'journeys': [],
      });
      await tester.pumpWidget(_wrap(JourneyPlanSection(plan: plan, hideMap: true)));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Transport network is temporarily unavailable'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('displays up to 3 alternatives in StrategyChooser and updates selection on tap', (tester) async {
      int selectedIdx = 0;
      final plan = JourneyPlan.fromResponse({
        'journeyPlanning': {'available': true},
        'journeys': [
          {
            'objectives': ['recommended'],
            'category': 'recommended',
            'origin': 'Mirpur 10',
            'destination': 'Motijheel',
            'totalFareTk': 50.0,
            'totalDurationMinutes': 35,
            'totalDistanceKm': 12.0,
            'totalWalkKm': 0.4,
            'transfers': 1,
            'modeSummary': ['Metro'],
            'fareCertainty': 'official',
            'fareCertaintyLabel': 'Official',
            'fareDeltaTk': 0,
            'durationDeltaMinutes': 0,
            'legs': [],
          },
          {
            'objectives': ['cheapest'],
            'category': 'cheapest',
            'origin': 'Mirpur 10',
            'destination': 'Motijheel',
            'totalFareTk': 30.0,
            'totalDurationMinutes': 60,
            'totalDistanceKm': 13.0,
            'totalWalkKm': 0.8,
            'transfers': 0,
            'modeSummary': ['Bus'],
            'fareCertainty': 'official',
            'fareCertaintyLabel': 'Official',
            'fareDeltaTk': -20,
            'durationDeltaMinutes': 25,
            'legs': [],
          },
          {
            'objectives': ['fastest'],
            'category': 'fastest',
            'origin': 'Mirpur 10',
            'destination': 'Motijheel',
            'totalFareTk': 60.0,
            'totalDurationMinutes': 30,
            'totalDistanceKm': 11.5,
            'totalWalkKm': 0.3,
            'transfers': 1,
            'modeSummary': ['Metro', 'Rickshaw'],
            'fareCertainty': 'calculated',
            'fareCertaintyLabel': 'Calculated',
            'fareDeltaTk': 10,
            'durationDeltaMinutes': -5,
            'legs': [],
          },
        ],
      });

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _wrap(
              JourneyPlanSection(
                plan: plan,
                selectedIndex: selectedIdx,
                onJourneySelected: (index) {
                  setState(() => selectedIdx = index);
                },
                hideMap: true,
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Ensure all 3 options exist
      expect(find.textContaining('Recommended'), findsWidgets);
      expect(find.textContaining('Cheapest'), findsWidgets);
      expect(find.textContaining('Fastest'), findsWidgets);

      // Tap on the 'Cheapest' strategy option
      await tester.tap(find.textContaining('Cheapest').first);
      await tester.pumpAndSettle();

      expect(selectedIdx, equals(1));
    });

    test('deterministic notification ID remains consistent and within 31-bit positive range', () {
      const sampleIds = [
        'trip_test_1',
        'trip_mirpur_dhanmondi_2026',
        'trip_uuid_abc_123_456_789',
        '',
      ];
      for (final id in sampleIds) {
        final nid1 = NotificationService.debugCommuteTripNotificationId(id);
        final nid2 = NotificationService.debugCommuteTripNotificationId(id);
        expect(nid1, equals(nid2));
        expect(nid1, greaterThanOrEqualTo(0));
        expect(nid1, lessThanOrEqualTo(0x7fffffff));
      }
    });
  });
}
