import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'language.dart';
import 'theme.dart';

/// Best-effort mapping from a thrown error to a localized, user-facing
/// string. `permission-denied` is the only case we actively rewrite because
/// Firestore rules require `verified()` for several collections (notably
/// `bazar_items` / `financial_transactions`) and the raw error string
/// confuses users — they assume the app is broken when in reality the rule
/// only allows them to write after they verify their email.
String _friendlyMessage(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return EkLanguage.text(
      'Your account is not verified yet. Please verify your email to save changes.',
      'আপনার অ্যাকাউন্ট এখনো যাচাই হয়নি। পরিবর্তন সংরক্ষণ করতে ইমেইল যাচাই করুন।',
    );
  }
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty ? 'Something went wrong. Please try again.' : text;
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2D33),
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(_friendlyMessage(error)),
      ),
    );
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EkColors.green,
        margin: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(message),
      ),
    );
}

/// Info snackbar with an optional tappable action. Used by screens that
/// need to nudge the user into a settings screen (notification permission,
/// location, etc.) without blocking the surrounding flow.
///
/// `action` is rendered in `EkColors.amber` so it reads as a secondary
/// affordance against the dark snackbar background — same colour family
/// as our inline action links elsewhere.
void showInfo(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2D33),
        margin: const EdgeInsets.all(14),
        duration: duration,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(message),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: EkColors.orange,
                onPressed: onAction,
              )
            : null,
      ),
    );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirm',
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                child: title,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 11, color: EkColors.muted),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}
