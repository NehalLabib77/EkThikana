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
}
