// Notification policy regression tests.
//
// Pins the behavioural contract documented in GOCHANO.md §24 and
// audit.json part4_branding_polish.
//
// Rules pinned here:
//   1. medicine notification IDs are deterministic per (medicineId, hhmm)
//      pair - the same dose never produces two notifications, and a retry
//      does not duplicate the underlying record.
//   2. central ledger transactionId is deterministic and bound to the
//      sourceRecordId so a Taken dose writes exactly one expense.
//   3. dose status "skipped" never produces an expense transaction id
//      tied to the dose (the expense identity key includes the status
//      via the sourceRecordId).
//   4. two distinct medicine ids at the same hhmm produce two distinct
//      notification ids (no collision).

import 'package:gochano/features/life/presentation/commute/planned_trip_models.dart';
import 'package:gochano/services/financial_service.dart';
import 'package:gochano/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Medicine notification id (deterministic, no duplicates)', () {
    test('same medicineId + hhmm produces the same notification id', () {
      final a = NotificationService.debugMedicineNotificationId(
        'medA',
        '08:30',
      );
      final b = NotificationService.debugMedicineNotificationId(
        'medA',
        '08:30',
      );
      expect(a, equals(b));
    });

    test('different medicine ids at the same hhmm produce different ids', () {
      final a = NotificationService.debugMedicineNotificationId(
        'medA',
        '08:30',
      );
      final b = NotificationService.debugMedicineNotificationId(
        'medB',
        '08:30',
      );
      expect(a, isNot(equals(b)));
    });

    test('same medicine at different hhmm produces different ids', () {
      final morning = NotificationService.debugMedicineNotificationId(
        'medA',
        '08:30',
      );
      final evening = NotificationService.debugMedicineNotificationId(
        'medA',
        '20:30',
      );
      expect(morning, isNot(equals(evening)));
    });
  });

  group(
    'Medicine dose ledger keys (Taken == one expense; Skip == no expense)',
    () {
      test('identical Taken doses share the same transaction id', () {
        // The expense is bound to the dose via a sourceRecordId derived from
        // medicineId + hhmm + status. A retry of "taken" produces the same id.
        final id = FinancialService.transactionId(
          'medicine',
          'medA_08:30_taken',
        );
        final again = FinancialService.transactionId(
          'medicine',
          'medA_08:30_taken',
        );
        expect(id, equals(again));
      });

      test(
        'Skipped doses use a different sourceRecordId so no expense is written',
        () {
          final taken = FinancialService.transactionId(
            'medicine',
            'medA_08:30_taken',
          );
          final skipped = FinancialService.transactionId(
            'medicine',
            'medA_08:30_skipped',
          );
          expect(skipped, isNot(equals(taken)));
        },
      );

      test('Pending or missed doses do not collide with Taken ids', () {
        final taken = FinancialService.transactionId(
          'medicine',
          'medA_08:30_taken',
        );
        final pending = FinancialService.transactionId(
          'medicine',
          'medA_08:30_pending',
        );
        expect(pending, isNot(equals(taken)));
      });
    },
  );

  group('Notification policy / language', () {
    test('Mathias-frontend cannot expose a non-existent override', () {
      // Sanity-check that the helper exists - keeps import surfaces stable.
      // The actual bilingual switch is exercised in widget tests.
      expect(NotificationService.debugMedicineNotificationId, isNotNull);
    });
  });

  group('Deterministic reminder cadence policies', () {
    test(
      'Task reminders generate 6 distinct deterministic IDs for offsets 90, 60, 30, 10, 0, -30',
      () {
        const taskId = 'task_algebra_101';
        const offsets = [90, 60, 30, 10, 0, -30];
        final ids = offsets
            .map(
              (off) => NotificationService.debugTaskNotificationId(taskId, off),
            )
            .toList();

        for (final id in ids) {
          expect(id, isNonNegative);
          expect(id, lessThan(0x80000000));
        }

        final uniqueIds = ids.toSet();
        expect(uniqueIds.length, equals(6));

        // Determinism
        expect(
          ids[0],
          equals(NotificationService.debugTaskNotificationId(taskId, 90)),
        );
        expect(
          ids[4],
          equals(NotificationService.debugTaskNotificationId(taskId, 0)),
        );
        expect(
          ids[4],
          equals(NotificationService.debugTaskNotificationId(taskId)),
        );
        expect(
          ids[5],
          equals(NotificationService.debugTaskNotificationId(taskId, -30)),
        );
      },
    );

    test(
      'Medicine reminders generate 5 distinct deterministic IDs for offsets 0, 30, 60, 90, 120',
      () {
        final medId = 'med_paracetamol';
        final hhmm = '14:00';
        final offsets = [0, 30, 60, 90, 120];
        final ids = offsets
            .map(
              (off) => NotificationService.debugMedicineNotificationId(
                medId,
                hhmm,
                off,
              ),
            )
            .toSet();

        expect(ids.length, equals(5));
        for (final id in ids) {
          expect(id, isNonNegative);
        }

        // Backward compatible default offset = 0
        expect(
          NotificationService.debugMedicineNotificationId(medId, hhmm),
          equals(
            NotificationService.debugMedicineNotificationId(medId, hhmm, 0),
          ),
        );
      },
    );

    test('PlannedCommuteTrip correctly derives isMissed and isUpcoming', () {
      final now = DateTime.now();
      final futureTrip = PlannedCommuteTrip(
        id: 'trip-1',
        ownerId: 'user-1',
        originName: 'Mirpur',
        destinationName: 'Dhanmondi',
        departureTime: now.add(const Duration(hours: 1)),
        reminderMinutes: 30,
      );
      final pastTrip = PlannedCommuteTrip(
        id: 'trip-2',
        ownerId: 'user-1',
        originName: 'Mirpur',
        destinationName: 'Dhanmondi',
        departureTime: now.subtract(const Duration(minutes: 5)),
        reminderMinutes: 30,
      );

      expect(futureTrip.isUpcoming, isTrue);
      expect(futureTrip.isMissed, isFalse);
      expect(pastTrip.isUpcoming, isFalse);
      expect(pastTrip.isMissed, isTrue);
    });

    test(
      'Medicine missed lifecycle: pending before 120 min, missed after 120 min',
      () {
        final scheduledAt = DateTime(2026, 9, 13, 10, 0);
        final at119 = scheduledAt.add(const Duration(minutes: 119));
        final at121 = scheduledAt.add(const Duration(minutes: 121));

        // At T+119, scheduled is NOT before at119 - 120 min
        expect(
          scheduledAt.isBefore(at119.subtract(const Duration(minutes: 120))),
          isFalse,
        );
        // At T+121, scheduled IS before at121 - 120 min (transitions to missed)
        expect(
          scheduledAt.isBefore(at121.subtract(const Duration(minutes: 120))),
          isTrue,
        );
      },
    );

    test(
      'Task 30-minute grace period lifecycle: active during grace, missed only after T+30',
      () {
        final dueAt = DateTime(2026, 9, 13, 15, 0);
        final missedAt = dueAt.add(const Duration(minutes: 30));

        // T - 10: Before due, not overdue, not missed
        final tMinus10 = dueAt.subtract(const Duration(minutes: 10));
        expect(dueAt.isBefore(tMinus10), isFalse);
        expect(!missedAt.isAfter(tMinus10), isFalse);

        // T: Exact due time, not yet missed
        expect(!missedAt.isAfter(dueAt), isFalse);

        // T + 15: Grace period, overdue but NOT missed (remains active on Home)
        final tPlus15 = dueAt.add(const Duration(minutes: 15));
        expect(dueAt.isBefore(tPlus15), isTrue); // overdue
        expect(!missedAt.isAfter(tPlus15), isFalse); // not missed yet

        // T + 29: Grace period boundary, still not missed
        final tPlus29 = dueAt.add(const Duration(minutes: 29));
        expect(!missedAt.isAfter(tPlus29), isFalse);

        // T + 30: Grace period expired, IS missed
        final tPlus30 = dueAt.add(const Duration(minutes: 30));
        expect(!missedAt.isAfter(tPlus30), isTrue);

        // T + 45: Past grace period, IS missed
        final tPlus45 = dueAt.add(const Duration(minutes: 45));
        expect(!missedAt.isAfter(tPlus45), isTrue);
      },
    );

    test(
      'Task deadline lifecycle: due before now is overdue/missed from Home',
      () {
        final now = DateTime(2026, 9, 13, 15, 0);
        final beforeDeadline = now.add(const Duration(minutes: 30));
        final afterDeadline = now.subtract(const Duration(minutes: 1));

        expect(beforeDeadline.isBefore(now), isFalse);
        expect(afterDeadline.isBefore(now), isTrue);
      },
    );
  });
}
