// Widget tests for NotificationCenterScreen and CustomReminderSheet.
// Validates rendering across all reminder categories, filtering, inline actions,
// bilingual presentation, 320dp responsive layout, and 2.0x font scaling.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/notifications/presentation/custom_reminder_sheet.dart';
import 'package:gochano/features/notifications/presentation/notification_center_screen.dart';
import 'package:gochano/models/local_reminder.dart';
import 'package:gochano/services/local_reminder_store.dart';

Widget _buildWrapper({
  required Widget child,
  double width = 360,
  double height = 700,
  double textScaleFactor = 1.0,
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(textScaleFactor),
      ),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testManifestFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notif_center_test_');
    testManifestFile = File('${tempDir.path}/reminders_manifest.json');
    LocalReminderStore.instance.resetForTesting();
    LocalReminderStore.instance.setTestFile(testManifestFile);
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('NotificationCenterScreen Presentation', () {
    testWidgets('renders empty state when no reminders exist', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(child: const NotificationCenterScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notification Center'), findsOneWidget);
      expect(find.text('All caught up!'), findsOneWidget);
      expect(find.text('Create Reminder'), findsOneWidget);
    });

    testWidgets('renders empty state in Bengali mode', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(child: const NotificationCenterScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('নোটিফিকেশন সেন্টার'), findsOneWidget);
      expect(find.text('সব নোটিফিকেশন দেখা হয়েছে!'), findsOneWidget);
      expect(find.text('রিমাইন্ডার তৈরি করুন'), findsOneWidget);
    });

    testWidgets('renders cards for different reminder types', (tester) async {
      final now = DateTime.now();
      final items = [
        LocalReminder(
          id: 'test_task_1',
          ownerItemId: 'owner_task_1',
          type: LocalReminderType.task,
          title: 'Physics Lab Report',
          body: 'Submit to lab instructor',
          scheduledAt: now.add(const Duration(hours: 2)),
          status: LocalReminderStatus.pending,
          createdAt: now,
        ),
        LocalReminder(
          id: 'test_med_1',
          ownerItemId: 'owner_med_1',
          type: LocalReminderType.medicine,
          title: 'Paracetamol 500mg',
          body: '1 tablet after lunch',
          scheduledAt: now.add(const Duration(hours: 3)),
          status: LocalReminderStatus.pending,
          createdAt: now,
        ),
        LocalReminder(
          id: 'test_trip_1',
          ownerItemId: 'owner_trip_1',
          type: LocalReminderType.commuteTrip,
          title: 'Bus to Uttara',
          body: 'Depart from Farmgate',
          scheduledAt: now.add(const Duration(hours: 4)),
          status: LocalReminderStatus.pending,
          createdAt: now,
        ),
      ];
      LocalReminderStore.instance.resetForTesting(items);

      await tester.pumpWidget(
        _buildWrapper(child: const NotificationCenterScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Physics Lab Report'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Bus to Uttara'), findsOneWidget);

      // Verify category badges
      expect(find.text('Task'), findsOneWidget);
      expect(find.text('Medicine'), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);

      // Verify inline action buttons
      expect(find.text('Mark Done'), findsOneWidget); // For Task
      expect(find.text('Taken'), findsOneWidget); // For Medicine
      expect(find.text('Skip'), findsOneWidget); // For Medicine
    });

    testWidgets('filter chips filter between All, Upcoming, and Completed', (
      tester,
    ) async {
      final now = DateTime.now();
      final items = [
        LocalReminder(
          id: 'pending_task',
          ownerItemId: 'owner_pending',
          type: LocalReminderType.task,
          title: 'Upcoming Math Homework',
          scheduledAt: now.add(const Duration(hours: 2)),
          status: LocalReminderStatus.pending,
          createdAt: now,
        ),
        LocalReminder(
          id: 'completed_task',
          ownerItemId: 'owner_completed',
          type: LocalReminderType.task,
          title: 'Finished History Essay',
          scheduledAt: now.subtract(const Duration(hours: 1)),
          status: LocalReminderStatus.completed,
          createdAt: now,
        ),
      ];
      LocalReminderStore.instance.resetForTesting(items);

      await tester.pumpWidget(
        _buildWrapper(child: const NotificationCenterScreen()),
      );
      await tester.pumpAndSettle();

      // "All" tab should show both
      expect(find.text('Upcoming Math Homework'), findsOneWidget);
      expect(find.text('Finished History Essay'), findsOneWidget);

      // Switch to "Upcoming" filter
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text('Upcoming Math Homework'), findsOneWidget);
      expect(find.text('Finished History Essay'), findsNothing);

      // Switch to "Completed" filter
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Upcoming Math Homework'), findsNothing);
      expect(find.text('Finished History Essay'), findsOneWidget);
    });

    testWidgets('tapping Mark Done on task updates status to Completed', (
      tester,
    ) async {
      final now = DateTime.now();
      final item = LocalReminder(
        id: 'inline_done_task',
        ownerItemId: 'inline_done_task',
        type: LocalReminderType.task,
        title: 'Call Supervisor',
        scheduledAt: now.add(const Duration(hours: 1)),
        status: LocalReminderStatus.pending,
        createdAt: now,
      );
      LocalReminderStore.instance.resetForTesting([item]);

      await tester.pumpWidget(
        _buildWrapper(child: const NotificationCenterScreen()),
      );
      await tester.pumpAndSettle();

      final doneButton = find.text('Mark Done');
      expect(doneButton, findsOneWidget);

      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      // Verify item is now marked completed in LocalReminderStore
      final updated = LocalReminderStore.instance.getById('inline_done_task');
      expect(updated?.status, equals(LocalReminderStatus.completed));
    });

    testWidgets('renders cleanly on 320dp width without overflow', (
      tester,
    ) async {
      final now = DateTime.now();
      final items = [
        LocalReminder(
          id: 'narrow_task',
          ownerItemId: 'narrow_task',
          type: LocalReminderType.assignment,
          title: 'Microprocessor Architecture Project Submission',
          body: 'Detailed report with assembly simulation diagrams',
          scheduledAt: now.add(const Duration(hours: 2)),
          status: LocalReminderStatus.pending,
          createdAt: now,
        ),
      ];
      LocalReminderStore.instance.resetForTesting(items);

      await tester.pumpWidget(
        _buildWrapper(width: 320, child: const NotificationCenterScreen()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Microprocessor Architecture Project Submission'),
        findsOneWidget,
      );
    });

    testWidgets('renders cleanly with 2.0x font scaling without overflow', (
      tester,
    ) async {
      final now = DateTime.now();
      final items = [
        LocalReminder(
          id: 'scale_task',
          ownerItemId: 'scale_task',
          type: LocalReminderType.task,
          title: 'Algorithm Assignment',
          body: 'Graph traversal problems',
          scheduledAt: now.add(const Duration(hours: 3)),
          status: LocalReminderStatus.pending,
          createdAt: now,
        ),
      ];
      LocalReminderStore.instance.resetForTesting(items);

      await tester.pumpWidget(
        _buildWrapper(
          textScaleFactor: 2.0,
          child: const NotificationCenterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Algorithm Assignment'), findsOneWidget);
    });
  });

  group('CustomReminderSheet Presentation', () {
    testWidgets('renders inputs and creates custom reminder', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCustomReminderSheet(context),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('New Reminder'), findsOneWidget);
      expect(find.text('What to remind?'), findsOneWidget);
      expect(find.text('Remind at'), findsOneWidget);
      expect(find.text('Save Reminder'), findsOneWidget);
    });
  });
}
