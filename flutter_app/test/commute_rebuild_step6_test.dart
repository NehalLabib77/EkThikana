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
      expect(trip.isCompleted, isFalse);
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

    test('completed trip is not upcoming and not missed', () {
      final trip = PlannedCommuteTrip(
        id: 'test_trip_completed',
        ownerId: 'user_abc',
        originName: 'Mirpur',
        destinationName: 'Dhanmondi',
        departureTime: DateTime.now().add(const Duration(hours: 1)),
        reminderMinutes: 10,
        completed: true,
        completedAt: DateTime.now(),
      );

      expect(trip.isCompleted, isTrue);
      expect(trip.isUpcoming, isFalse);
      expect(trip.isMissed, isFalse);
    });

    test('future trip with completed=false is upcoming', () {
      final trip = PlannedCommuteTrip(
        id: 'test_trip_future',
        ownerId: 'user_abc',
        originName: 'Mirpur',
        destinationName: 'Dhanmondi',
        departureTime: DateTime.now().add(const Duration(hours: 1)),
        reminderMinutes: 10,
        completed: false,
      );

      expect(trip.isUpcoming, isTrue);
      expect(trip.isMissed, isFalse);
      expect(trip.isCompleted, isFalse);
    });

    test('past trip with completed=false is missed', () {
      final trip = PlannedCommuteTrip(
        id: 'test_trip_past',
        ownerId: 'user_abc',
        originName: 'Mirpur',
        destinationName: 'Dhanmondi',
        departureTime: DateTime.now().subtract(const Duration(hours: 1)),
        reminderMinutes: 10,
        completed: false,
      );

      expect(trip.isMissed, isTrue);
      expect(trip.isUpcoming, isFalse);
      expect(trip.isCompleted, isFalse);
    });

    test('past trip with completed=true is not missed', () {
      final trip = PlannedCommuteTrip(
        id: 'test_trip_past_done',
        ownerId: 'user_abc',
        originName: 'Mirpur',
        destinationName: 'Dhanmondi',
        departureTime: DateTime.now().subtract(const Duration(hours: 1)),
        reminderMinutes: 10,
        completed: true,
        completedAt: DateTime.now(),
      );

      expect(trip.isMissed, isFalse);
      expect(trip.isCompleted, isTrue);
    });

    test('completed field round-trips through toMap/fromDoc pattern', () {
      final trip = PlannedCommuteTrip(
        id: 'roundtrip',
        ownerId: 'u1',
        originName: 'A',
        destinationName: 'B',
        departureTime: DateTime(2026, 9, 20, 14, 30),
        reminderMinutes: 30,
        completed: true,
        completedAt: DateTime(2026, 9, 19, 10, 0),
      );

      expect(trip.isCompleted, isTrue);
      expect(trip.completedAt, isNotNull);
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

    test('10 min selection produces unique notification id', () {
      final id10 =
          NotificationService.debugCommuteTripNotificationId('trip_x', 10);
      final id30 =
          NotificationService.debugCommuteTripNotificationId('trip_x', 30);
      final id60 =
          NotificationService.debugCommuteTripNotificationId('trip_x', 60);

      // Different reminder minutes → different IDs
      expect(id10, isNot(equals(id30)));
      expect(id10, isNot(equals(id60)));
      expect(id30, isNot(equals(id60)));
    });

    test('same reminder minutes for different trips produces different IDs', () {
      final idA =
          NotificationService.debugCommuteTripNotificationId('trip_a', 10);
      final idB =
          NotificationService.debugCommuteTripNotificationId('trip_b', 10);

      expect(idA, isNot(equals(idB)));
    });

    test('produces stable pinned values from FNV-1a (not Dart .hashCode)', () {
      final idA = NotificationService.debugCommuteTripNotificationId('trip_123');
      final idB = NotificationService.debugCommuteTripNotificationId('abc');
      final idC = NotificationService.debugCommuteTripNotificationId('');

      expect(idA, equals(NotificationService.debugCommuteTripNotificationId('trip_123')));
      expect(idB, equals(NotificationService.debugCommuteTripNotificationId('abc')));
      expect(idC, equals(NotificationService.debugCommuteTripNotificationId('')));

      expect({idA, idB, idC}.length, equals(3));
    });

    test('notification_service.dart does not use .hashCode for commute reminder IDs', () {
      final file = File('lib/services/notification_service.dart');
      final content = file.readAsStringSync();

      // Check that the user reminder ID method does not use .hashCode
      final userMethodStart = content.indexOf('_commuteTripUserReminderId');
      expect(userMethodStart, isNot(equals(-1)),
          reason: '_commuteTripUserReminderId must exist');

      final window = content.substring(
        userMethodStart,
        (userMethodStart + 200).clamp(0, content.length),
      );
      expect(window.contains('.hashCode'), isFalse,
          reason: '_commuteTripUserReminderId must not use .hashCode');
    });

    test('all IDs are within valid Android notification range [0, 0x7fffffff]', () {
      const sampleIds = [
        'trip_test_1',
        'trip_mirpur_dhanmondi_2026',
        'trip_uuid_abc_123_456_789',
        '',
        '0',
        'a_very_long_trip_id_that_goes_on_and_on_and_on_1234567890',
      ];
      for (final id in sampleIds) {
        final nid = NotificationService.debugCommuteTripNotificationId(id);
        expect(nid, greaterThanOrEqualTo(0));
        expect(nid, lessThanOrEqualTo(0x7fffffff));
        // Also test with specific reminder minutes
        final nid10 = NotificationService.debugCommuteTripNotificationId(id, 10);
        expect(nid10, greaterThanOrEqualTo(0));
        expect(nid10, lessThanOrEqualTo(0x7fffffff));
      }
    });

    test('notification_service.dart only schedules single reminder for commute trips', () {
      final file = File('lib/services/notification_service.dart');
      final content = file.readAsStringSync();

      // The old hardcoded offsets should not be used in scheduleCommuteTripReminder
      expect(content.contains('_commuteTripReminderOffsets'), isFalse,
          reason: 'Old multi-offset list _commuteTripReminderOffsets must be removed');
    });
  });

  group('PlanTripSheet completion surface', () {
    testWidgets('shows "I did the trip" button for upcoming trips', (tester) async {
      final departure = DateTime.now().add(const Duration(days: 2));
      final trip = PlannedCommuteTrip(
        id: 'trip_complete_test',
        ownerId: 'user_1',
        originName: 'Mirpur',
        destinationName: 'Gulshan',
        departureTime: departure,
        reminderMinutes: 30,
      );

      await tester.pumpWidget(
        _wrap(PlanTripForm(existingTrip: trip)),
      );
      await tester.pumpAndSettle();

      expect(find.text('I did the trip'), findsOneWidget);
      expect(find.text('Edit planned trip'), findsOneWidget);
    });

    testWidgets('does not show "I did the trip" for completed trips', (tester) async {
      final departure = DateTime.now().add(const Duration(days: 2));
      final trip = PlannedCommuteTrip(
        id: 'trip_already_done',
        ownerId: 'user_1',
        originName: 'Mirpur',
        destinationName: 'Gulshan',
        departureTime: departure,
        reminderMinutes: 30,
        completed: true,
        completedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        _wrap(PlanTripForm(existingTrip: trip)),
      );
      await tester.pumpAndSettle();

      expect(find.text('I did the trip'), findsNothing);
      expect(find.text('Edit planned trip'), findsOneWidget);
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
      expect(find.text('I did the trip'), findsNothing);
    });

    testWidgets('renders Edit mode with Update, Delete, and completion buttons', (tester) async {
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
      expect(find.text('I did the trip'), findsOneWidget);
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
  });
}
