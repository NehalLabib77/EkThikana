import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/life/presentation/commute/journey_models.dart';
import 'package:gochano/features/life/presentation/commute/journey_view.dart';
import 'package:gochano/features/life/presentation/commute/planned_trip_models.dart';

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

  group('StrategyChooser unconstrained rendering', () {
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
}
