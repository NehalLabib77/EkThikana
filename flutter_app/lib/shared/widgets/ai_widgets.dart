// AI UX Polish — Shared widgets for empty states, error banners,
// and loading states across all AI-powered screens.
//
// Ensures consistent student experience: every AI screen looks and
// feels the same way, with the same visual language and localization.

import 'package:flutter/material.dart';

import '../../core/design_system/gochano_colors.dart';
import '../../core/design_system/gochano_spacing.dart';
import '../../core/design_system/gochano_typography.dart';
import '../../core/localization/gochano_language.dart';

/// Standard AI error banner — inline error below an action button.
///
/// Consistent across: Assignment Assistant, Smart Planner, Quiz Generator,
/// AI Assistant, Learning Insights recommendations.
class AiErrorBanner extends StatelessWidget {
  const AiErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.errorSoft,
        borderRadius: GochanoRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: context.type.bodySecondary.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard AI loading state — full-screen centred with "AI is analyzing..."
///
/// Applied to: Assignment Assistant, Quiz, Planner, Learning Insights,
/// Recommendations.
class AiLoadingState extends StatelessWidget {
  const AiLoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                minHeight: 6,
                backgroundColor: colors.surfaceVariant,
                color: colors.ai,
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              message ??
                  GochanoLanguage.text(
                    'AI is analyzing your data…',
                    'এআই আপনার ডেটা বিশ্লেষণ করছে…',
                  ),
              style: context.type.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Standard AI empty state — illustration + title + message + optional action.
///
/// Replaces the ad-hoc empty states that each AI screen used to build
/// independently, providing a consistent "nothing here yet" experience.
class AiEmptyState extends StatelessWidget {
  const AiEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveAccent = accent ?? colors.textTertiary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.xl,
          vertical: GochanoSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effectiveAccent.withValues(alpha: 0.10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 40, color: effectiveAccent),
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              title,
              style: context.type.sectionHeading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              message,
              style: context.type.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Localized AI error message strings.
///
/// Single place for all AI-related error messages so they are consistent
/// and localised.  Screens call `aiErrorMessage(type)` instead of building
/// their own strings inline.
String aiErrorMessage(AiErrorType type) {
  String t(String en, String bn) => GochanoLanguage.text(en, bn);
  switch (type) {
    case AiErrorType.network:
      return t(
        'Unable to connect with AI service. Please check your connection.',
        'এআই সার্ভারে সংযোগ হচ্ছে না। অনুগ্রহ করে আপনার সংযোগ দেখুন।',
      );
    case AiErrorType.aiFailure:
      return t(
        'AI service is temporarily unavailable. Please try again later.',
        'এআই সেবা সাময়িকভাবে অনুপলব্ধ। পরে আবার চেষ্টা করুন।',
      );
    case AiErrorType.quota:
      return t(
        'AI limit reached. Your limit resets tomorrow.',
        'এআই সীমা শেষ হয়েছে। আপনার সীমা আগামীকাল রিসেট হবে।',
      );
  }
}

enum AiErrorType { network, aiFailure, quota }
