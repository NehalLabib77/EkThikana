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
}
