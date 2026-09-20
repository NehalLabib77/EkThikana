// Offline reminder scheduling, deterministic IDs, and self-healing tests.
// Pins the local-first engine guarantees without requiring network or Firebase.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/models/local_reminder.dart';
import 'package:gochano/services/local_reminder_store.dart';
import 'package:gochano/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testManifestFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_sched_test_');
    testManifestFile = File('${tempDir.path}/reminders_manifest.json');
    LocalReminderStore.instance.resetForTesting();
    LocalReminderStore.instance.setTestFile(testManifestFile);
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Offline Deterministic Notification IDs', () {
    test(
      'all reminder categories produce valid non-negative 31-bit integers',
      () {
        const taskId = 'task_algebra_101';
        const medId = 'med_paracetamol_500';
        const tripId = 'trip_mirpur_to_motijheel';
        const expenseId = 'dena_pawna_karim_500';
        const customId = 'custom_remind_water_plants';

        // 1. Task / Assignment IDs (across all 6 lead-time offsets)
        const taskOffsets = [90, 60, 30, 10, 0, -30];
        for (final offset in taskOffsets) {
          final id = NotificationService.debugTaskNotificationId(
            taskId,
            offset,
          );
          expect(id, isNonNegative);
          expect(id, lessThan(0x80000000));
        }

        // 2. Medicine IDs (across all 5 dose/follow-up offsets)
        const medOffsets = [0, 30, 60, 90, 120];
        for (final offset in medOffsets) {
          final id = NotificationService.debugMedicineNotificationId(
            medId,
            '08:00',
            offset,
          );
          expect(id, isNonNegative);
          expect(id, lessThan(0x80000000));
        }

        // 3. Commute Trip IDs (for 60, 30, 10 min lead times)
        for (final leadTime in [60, 30, 10]) {
          final id = NotificationService.debugCommuteTripNotificationId(
            tripId,
            leadTime,
          );
          expect(id, isNonNegative);
          expect(id, lessThan(0x80000000));
        }

        // 4. Expense Due ID
        final expenseNotifId =
            NotificationService.debugExpenseDueNotificationId(expenseId, 0);
        expect(expenseNotifId, isNonNegative);
        expect(expenseNotifId, lessThan(0x80000000));

        // 5. Custom Reminder ID
        final customNotifId =
            NotificationService.debugCustomReminderNotificationId(customId);
        expect(customNotifId, isNonNegative);
        expect(customNotifId, lessThan(0x80000000));
      },
    );

    test(
      'deterministic FNV-1a IDs remain identical across simulated process restarts',
      () {
        const taskId = 'persisted_offline_task_4455';
        const medId = 'persisted_offline_med_8899';
        const expenseId = 'persisted_offline_due_1122';

        final taskFirst = NotificationService.debugTaskNotificationId(
          taskId,
          30,
        );
        final medFirst = NotificationService.debugMedicineNotificationId(
          medId,
          '14:00',
          0,
        );
        final dueFirst = NotificationService.debugExpenseDueNotificationId(
          expenseId,
          0,
        );

        // Simulate re-creation from fresh string memory allocation
        final freshTask = String.fromCharCodes(taskId.codeUnits);
        final freshMed = String.fromCharCodes(medId.codeUnits);
        final freshDue = String.fromCharCodes(expenseId.codeUnits);

        expect(
          NotificationService.debugTaskNotificationId(freshTask, 30),
          equals(taskFirst),
        );
        expect(
          NotificationService.debugMedicineNotificationId(freshMed, '14:00', 0),
          equals(medFirst),
        );
        expect(
          NotificationService.debugExpenseDueNotificationId(freshDue, 0),
          equals(dueFirst),
        );
      },
    );

    test('different items produce distinct IDs without collision', () {
      final task1 = NotificationService.debugTaskNotificationId('task_1', 0);
      final task2 = NotificationService.debugTaskNotificationId('task_2', 0);
      final med1 = NotificationService.debugMedicineNotificationId(
        'med_1',
        '08:00',
        0,
      );
      final due1 = NotificationService.debugExpenseDueNotificationId(
        'due_1',
        0,
      );
      final custom1 = NotificationService.debugCustomReminderNotificationId(
        'custom_1',
      );

      final ids = {task1, task2, med1, due1, custom1};
      expect(ids.length, equals(5));
    });
  });

  group('Offline Reminder State & Reconciliation Guarantees', () {
    test('local store records and updates task status offline', () async {
      final reminder = LocalReminder(
        id: 'task_math_hw',
        ownerItemId: 'task_math_hw',
        type: LocalReminderType.assignment,
        title: 'Math Homework Assignment',
        scheduledAt: DateTime.now().add(const Duration(hours: 4)),
        status: LocalReminderStatus.pending,
        createdAt: DateTime.now(),
      );
      await LocalReminderStore.instance.save(reminder);

      expect(
        LocalReminderStore.instance.getById('task_math_hw')?.status,
        equals(LocalReminderStatus.pending),
      );

      // Simulate inline completion (e.g. from Done action)
      await LocalReminderStore.instance.updateStatus(
        'task_math_hw',
        LocalReminderStatus.completed,
      );

      final completed = LocalReminderStore.instance.getById('task_math_hw');
      expect(completed?.status, equals(LocalReminderStatus.completed));
      expect(completed?.completedAt, isNotNull);
    });

    test(
      'reconcilable reminders filter out cancelled items and keep daily medicine',
      () {
        final now = DateTime.now();
        final items = [
          LocalReminder(
            id: 'item_1',
            ownerItemId: 'owner_1',
            type: LocalReminderType.task,
            title: 'Future Task',
            scheduledAt: now.add(const Duration(hours: 2)),
            status: LocalReminderStatus.pending,
            createdAt: now,
          ),
          LocalReminder(
            id: 'item_2',
            ownerItemId: 'owner_2',
            type: LocalReminderType.task,
            title: 'Cancelled Task',
            scheduledAt: now.add(const Duration(hours: 3)),
            status: LocalReminderStatus.cancelled,
            createdAt: now,
          ),
          LocalReminder(
            id: 'item_3',
            ownerItemId: 'owner_3',
            type: LocalReminderType.medicine,
            title: 'Daily Insulin',
            scheduledAt: now.subtract(const Duration(hours: 1)),
            recurrence: LocalReminderRecurrence.daily,
            status: LocalReminderStatus.completed,
            createdAt: now,
          ),
        ];

        LocalReminderStore.instance.resetForTesting(items);

        final reconcilable = LocalReminderStore.instance
            .getReconcilableReminders();
        expect(reconcilable.length, equals(2));
        final ids = reconcilable.map((r) => r.id).toSet();
        expect(ids.contains('item_1'), isTrue);
        expect(ids.contains('item_2'), isFalse);
        expect(ids.contains('item_3'), isTrue);
      },
    );

    test('NotificationAction and Tap streams are reactive', () {
      NotificationService.taskAction.value = null;
      NotificationService.notificationTap.value = null;

      var taskActionFired = false;
      NotificationService.taskAction.addListener(() {
        if (NotificationService.taskAction.value != null) {
          taskActionFired = true;
        }
      });

      NotificationService.taskAction.value = const TaskNotificationAction(
        action: 'done',
        taskId: 'task_xyz',
        title: 'Task XYZ',
      );
      expect(taskActionFired, isTrue);

      var tapFired = false;
      NotificationService.notificationTap.addListener(() {
        if (NotificationService.notificationTap.value != null) {
          tapFired = true;
        }
      });

      NotificationService.notificationTap.value = const GeneralNotificationTap(
        kind: 'custom',
        id: 'custom_123',
        title: 'Custom Reminder',
      );
      expect(tapFired, isTrue);
    });
  });
}
