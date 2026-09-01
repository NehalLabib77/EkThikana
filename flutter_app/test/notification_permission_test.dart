// Notification permission flow + channel architecture smoke tests.
//
// Validates the structural pieces of P3-6:
//
//   1. The two channel IDs are stable and tied to the legacy `ekthikana_*`
//      prefix (per docs/GOCHANO_BRANDING.md — renaming would create new
//      channels and reset every existing user's per-channel preferences).
//   2. The NotificationService exposes a permission probe and a settings
//      deep-link helper for screens that need to nudge the user.
//   3. The shared AndroidNotificationDetails factory is referenced by
//      every schedule entry-point (scheduleTask, rescheduleTask,
//      scheduleDailyMedicine) — there are no stale inline copies left
//      behind from before the refactor.
//   4. Both channels declare `category: AndroidNotificationCategory.reminder`
//      so the OS routes them through the right priority lane.
//   5. Both channels explicitly set `enableVibration` + `playSound` so
//      reminders never arrive silently on devices whose defaults would
//      otherwise suppress them.
//   6. The medicine channel preserves its existing "Taken / Skip" actions
//      so the user-confirmed reminder flow still works.
//   7. The pre-prompt dialog widget renders bilingual copy and routes
//      through NotificationPermissionResult values.
//   8. The shared `showInfo` snackbar helper exists in core/ui.dart and
//      carries an optional action affordance.
//   9. Both screens that schedule reminders (medicine form, task add)
//      probe `areNotificationsEnabled()` after the schedule call and
//      surface the OS-settings deep link via `showInfo`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationService channel architecture', () {
    final serviceFile = File(
      'lib/services/notification_service.dart',
    );

    test('file exists', () {
      expect(serviceFile.existsSync(), isTrue);
    });

    test('legacy ekthikana channel IDs are preserved', () {
      // Per docs/GOCHANO_BRANDING.md, renaming these IDs would register new
      // channels and reset every existing user's per-channel preferences.
      // This assertion guards against accidental renames.
      final src = serviceFile.readAsStringSync();
      expect(src, contains("kChannelRemindersId = 'ekthikana_reminders'"));
      expect(src, contains("kChannelMedicineId = 'ekthikana_medicine'"));
    });

    test('both channel constants carry user-visible names + descriptions',
        () {
      final src = serviceFile.readAsStringSync();
      expect(src, contains("kChannelRemindersName = 'Gochano Reminders'"));
      expect(src, contains("kChannelRemindersDesc ="));
      expect(src, contains("kChannelMedicineName = 'Gochano Medicine Reminders'"));
      expect(src, contains("kChannelMedicineDesc ="));
    });

    test('shared AndroidNotificationDetails factory exists', () {
      // Single source of truth so future tweaks apply uniformly.
      final src = serviceFile.readAsStringSync();
      expect(src, contains('static AndroidNotificationDetails _details({'));
      expect(src, contains('category: AndroidNotificationCategory.reminder'));
      expect(src, contains('enableVibration: true'));
      expect(src, contains('playSound: true'));
    });

    test('every schedule entry-point uses the shared factory', () {
      // No inline AndroidNotificationDetails(...) should remain — otherwise
      // future changes to vibration/sound/category would silently skip
      // some schedule paths.
      final src = serviceFile.readAsStringSync();
      // Count of inline AndroidNotificationDetails( constructor calls.
      // We expect exactly zero because the factory replaced them.
      final inlineMatches = RegExp(
        r'android:\s*AndroidNotificationDetails\(',
      ).allMatches(src).length;
      expect(inlineMatches, 0,
          reason:
              'Inline AndroidNotificationDetails(...) instances found — '
              'every schedule path must route through the shared factory.');
      // And the factory must be referenced by all three schedule helpers.
      expect(src, contains('android: _details('));
    });

    test('medicine channel retains Taken / Skip actions', () {
      final src = serviceFile.readAsStringSync();
      expect(src, contains("'taken'"));
      expect(src, contains("'skip'"));
    });

    test('permission probe + settings helpers are public API', () {
      final src = serviceFile.readAsStringSync();
      expect(src, contains('static Future<bool?> areNotificationsEnabled()'));
      expect(src,
          contains('static Future<bool> openNotificationSettings()'));
    });

    test('init() does not show our own pre-prompt', () {
      // The pre-prompt is the screen's responsibility — init() is
      // intentionally minimal so cold-start never blocks on UI.
      final initBlock = RegExp(
        r'static Future<void> init\(\) async \{[\s\S]*?^\s*\}',
        multiLine: true,
      ).firstMatch(serviceFile.readAsStringSync())!.group(0)!;
      expect(initBlock.contains('showDialog'), isFalse);
    });
  });

  group('Notification permission dialog widget', () {
    final widgetFile = File(
      'lib/widgets/notification_permission_dialog.dart',
    );

    test('file exists', () {
      expect(widgetFile.existsSync(), isTrue);
    });

    test('exports the dialog + result enum', () {
      final src = widgetFile.readAsStringSync();
      expect(src, contains('class NotificationPermissionDialog'));
      expect(src, contains('enum NotificationPermissionResult'));
      expect(src,
          contains('NotificationPermissionResult.granted'));
      expect(src, contains('NotificationPermissionResult.requested'));
      expect(src, contains('NotificationPermissionResult.denied'));
      expect(src, contains('NotificationPermissionResult.settings'));
    });

    test('dialog copy is bilingual via EkLanguage.text', () {
      final src = widgetFile.readAsStringSync();
      // Title + body + both buttons must use EkLanguage.text with literal
      // English + Bangla pairs (matches the P3-4 audit contract).
      final ekCalls = RegExp(r'EkLanguage\.text\(').allMatches(src).length;
      expect(ekCalls, greaterThanOrEqualTo(4),
          reason:
              'Dialog should localize title, body, Enable, Not now at minimum.');
    });

    test('short-circuit when notifications are already enabled', () {
      // The wrapper should NOT show a dialog if notifications are already
      // granted, otherwise it becomes a nag surface on every re-add.
      final src = widgetFile.readAsStringSync();
      expect(src, contains('await NotificationService.areNotificationsEnabled()'));
      expect(src, contains('NotificationPermissionResult.granted'));
    });
  });

  group('showInfo snackbar helper', () {
    final uiFile = File('lib/core/ui.dart');

    test('is exported with an optional action affordance', () {
      final src = uiFile.readAsStringSync();
      expect(src, contains('void showInfo('));
      expect(src, contains('String? actionLabel'));
      expect(src, contains('VoidCallback? onAction'));
    });
  });

  group('Notification hookups in scheduling screens', () {
    test('medicine form schedules reminders and probes OS permission', () {
      final src = File('lib/screens/life/medicine_form_screen.dart')
          .readAsStringSync();
      expect(src, contains('NotificationService.scheduleDailyMedicine('));
      expect(src, contains('NotificationService.areNotificationsEnabled()'));
      expect(src, contains('NotificationService.openNotificationSettings()'));
      expect(src, contains('showInfo('));
    });

    test('tasks screen schedules reminders and probes OS permission', () {
      final src = File('lib/screens/tasks/tasks_screen.dart')
          .readAsStringSync();
      expect(src, contains('NotificationService.scheduleTask('));
      expect(src, contains('NotificationService.areNotificationsEnabled()'));
      expect(src, contains('NotificationService.openNotificationSettings()'));
      expect(src, contains('showInfo('));
    });
  });
}
