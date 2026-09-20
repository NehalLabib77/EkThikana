// Unit tests for LocalReminder model and LocalReminderStore.
// Validates 100% offline persistence, reactive notifiers, CRUD operations,
// status transitions, and self-healing reconciliation manifests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/models/local_reminder.dart';
import 'package:gochano/services/local_reminder_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testManifestFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_reminder_test_');
    testManifestFile = File('${tempDir.path}/reminders_manifest.json');
    LocalReminderStore.instance.resetForTesting();
    LocalReminderStore.instance.setTestFile(testManifestFile);
    await LocalReminderStore.instance.init();
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('LocalReminder Model', () {
    test('serializes and deserializes correctly', () {
      final scheduled = DateTime(2026, 9, 20, 14, 30);
      final created = DateTime(2026, 9, 18, 10, 0);

      final reminder = LocalReminder(
        id: 'task_abc_1',
        ownerItemId: 'task_abc',
        type: LocalReminderType.task,
        title: 'Complete Lab Report',
        body: 'Due in 30 minutes',
        scheduledAt: scheduled,
        offsets: const [90, 60, 30, 10, 0, -30],
        notificationIds: const [100, 101, 102, 103, 104, 105],
        recurrence: LocalReminderRecurrence.none,
        status: LocalReminderStatus.pending,
        payload: const {'subject': 'Physics', 'priority': 'high'},
        createdAt: created,
        updatedAt: created,
        isRead: false,
      );

      final json = reminder.toJson();
      expect(json['id'], equals('task_abc_1'));
      expect(json['type'], equals('task'));
      expect(json['status'], equals('pending'));
      expect(json['offsets'], equals([90, 60, 30, 10, 0, -30]));
      expect(json['notificationIds'], equals([100, 101, 102, 103, 104, 105]));
      expect(json['payload']['subject'], equals('Physics'));

      final restored = LocalReminder.fromJson(json);
      expect(restored.id, equals(reminder.id));
      expect(restored.ownerItemId, equals(reminder.ownerItemId));
      expect(restored.type, equals(LocalReminderType.task));
      expect(restored.title, equals('Complete Lab Report'));
      expect(restored.scheduledAt, equals(scheduled));
      expect(restored.offsets, equals([90, 60, 30, 10, 0, -30]));
      expect(restored.status, equals(LocalReminderStatus.pending));
      expect(restored.isRead, isFalse);
    });

    test('copyWith produces correctly modified immutable copy', () {
      final reminder = LocalReminder(
        id: 'custom_1',
        ownerItemId: 'custom_1',
        type: LocalReminderType.custom,
        title: 'Water plants',
        scheduledAt: DateTime(2026, 9, 19, 8, 0),
        status: LocalReminderStatus.pending,
        createdAt: DateTime.now(),
      );

      final updated = reminder.copyWith(
        status: LocalReminderStatus.completed,
        isRead: true,
      );

      expect(updated.id, equals('custom_1'));
      expect(updated.status, equals(LocalReminderStatus.completed));
      expect(updated.isRead, isTrue);
      expect(reminder.status, equals(LocalReminderStatus.pending));
    });
  });

  group('LocalReminderStore Offline Persistence & CRUD', () {
    test(
      'save, retrieve, and disk persistence work completely offline',
      () async {
        final scheduled = DateTime.now().add(const Duration(hours: 2));
        final reminder = LocalReminder(
          id: 'med_napa_0800',
          ownerItemId: 'med_napa',
          type: LocalReminderType.medicine,
          title: 'Napa 500mg',
          body: '1 tablet after breakfast',
          scheduledAt: scheduled,
          offsets: const [0, 30, 60, 90, 120],
          notificationIds: const [201, 202, 203, 204, 205],
          recurrence: LocalReminderRecurrence.daily,
          status: LocalReminderStatus.pending,
          payload: const {'quantityPerDose': 1.0, 'unit': 'tablet'},
          createdAt: DateTime.now(),
        );

        await LocalReminderStore.instance.save(reminder);

        // Verify in-memory retrieval
        final fetched = LocalReminderStore.instance.getById('med_napa_0800');
        expect(fetched, isNotNull);
        expect(fetched!.title, equals('Napa 500mg'));
        expect(fetched.type, equals(LocalReminderType.medicine));

        // Verify file persistence on disk
        expect(await testManifestFile.exists(), isTrue);
        final rawJson = await testManifestFile.readAsString();
        expect(rawJson, contains('med_napa_0800'));
        expect(rawJson, contains('Napa 500mg'));

        // Simulate app restart by re-initializing from the same test file
        LocalReminderStore.instance.setTestFile(testManifestFile);
        await LocalReminderStore.instance.init();

        final reloaded = LocalReminderStore.instance.getById('med_napa_0800');
        expect(reloaded, isNotNull);
        expect(reloaded!.title, equals('Napa 500mg'));
        expect(reloaded.recurrence, equals(LocalReminderRecurrence.daily));
      },
    );

    test(
      'updateStatus updates reminder status and completes timestamp',
      () async {
        final reminder = LocalReminder(
          id: 'trip_shabag_1',
          ownerItemId: 'trip_shabag',
          type: LocalReminderType.commuteTrip,
          title: 'Bus to Shahbagh',
          scheduledAt: DateTime.now().add(const Duration(minutes: 45)),
          status: LocalReminderStatus.pending,
          createdAt: DateTime.now(),
        );
        await LocalReminderStore.instance.save(reminder);

        final completedTime = DateTime(2026, 9, 18, 11, 30);
        await LocalReminderStore.instance.updateStatus(
          'trip_shabag_1',
          LocalReminderStatus.completed,
          completedAt: completedTime,
        );

        final updated = LocalReminderStore.instance.getById('trip_shabag_1');
        expect(updated, isNotNull);
        expect(updated!.status, equals(LocalReminderStatus.completed));
        expect(updated.completedAt, equals(completedTime));
      },
    );

    test(
      'updateStatusByOwnerItemId updates all associated reminder slots',
      () async {
        final r1 = LocalReminder(
          id: 'task_xyz_slot1',
          ownerItemId: 'task_xyz',
          type: LocalReminderType.task,
          title: 'Project Submission',
          scheduledAt: DateTime.now().add(const Duration(hours: 1)),
          status: LocalReminderStatus.pending,
          createdAt: DateTime.now(),
        );
        final r2 = LocalReminder(
          id: 'task_xyz_slot2',
          ownerItemId: 'task_xyz',
          type: LocalReminderType.task,
          title: 'Project Submission',
          scheduledAt: DateTime.now().add(const Duration(hours: 2)),
          status: LocalReminderStatus.pending,
          createdAt: DateTime.now(),
        );
        await LocalReminderStore.instance.save(r1);
        await LocalReminderStore.instance.save(r2);

        await LocalReminderStore.instance.updateStatusByOwnerItemId(
          'task_xyz',
          LocalReminderStatus.cancelled,
        );

        expect(
          LocalReminderStore.instance.getById('task_xyz_slot1')?.status,
          equals(LocalReminderStatus.cancelled),
        );
        expect(
          LocalReminderStore.instance.getById('task_xyz_slot2')?.status,
          equals(LocalReminderStatus.cancelled),
        );
      },
    );

    test('delete removes item from memory and disk manifest', () async {
      final reminder = LocalReminder(
        id: 'custom_remove_me',
        ownerItemId: 'custom_remove_me',
        type: LocalReminderType.custom,
        title: 'Temporary item',
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
        status: LocalReminderStatus.pending,
        createdAt: DateTime.now(),
      );
      await LocalReminderStore.instance.save(reminder);
      expect(
        LocalReminderStore.instance.getById('custom_remove_me'),
        isNotNull,
      );

      await LocalReminderStore.instance.delete('custom_remove_me');
      expect(LocalReminderStore.instance.getById('custom_remove_me'), isNull);

      final raw = await testManifestFile.readAsString();
      expect(raw, isNot(contains('custom_remove_me')));
    });

    test('reactive notifiers track reminders list and unread count', () async {
      expect(LocalReminderStore.instance.unreadCountNotifier.value, equals(0));

      final r1 = LocalReminder(
        id: 'unread_1',
        ownerItemId: 'owner_1',
        type: LocalReminderType.task,
        title: 'First task',
        scheduledAt: DateTime.now().add(const Duration(hours: 1)),
        status: LocalReminderStatus.pending,
        createdAt: DateTime.now(),
        isRead: false,
      );
      final r2 = LocalReminder(
        id: 'unread_2',
        ownerItemId: 'owner_2',
        type: LocalReminderType.medicine,
        title: 'Second med',
        scheduledAt: DateTime.now().add(const Duration(hours: 2)),
        status: LocalReminderStatus.pending,
        createdAt: DateTime.now(),
        isRead: false,
      );

      await LocalReminderStore.instance.save(r1);
      await LocalReminderStore.instance.save(r2);

      expect(
        LocalReminderStore.instance.remindersNotifier.value.length,
        equals(2),
      );
      expect(LocalReminderStore.instance.unreadCountNotifier.value, equals(2));

      await LocalReminderStore.instance.markAsRead('unread_1');
      expect(LocalReminderStore.instance.unreadCountNotifier.value, equals(1));

      await LocalReminderStore.instance.markAllAsRead();
      expect(LocalReminderStore.instance.unreadCountNotifier.value, equals(0));
    });

    test(
      'getReconcilableReminders retrieves active pending and daily recurring items',
      () async {
        final futurePending = LocalReminder(
          id: 'rec_future_task',
          ownerItemId: 'rec_future_task',
          type: LocalReminderType.task,
          title: 'Future Task',
          scheduledAt: DateTime.now().add(const Duration(days: 1)),
          status: LocalReminderStatus.pending,
          createdAt: DateTime.now(),
        );
        final pastPending = LocalReminder(
          id: 'rec_past_task',
          ownerItemId: 'rec_past_task',
          type: LocalReminderType.task,
          title: 'Past Task',
          scheduledAt: DateTime.now().subtract(const Duration(days: 1)),
          status: LocalReminderStatus.pending,
          createdAt: DateTime.now(),
        );
        final dailyMedicine = LocalReminder(
          id: 'rec_daily_med',
          ownerItemId: 'rec_daily_med',
          type: LocalReminderType.medicine,
          title: 'Daily Vitamin',
          scheduledAt: DateTime.now().subtract(const Duration(hours: 5)),
          recurrence: LocalReminderRecurrence.daily,
          status: LocalReminderStatus.completed,
          createdAt: DateTime.now(),
        );
        final cancelled = LocalReminder(
          id: 'rec_cancelled',
          ownerItemId: 'rec_cancelled',
          type: LocalReminderType.custom,
          title: 'Cancelled item',
          scheduledAt: DateTime.now().add(const Duration(days: 2)),
          status: LocalReminderStatus.cancelled,
          createdAt: DateTime.now(),
        );

        await LocalReminderStore.instance.save(futurePending);
        await LocalReminderStore.instance.save(pastPending);
        await LocalReminderStore.instance.save(dailyMedicine);
        await LocalReminderStore.instance.save(cancelled);

        final reconcilable = LocalReminderStore.instance
            .getReconcilableReminders();
        final ids = reconcilable.map((r) => r.id).toSet();

        expect(ids.contains('rec_future_task'), isTrue);
        expect(
          ids.contains('rec_daily_med'),
          isTrue,
        ); // daily recurrence is eligible
        expect(ids.contains('rec_cancelled'), isFalse);
      },
    );
  });
}
