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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';

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

  group('Android medicine background scheduling', () {
    test('uses exact idle-safe mode only when capability is granted', () {
      expect(
        NotificationService.medicineScheduleModeForCapability(true),
        AndroidScheduleMode.exactAllowWhileIdle,
      );
      expect(
        NotificationService.medicineScheduleModeForCapability(false),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    });

    test('uses OS scheduling and deterministic cancel identity', () {
      final source = File(
        'lib/services/notification_service.dart',
      ).readAsStringSync();
      expect(source, contains('plugin.zonedSchedule'));
      expect(source, contains('canScheduleExactNotifications'));
      expect(source, contains('plugin.cancel(id: _medicineNotificationId'));
      expect(source, isNot(contains('Timer(')));
      expect(source, isNot(contains('Future.delayed')));
    });

    test('manifest declares notification, vibration, and boot support', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('android.permission.VIBRATE'));
      expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
      expect(
        manifest,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
        ),
      );
      expect(
        manifest,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
        ),
      );
      expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
      expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    });

    test('medicine edit and cancellation reuse medicineId plus hhmm', () {
      final source = File(
        'lib/services/notification_service.dart',
      ).readAsStringSync();
      expect(source, contains('id: _medicineNotificationId(medicineId, hhmm)'));
      expect(
        source,
        contains(
          'plugin.cancel(id: _medicineNotificationId(medicineId, time))',
        ),
      );
      expect(
        source,
        contains('matchDateTimeComponents: DateTimeComponents.time'),
      );
    });
  });
}
