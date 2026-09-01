// Unified state surface for list / detail screens.
//
// Why this exists:
//   - Before this widget, every screen rendered its own loading/empty/
//     error combinations inline. The patterns drifted: some screens used
//     the Gochano loading widget, some used a CircularProgressIndicator,
//     some showed a StackOverflow error, some showed nothing.
//   - This widget centralises the contract:
//       EkStateView({
//         state: ...,
//         module: 'study',     // for the empty illustration
//         title: ...,
//         message: ...,
//         onRetry: ...,
//       })
//   - States:
//       * loading → GochanoLoading (or compact)
//       * empty   → EmptyIllustrationPainter + title + message + CTA
//       * error   → red icon + title + message + Retry button
//       * success → caller renders the body via `dataBuilder`
//
// Why a sealed-class-like enum rather than three separate widgets:
//   - The call-site reads as a single object: `EkStateView(state: .empty,
//     module: 'study', ...)` which makes it easy to add telemetry or a
//     global debug overlay later without touching every screen.
//   - State transitions (loading → empty / empty → success) are a
//     one-line `setState` instead of a `if (loading) ... else if (empty)
//     ... else if (err) ...` ladder in every screen.

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/language.dart';
import 'empty_illustrations.dart';
import 'gochano_loading.dart';

/// Three states a list / detail screen can be in.
enum EkViewState { loading, empty, error, success }

/// Default sizing for the empty-state illustration.
const double _kEmptyIllustrationSize = 160;

/// A unified loading / empty / error surface.
///
/// Usage:
///
/// ```dart
/// EkStateView(
///   state: EkViewState.empty,
///   module: 'study',
///   title: EkLanguage.text('No notes yet', 'কোন নোট নেই'),
///   message: EkLanguage.text('Tap + to create one.', '+ চেপে তৈরি করুন।'),
///   onAction: () => _openCreate(),
///   actionLabel: EkLanguage.text('Create note', 'নোট তৈরি করুন'),
/// )
/// ```
class EkStateView extends StatelessWidget {
  const EkStateView({
    super.key,
    required this.state,
    this.module = 'study',
    this.title,
    this.message,
    this.onRetry,
    this.onAction,
    this.actionLabel,
    this.compact = false,
    this.dataBuilder,
  });

  /// Current state. When [state] is [EkViewState.success] the caller MUST
  /// also pass [dataBuilder]; for all other states [dataBuilder] is
  /// ignored.
  final EkViewState state;

  /// Module id used to pick the empty illustration. Falls back to the
  /// generic sparkle if no matching shape exists.
  final String module;

  /// Headline shown in the empty / error states.
  final String? title;

  /// Body copy shown under [title].
  final String? message;

  /// Retry callback. Required for [EkViewState.error]; optional for
  /// [EkViewState.loading] (exposed as a fallback button after a delay).
  final VoidCallback? onRetry;

  /// Primary CTA callback (e.g. "Create note", "Upload material").
  /// When set, also pass [actionLabel].
  final VoidCallback? onAction;

  /// Label for the primary CTA.
  final String? actionLabel;

  /// If true, uses the compact loading variant. Has no effect on the
  /// empty / error states.
  final bool compact;

  /// Body builder used only when [state] == [EkViewState.success].
  final WidgetBuilder? dataBuilder;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case EkViewState.loading:
        return compact
            ? const GochanoLoading.compact()
            : GochanoLoading(onRetry: onRetry);
      case EkViewState.empty:
        return _EmptyBody(
          module: module,
          title: title,
          message: message,
          onAction: onAction,
          actionLabel: actionLabel,
        );
      case EkViewState.error:
        return _ErrorBody(
          title: title,
          message: message,
          onRetry: onRetry,
        );
      case EkViewState.success:
        if (dataBuilder == null) {
          // Defensive: in debug we want to see this clearly.
          assert(
            false,
            'EkStateView(state: success) requires dataBuilder. '
            'Either pass dataBuilder or render the body directly.',
          );
          return const SizedBox.shrink();
        }
        return Builder(builder: dataBuilder!);
    }
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({
    required this.module,
    required this.title,
    required this.message,
    required this.onAction,
    required this.actionLabel,
  });

  final String module;
  final String? title;
  final String? message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.surfaceContainerHighest;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: title ?? EkLanguage.text('Nothing here yet', 'এখানে কিছু নেই'),
                child: SizedBox(
                  width: _kEmptyIllustrationSize,
                  height: _kEmptyIllustrationSize,
                  child: CustomPaint(
                    painter: EmptyIllustrationPainter(
                      module: module,
                      accent: accent,
                      muted: muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (title != null)
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: EkSurfaces.muted(context),
                  ),
                ),
              ],
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String? title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: scheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                title ??
                    EkLanguage.text(
                      'Something went wrong',
                      'কিছু সমস্যা হয়েছে',
                    ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: EkSurfaces.muted(context),
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(EkLanguage.text('Retry', 'আবার চেষ্টা করুন')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
