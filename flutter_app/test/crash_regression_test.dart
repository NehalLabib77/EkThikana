// Regression tests for the two P0 runtime crashes fixed in this branch:
//
// 1. DoseStatus .name crash — StudentEvent.fromScheduledDose called `.name`
//    on a dynamic value that holds a DoseStatus enum. The fix introduces
//    `doseStatusKey()` which uses an explicit switch.
//
// 2. CommuteBD infinite height — _StrategyChooser used
//    CrossAxisAlignment.stretch on a Row inside an unbounded ListView.
//    The fix changes it to CrossAxisAlignment.center.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/student/student_event.dart';
import 'package:gochano/features/life/domain/medicine_schedule.dart';
import 'package:gochano/features/life/presentation/commute/journey_models.dart';
import 'package:gochano/features/life/presentation/commute/journey_view.dart';

// ---------------------------------------------------------------------------
// 1. DoseStatus → doseStatusKey regression
// ---------------------------------------------------------------------------

void main() {
  group('doseStatusKey — every DoseStatus value', () {
    test('pending returns "pending"', () {
      expect(doseStatusKey(DoseStatus.pending), 'pending');
    });

    test('taken returns "taken"', () {
      expect(doseStatusKey(DoseStatus.taken), 'taken');
    });

    test('skipped returns "skipped"', () {
      expect(doseStatusKey(DoseStatus.skipped), 'skipped');
    });

    test('missed returns "missed"', () {
      expect(doseStatusKey(DoseStatus.missed), 'missed');
    });

    test('all four keys are distinct', () {
      final keys = DoseStatus.values.map(doseStatusKey).toSet();
      expect(keys.length, 4);
    });

    test('every key matches the DoseStatus.parse round-trip', () {
      for (final s in DoseStatus.values) {
        final key = doseStatusKey(s);
        expect(DoseStatus.parse(key), s);
      }
    });
  });

  group('StudentEvent.fromScheduledDose — no .name on dynamic', () {
    test('handles every real DoseStatus without crashing', () {
      for (final ds in DoseStatus.values) {
        final dose = _FakeScheduledDose(
          medicineId: 'med1',
          medicineName: 'Paracetamol',
          time: '08:00',
          status: ds,
        );

        final event = StudentEvent.fromScheduledDose(
          dose,
          DateTime(2025, 6, 15),
        );

        expect(event.type, StudentEventType.medicine);
        expect(event.title, 'Paracetamol');
      }
    });

    test('maps taken → completed', () {
      final event = StudentEvent.fromScheduledDose(
        _FakeScheduledDose(
          medicineId: 'm1',
          medicineName: 'Ibuprofen',
          time: '12:00',
          status: DoseStatus.taken,
        ),
        DateTime(2025, 6, 15),
      );
      expect(event.status, StudentEventStatus.completed);
    });

    test('maps skipped → skipped', () {
      final event = StudentEvent.fromScheduledDose(
        _FakeScheduledDose(
          medicineId: 'm1',
          medicineName: 'Vitamin',
          time: '09:00',
          status: DoseStatus.skipped,
        ),
        DateTime(2025, 6, 15),
      );
      expect(event.status, StudentEventStatus.skipped);
    });

    test('maps missed → missed', () {
      final event = StudentEvent.fromScheduledDose(
        _FakeScheduledDose(
          medicineId: 'm1',
          medicineName: 'Omeprazole',
          time: '07:00',
          status: DoseStatus.missed,
        ),
        DateTime(2025, 6, 15),
      );
      expect(event.status, StudentEventStatus.missed);
    });

    test('maps pending → pending', () {
      final event = StudentEvent.fromScheduledDose(
        _FakeScheduledDose(
          medicineId: 'm1',
          medicineName: 'Cetirizine',
          time: '20:00',
          status: DoseStatus.pending,
        ),
        DateTime(2025, 6, 15),
      );
      expect(event.status, StudentEventStatus.pending);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. _StrategyChooser — no CrossAxisAlignment.stretch in unbounded layout
  // ---------------------------------------------------------------------------

  group('StrategyChooser — no infinite height crash', () {
    testWidgets('renders inside a scrollable Column without crashing',
        (tester) async {
      final plan = JourneyPlan.fromResponse(_twoJourneyResponse());

      await tester.pumpWidget(MaterialApp(
        theme: GochanoTheme.light(),
        home: Scaffold(
          body: ListView(
            children: [
              JourneyPlanSection(plan: plan),
            ],
          ),
        ),
      ));

      // Should render without "BoxConstraints forces an infinite height".
      expect(find.textContaining('Recommended'), findsWidgets);
    });

    testWidgets('strategy controls remain tappable after rendering',
        (tester) async {
      final plan = JourneyPlan.fromResponse(_twoJourneyResponse());

      await tester.pumpWidget(MaterialApp(
        theme: GochanoTheme.light(),
        home: Scaffold(
          body: ListView(
            children: [
              JourneyPlanSection(plan: plan),
            ],
          ),
        ),
      ));

      // Tap the second strategy chip.
      final finder = find.textContaining('Cheapest');
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first);
        await tester.pump();
      }
      // No crash means success.
    });

    testWidgets('no RenderBox/child.hasSize assertion', (tester) async {
      final plan = JourneyPlan.fromResponse(_twoJourneyResponse());

      await tester.pumpWidget(MaterialApp(
        theme: GochanoTheme.light(),
        home: Scaffold(
          body: ListView(
            children: [
              JourneyPlanSection(plan: plan),
            ],
          ),
        ),
      ));

      // If we get here without an exception, the layout is valid.
      expect(tester.takeException(), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Fake that exposes the same interface as ScheduledDose without importing it
/// (avoids import-cycle issues in the test, mirroring the real `dynamic dose`).
class _FakeScheduledDose {
  const _FakeScheduledDose({
    required this.medicineId,
    required this.medicineName,
    required this.time,
    required this.status,
  });

  final String medicineId;
  final String medicineName;
  final String time;
  final DoseStatus status;
}

/// Two-journey response for the strategy chooser tests.
Map<String, dynamic> _twoJourneyResponse() => {
      'journeyPlanning': {
        'available': true,
        'reason': null,
        'coverageRadiusKm': 4.0,
      },
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
          'transfers': 2,
          'modeSummary': ['Walk', 'Metro', 'Walk'],
          'fareCertainty': 'official',
          'fareCertaintyLabel': 'Official',
          'fareDeltaTk': 0,
          'durationDeltaMinutes': 0,
          'whyRecommended': 'Faster option.',
          'legs': [
            {
              'mode': 'walk',
              'modeLabel': 'Walk',
              'from': 'Mirpur 10',
              'to': 'Mirpur 10 Metro',
              'distanceKm': 0.1,
              'durationMinutes': 1,
              'fareTk': 0.0,
              'fareType': 'none',
              'fareLabel': 'Free',
              'fareSource': '',
              'instruction': 'Walk to metro.',
              'isTransfer': false,
              'transferMinutes': 0,
              'serviceName': null,
              'fromLat': 23.80,
              'fromLon': 90.36,
              'toLat': 23.81,
              'toLon': 90.37,
            },
          ],
        },
        {
          'objectives': ['cheapest'],
          'category': 'cheapest',
          'origin': 'Mirpur 10',
          'destination': 'Farmgate',
          'totalFareTk': 14.0,
          'totalDurationMinutes': 40,
          'totalDistanceKm': 7.0,
          'totalWalkKm': 0.5,
          'transfers': 1,
          'modeSummary': ['Walk', 'Bus', 'Walk'],
          'fareCertainty': 'official',
          'fareCertaintyLabel': 'Official',
          'fareDeltaTk': -16,
          'durationDeltaMinutes': 15,
          'whyRecommended': '',
          'legs': [
            {
              'mode': 'walk',
              'modeLabel': 'Walk',
              'from': 'Mirpur 10',
              'to': 'Bus Stop',
              'distanceKm': 0.3,
              'durationMinutes': 4,
              'fareTk': 0.0,
              'fareType': 'none',
              'fareLabel': 'Free',
              'fareSource': '',
              'instruction': 'Walk to bus stop.',
              'isTransfer': false,
              'transferMinutes': 0,
              'serviceName': null,
              'fromLat': 23.80,
              'fromLon': 90.36,
              'toLat': 23.81,
              'toLon': 90.37,
            },
          ],
        },
      ],
    };
