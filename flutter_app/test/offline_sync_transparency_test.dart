import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/feedback_messages.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/life/presentation/commute/commute_screen.dart';
import 'package:gochano/features/shell/presentation/quick_add_sheet.dart';
import 'package:gochano/models/local_reminder.dart';
import 'package:gochano/services/connectivity_service.dart';
import 'package:gochano/services/local_reminder_store.dart';
import 'package:gochano/services/sync_coordinator.dart';
import 'package:gochano/widgets/sync_status_indicator.dart';
import 'package:gochano/widgets/sync_status_sheet.dart';

Widget _wrap(Widget child, {Size? size, double textScale = 1.0}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: size ?? const Size(390, 844),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    ConnectivityService.instance.debugForceValue(true);
    GochanoLanguage.current.value = GochanoLocale.english;
    SyncCoordinator.instance.debugReset();
    LocalReminderStore.instance.resetForTesting();
  });

  tearDown(() {
    SyncCoordinator.instance.debugReset();
    ConnectivityService.instance.debugForceValue(true);
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('1. Offline Status Indicator & Sync States', () {
    testWidgets('renders Synced state when online and zero pending', (
      tester,
    ) async {
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.synced,
          isOnline: true,
          pendingCount: 0,
          pendingItems: [],
        ),
      );

      await tester.pumpWidget(_wrap(const SyncStatusIndicator()));
      await tester.pumpAndSettle();

      expect(find.text('Synced'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
    });

    testWidgets('renders Offline mode state when offline and zero pending', (
      tester,
    ) async {
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.offline,
          isOnline: false,
          pendingCount: 0,
          pendingItems: [],
        ),
      );

      await tester.pumpWidget(_wrap(const SyncStatusIndicator()));
      await tester.pumpAndSettle();

      expect(find.text('Offline mode'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('renders Bengali text for Offline mode', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.offline,
          isOnline: false,
          pendingCount: 0,
          pendingItems: [],
        ),
      );

      await tester.pumpWidget(_wrap(const SyncStatusIndicator()));
      await tester.pumpAndSettle();

      expect(find.text('অফলাইন মোড'), findsOneWidget);
    });

    testWidgets('renders pending sync count in English and Bengali', (
      tester,
    ) async {
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.pending,
          isOnline: false,
          pendingCount: 3,
          pendingItems: [
            SyncPendingItem(
              id: '1',
              collection: 'tasks',
              type: 'task',
              title: 'Study Physics',
            ),
            SyncPendingItem(
              id: '2',
              collection: 'medicines',
              type: 'medicine',
              title: 'Napa Extra',
            ),
            SyncPendingItem(
              id: '3',
              collection: 'daily_expenses',
              type: 'expense',
              title: 'Lunch',
            ),
          ],
        ),
      );

      await tester.pumpWidget(_wrap(const SyncStatusIndicator()));
      await tester.pumpAndSettle();

      expect(find.text('3 items waiting to sync'), findsOneWidget);

      GochanoLanguage.current.value = GochanoLocale.bangla;
      await tester.pumpAndSettle();
      expect(find.text('৩টি পরিবর্তন সিঙ্ক অপেক্ষায়'), findsOneWidget);
    });

    testWidgets('tapping indicator opens SyncStatusSheet', (tester) async {
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.pending,
          isOnline: false,
          pendingCount: 1,
          pendingItems: [
            SyncPendingItem(
              id: '10',
              collection: 'tasks',
              type: 'task',
              title: 'Complete assignment',
            ),
          ],
        ),
      );

      await tester.pumpWidget(_wrap(const SyncStatusIndicator()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('sync_status_indicator_chip')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SyncStatusSheet), findsOneWidget);
      expect(find.text('Complete assignment'), findsOneWidget);
      expect(find.text('Waiting to sync (1)'), findsOneWidget);
    });
  });

  group('2. Sync Queue Visibility & Sync Action', () {
    testWidgets(
      'SyncStatusSheet hides internal IDs and shows friendly categories',
      (tester) async {
        SyncCoordinator.instance.debugSetState(
          const SyncState(
            status: SyncStatus.pending,
            isOnline: true,
            pendingCount: 2,
            pendingItems: [
              SyncPendingItem(
                id: 'doc_id_9999_internal',
                collection: 'tasks',
                type: 'task',
                title: 'Assignment submission',
              ),
              SyncPendingItem(
                id: 'doc_id_8888_internal',
                collection: 'daily_expenses',
                type: 'expense',
                title: 'Rickshaw fare',
              ),
            ],
          ),
        );

        await tester.pumpWidget(_wrap(const SyncStatusSheet()));
        await tester.pumpAndSettle();

        // Human-readable titles visible
        expect(find.text('Assignment submission'), findsOneWidget);
        expect(find.text('Rickshaw fare'), findsOneWidget);

        // Internal Firestore document IDs MUST NOT be shown to user
        expect(find.textContaining('doc_id_9999_internal'), findsNothing);
        expect(find.textContaining('doc_id_8888_internal'), findsNothing);

        // Category tags visible
        expect(find.text('Task'), findsOneWidget);
        expect(find.text('Expense'), findsOneWidget);
      },
    );

    testWidgets('Sync now button is disabled when offline', (tester) async {
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.offline,
          isOnline: false,
          pendingCount: 1,
          pendingItems: [
            SyncPendingItem(
              id: '1',
              collection: 'tasks',
              type: 'task',
              title: 'Lab report',
            ),
          ],
        ),
      );

      await tester.pumpWidget(_wrap(const SyncStatusSheet()));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('sync_now_button')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('3. Truthful Action Feedback Messages', () {
    test('Task feedback differentiates online vs offline', () {
      final onlineMsg = FeedbackMessages.taskSaved(isOffline: false);
      expect(onlineMsg, 'Task saved');

      final offlineMsg = FeedbackMessages.taskSaved(isOffline: true);
      expect(offlineMsg, 'Saved offline. Will sync when internet returns.');

      GochanoLanguage.current.value = GochanoLocale.bangla;
      final offlineBn = FeedbackMessages.taskSaved(isOffline: true);
      expect(offlineBn, 'অফলাইনে সংরক্ষিত। ইন্টারনেট ফিরলে সিঙ্ক হবে।');
    });

    test('Medicine feedback differentiates online vs offline', () {
      GochanoLanguage.current.value = GochanoLocale.english;
      final onlineMsg = FeedbackMessages.medicineSaved(isOffline: false);
      expect(onlineMsg, 'Medicine saved');

      final offlineMsg = FeedbackMessages.medicineSaved(isOffline: true);
      expect(offlineMsg, 'Reminder saved. Sync pending.');

      GochanoLanguage.current.value = GochanoLocale.bangla;
      final offlineBn = FeedbackMessages.medicineSaved(isOffline: true);
      expect(offlineBn, 'রিমাইন্ডার সংরক্ষিত। সিঙ্ক অপেক্ষায়।');
    });

    test('Expense feedback differentiates online vs offline', () {
      GochanoLanguage.current.value = GochanoLocale.english;
      final onlineMsg = FeedbackMessages.expenseSaved(isOffline: false);
      expect(onlineMsg, 'Expense added');

      final offlineMsg = FeedbackMessages.expenseSaved(isOffline: true);
      expect(offlineMsg, 'Saved locally.');

      GochanoLanguage.current.value = GochanoLocale.bangla;
      final offlineBn = FeedbackMessages.expenseSaved(isOffline: true);
      expect(offlineBn, 'ডিভাইসে সংরক্ষিত হয়েছে।');
    });

    test('Trip feedback differentiates online vs offline', () {
      GochanoLanguage.current.value = GochanoLocale.english;
      final onlineMsg = FeedbackMessages.tripPlanned(isOffline: false);
      expect(onlineMsg, 'Trip planned');

      final offlineMsg = FeedbackMessages.tripPlanned(isOffline: true);
      expect(
        offlineMsg,
        'Trip planned offline. Will sync when internet returns.',
      );

      GochanoLanguage.current.value = GochanoLocale.bangla;
      final offlineBn = FeedbackMessages.tripPlanned(isOffline: true);
      expect(offlineBn, 'অফলাইনে যাত্রা পরিকল্পিত। ইন্টারনেট ফিরলে সিঙ্ক হবে।');
    });
  });

  group('4. Commute Offline Graceful Fallback', () {
    testWidgets(
      'shows offline notice card and view saved trips button when offline',
      (tester) async {
        ConnectivityService.instance.debugForceValue(false);

        await tester.pumpWidget(_wrap(const CommuteScreen()));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('commute_offline_banner')),
          findsOneWidget,
        );
        expect(
          find.text('No internet connection. Saved trips are available.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('commute_view_saved_trips_button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows Bengali offline message on Commute when locale is Bangla',
      (tester) async {
        ConnectivityService.instance.debugForceValue(false);
        GochanoLanguage.current.value = GochanoLocale.bangla;

        await tester.pumpWidget(_wrap(const CommuteScreen()));
        await tester.pumpAndSettle();

        expect(
          find.text('ইন্টারনেট সংযোগ নেই। সংরক্ষিত যাত্রাগুলি উপলব্ধ।'),
          findsOneWidget,
        );
        expect(find.text('সংরক্ষিত যাত্রা দেখুন'), findsOneWidget);
      },
    );
  });

  group('5. Custom Reminder has Zero Network Dependency', () {
    test('LocalReminderStore functions completely offline', () async {
      ConnectivityService.instance.debugForceValue(false);
      expect(ConnectivityService.instance.online.value, isFalse);

      final store = LocalReminderStore.instance;
      await store.init();
      final now = DateTime.now();
      final reminder = LocalReminder(
        id: 'rem_1',
        ownerItemId: 'custom_1',
        type: LocalReminderType.custom,
        title: 'Call parents',
        scheduledAt: now.add(const Duration(hours: 2)),
        createdAt: now,
      );
      await store.save(reminder);

      expect(reminder.title, 'Call parents');
      expect(store.remindersNotifier.value.length, 1);
      expect(store.remindersNotifier.value.first.id, reminder.id);
    });
  });

  group('6. Responsive Layout & Accessibility', () {
    testWidgets('renders cleanly on 320dp narrow viewport without overflow', (
      tester,
    ) async {
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.pending,
          isOnline: false,
          pendingCount: 5,
          pendingItems: [
            SyncPendingItem(
              id: '1',
              collection: 'tasks',
              type: 'task',
              title:
                  'Super long task title testing 320dp narrow screen without overflow',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(const SyncStatusSheet(), size: const Size(320, 640)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly under 2.0x font scaling without overflow', (
      tester,
    ) async {
      SyncCoordinator.instance.debugSetState(
        const SyncState(
          status: SyncStatus.pending,
          isOnline: false,
          pendingCount: 2,
          pendingItems: [
            SyncPendingItem(
              id: '1',
              collection: 'tasks',
              type: 'task',
              title: 'Scaling test task',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(const SyncStatusIndicator(), textScale: 2.0),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('7. Regressions & Architectural Invariants', () {
    test('ProfileScreen includes SyncStatusCard in the list', () {
      final file = File(
        'lib/features/profile/presentation/profile_screen.dart',
      ).readAsStringSync();
      expect(file, contains('_SyncStatusCard()'));
      expect(file, contains('sync_status_sheet.dart'));
    });

    test('Universal Quick Add retains exactly 6 canonical actions', () {
      expect(QuickAddAction.values.length, 6);
    });
  });
}
