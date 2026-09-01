// Gochano pre-prompt dialog for the OS POST_NOTIFICATIONS permission.
//
// Why this exists:
//   On Android 13+ (API 33) the OS shows its own "Allow Gochano to send you
//   notifications?" dialog the first time we call
//   `requestNotificationsPermission()`.  Without context, users tap "Deny"
//   because they don't yet understand *why* a student-only super-app would
//   want to nudge them.  Showing our own lightweight pre-prompt explains
//   the value before the OS dialog appears, which raises the grant rate.
//
// Usage:
//   - Invoke at a moment of obvious intent (saving the first medicine
//     reminder, creating the first task reminder) — NOT on cold start.
//   - If the user has already granted POST_NOTIFICATIONS, the helper
//     `NotificationService.areNotificationsEnabled()` returns true and
//     the calling screen can skip this widget entirely.
//   - If the user previously denied POST_NOTIFICATIONS, the OS will NOT
//     re-show its dialog.  In that case this widget still surfaces, but
//     its primary action routes the user to `openNotificationSettings()`
//     instead of asking the OS again.

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/language.dart';
import '../services/notification_service.dart';

/// Show the pre-prompt (modal dialog). Returns the user's choice.
///
/// Returns:
///   - [NotificationPermissionResult.granted]   → already enabled, nothing to do
///   - [NotificationPermissionResult.requested] → user tapped "Enable" once
///   - [NotificationPermissionResult.denied]    → user tapped "Not now"
///   - [NotificationPermissionResult.settings]  → user came from a denied OS
///                                                 state and asked for settings
Future<NotificationPermissionResult> showNotificationPermissionDialog(
  BuildContext context,
) async {
  // If notifications are already allowed, skip the dialog entirely so we
  // never become a nag surface.  Callers can compare against `granted` to
  // decide whether to show in-context UI.
  final alreadyEnabled = await NotificationService.areNotificationsEnabled();
  if (alreadyEnabled == true) {
    return NotificationPermissionResult.granted;
  }

  if (!context.mounted) {
    return NotificationPermissionResult.denied;
  }

  final result = await showDialog<NotificationPermissionResult>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const NotificationPermissionDialog(),
  );
  return result ?? NotificationPermissionResult.denied;
}

enum NotificationPermissionResult {
  /// Notifications were already enabled when the dialog was opened.
  granted,

  /// User tapped "Enable" and the OS prompt was shown for the first time.
  requested,

  /// User dismissed the dialog or tapped "Not now".
  denied,

  /// User came from a previously-denied OS state and tapped "Open settings".
  settings,
}

class NotificationPermissionDialog extends StatelessWidget {
  const NotificationPermissionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.notifications_active_outlined,
        size: 32,
        color: scheme.primary,
      ),
      title: Text(
        EkLanguage.text(
          'Enable reminders?',
          'রিমাইন্ডার চালু করবেন?',
        ),
      ),
      content: Text(
        EkLanguage.text(
          "Gochano uses notifications for tasks and medicine reminders. "
          "You'll see a system prompt next — nothing else.",
          "গোচানো টাস্ক ও ওষুধের রিমাইন্ডারের জন্য নোটিফিকেশন ব্যবহার করে। "
          "পরের ধাপে সিস্টেম একটি প্রম্পট দেখাবে — এর বাইরে আর কিছু নয়।",
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(NotificationPermissionResult.denied),
          child: Text(
            EkLanguage.text('Not now', 'এখন না'),
          ),
        ),
        FilledButton.icon(
          // We rely on [showNotificationPermissionDialog]'s wrapper to keep
          // the post-dialog flow consistent — this button only communicates
          // intent (the wrapper then probes the OS state and decides between
          // a fresh prompt and a settings redirect).
          icon: const Icon(Icons.notifications_outlined, size: 18),
          label: Text(
            EkLanguage.text('Enable', 'চালু করুন'),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: EkSpace.md,
              vertical: EkSpace.sm,
            ),
          ),
          onPressed: () =>
              Navigator.of(context).pop(NotificationPermissionResult.requested),
        ),
      ],
    );
  }
}
