// Loading / empty / error states (spec §12, §22, §74, §75, §76).
//
// Every network-backed list in Gochano renders through these three widgets,
// so "nothing here" always looks deliberate and "it broke" always says
// something a student can act on.
//
// Rules encoded here:
//   * **Loading is static and named.** No spinner-as-decoration. A determinate
//     bar when progress is known, a static bar plus "Loading materials…" when
//     it is not. The screen never looks frozen (spec §12, §74).
//   * **Empty states explain and offer the next step** — a small illustration,
//     a title, one sentence, and the action that fills the list (spec §75).
//   * **Errors never leak internals.** [ErrorState] takes a human message;
//     stack traces, DioException/SocketException text and Python tracebacks
//     are for logs (spec §76).

import 'package:flutter/material.dart';

import '../../core/design_system/gochano_art.dart';
import '../../core/design_system/gochano_colors.dart';
import '../../core/design_system/gochano_illustration.dart';
import '../../core/design_system/gochano_spacing.dart';
import '../../core/design_system/gochano_typography.dart';
import '../../core/localization/gochano_language.dart';
import '../../services/api_service.dart';

/// A static, labelled loading state.
///
/// Pass [progress] (0..1) whenever the real figure is known — an upload, a
/// multi-page render — because a percentage is information and a spinner is
/// not (spec §12).
class StaticLoadingState extends StatelessWidget {
  const StaticLoadingState({
    super.key,
    required this.message,
    this.progress,
    this.compact = false,
  });

  /// What is happening, in the student's language: "Loading materials…",
  /// "Checking route…", "Scanning prescription…".
  final String message;

  /// Determinate progress in 0..1, or null for indeterminate.
  final double? progress;

  /// Renders as a single inline row rather than a centred block. Use inside a
  /// card that is refreshing in place.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 6,
        backgroundColor: colors.surfaceVariant,
        color: colors.brand,
      ),
    );

    final label = Text(
      progress == null
          ? message
          : '$message  ${(progress!.clamp(0, 1) * 100).round()}%',
      style: type.bodySecondary,
      textAlign: compact ? TextAlign.start : TextAlign.center,
    );

    if (compact) {
      return Semantics(
        liveRegion: true,
        label: message,
        child: Row(
          children: [
            SizedBox(width: 72, child: bar),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(child: label),
          ],
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      label: message,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GochanoSpacing.xxl,
            vertical: GochanoSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 140, child: bar),
              const SizedBox(height: GochanoSpacing.md),
              label,
            ],
          ),
        ),
      ),
    );
  }
}

/// A deliberate "nothing here yet" state.
///
/// [title] says what is missing; [message] says what to do about it; the
/// optional [actionLabel]/[onAction] pair is the button that does it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.illustration,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.accent,
    this.compact = false,
  });

  /// An id from [GochanoArt].
  final String illustration;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final Color? accent;

  /// Uses a smaller illustration and tighter spacing, for an empty state
  /// inside a card rather than on a whole screen (spec §22: illustrations
  /// should not occupy excessive screen space).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final type = context.type;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: GochanoSpacing.xl,
          vertical: compact ? GochanoSpacing.lg : GochanoSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GochanoIllustration(
              illustration,
              size: compact ? 56 : GochanoSizes.illustrationEmpty,
              accent: accent,
            ),
            SizedBox(height: compact ? GochanoSpacing.sm : GochanoSpacing.md),
            Text(
              title,
              style: type.sectionHeading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              message,
              style: type.bodySecondary,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: GochanoSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: GochanoSpacing.xs),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A recoverable error state.
///
/// [message] must already be a human sentence. Callers map exceptions to a
/// message before they get here — see `friendlyErrorMessage` below.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.title,
    this.onRetry,
    this.retryLabel,
    this.illustration = GochanoArt.stateError,
    this.compact = false,
  });

  final String message;
  final String? title;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final String illustration;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final colors = context.colors;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: GochanoSpacing.xl,
          vertical: compact ? GochanoSpacing.lg : GochanoSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GochanoIllustration(
              illustration,
              size: compact ? 48 : 80,
              accent: colors.error,
            ),
            SizedBox(height: compact ? GochanoSpacing.sm : GochanoSpacing.md),
            Text(
              title ?? GochanoLanguage.text('Something went wrong', 'কিছু একটা ভুল হয়েছে'),
              style: type.sectionHeading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(message, style: type.bodySecondary, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: GochanoSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: GochanoSizes.iconSm),
                label: Text(
                  retryLabel ?? GochanoLanguage.text('Try again', 'আবার চেষ্টা করুন'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Turns any thrown object into a sentence a student can act on.
///
/// This is the single place the app translates machinery into language. It
/// deliberately recognises the shapes that used to leak to the UI — socket
/// failures, HTTP status codes, JSON parse errors — and never returns the raw
/// text for anything it does not recognise (spec §76, §38).
String friendlyErrorMessage(Object? error, {String? fallback}) {
  final raw = error?.toString() ?? '';
  final lower = raw.toLowerCase();

  String t(String en, String bn) => GochanoLanguage.text(en, bn);

  // Connectivity.
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection closed') ||
      lower.contains('connection refused') ||
      lower.contains('clientexception')) {
    return t(
      'No connection to Gochano. Check your internet and try again.',
      'গোছানো সার্ভারে সংযোগ নেই। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
    );
  }

  // Timeouts / cold starts.
  if (lower.contains('timeoutexception') ||
      lower.contains('timed out') ||
      lower.contains('taking longer than expected')) {
    return t(
      'The server is taking too long to respond. Please try again.',
      'সার্ভার সাড়া দিতে বেশি সময় নিচ্ছে। আবার চেষ্টা করুন।',
    );
  }

  // Authentication.
  if (lower.contains('not signed in') ||
      lower.contains('unauthenticated') ||
      lower.contains('401') && lower.contains('token')) {
    return t(
      'Your session has expired. Sign in again to continue.',
      'আপনার সেশন শেষ হয়ে গেছে। চালিয়ে যেতে আবার সাইন ইন করুন।',
    );
  }

  // Permission.
  if (lower.contains('permission-denied') ||
      lower.contains('permission denied') ||
      lower.contains('403')) {
    return t(
      'You do not have access to this item.',
      'এই আইটেমে আপনার অ্যাক্সেস নেই।',
    );
  }

  // Missing resource.
  if (lower.contains('not found') || lower.contains('404')) {
    return t(
      'This item is no longer available.',
      'এই আইটেমটি আর নেই।',
    );
  }

  // Quota.
  if (lower.contains('daily ai limit') || lower.contains('quota')) {
    return t(
      'The daily AI limit has been reached. Try again tomorrow.',
      'আজকের এআই সীমা শেষ হয়েছে। আগামীকাল আবার চেষ্টা করুন।',
    );
  }

  // An ApiException's message was written for a person by construction: it is
  // either a FastAPI `detail` string or one `_decode` composed itself. Trust
  // it rather than running it past the dump filter below.
  //
  // That filter used to swallow it, and the effect was bad: `_decode` phrases
  // a 500 as "...Open Render -> Logs to see the server traceback", the filter
  // saw the word "traceback", judged it an exception dump, and replaced it
  // with "Something went wrong. Please try again." Every backend 500 in the
  // app therefore reported nothing usable -- on the Focus screen, in group
  // chat, anywhere -- which made the real fault invisible from the device.
  if (error is ApiException) {
    final apiMessage = error.message.trim();
    if (apiMessage.isNotEmpty) return apiMessage;
  }

  // Anything the backend deliberately wrote for a human: FastAPI `detail`
  // strings arrive here already phrased for the user. Accept them only when
  // they look like prose rather than like an exception dump.
  final looksLikeInternals = lower.contains('exception') ||
      lower.contains('traceback') ||
      lower.contains('stack trace') ||
      lower.contains('sqlstate') ||
      lower.contains('psycopg') ||
      lower.contains('firebase_admin') ||
      lower.contains('#0 ') ||
      raw.contains('{') ||
      raw.contains('\n');
  if (raw.isNotEmpty && raw.length <= 180 && !looksLikeInternals) {
    return raw;
  }

  return fallback ??
      t(
        'Something went wrong. Please try again.',
        'কিছু একটা ভুল হয়েছে। আবার চেষ্টা করুন।',
      );
}
