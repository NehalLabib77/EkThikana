// Phase T5/T6/T7 — Active Exam Rescue Experience Card
//
// Displays the active Exam Rescue status on Home / Study Today:
// - Exam title & days remaining
// - Today's rescue task completion count and progress bar
// - Planned minutes for today
// - State-specific CTA ("Continue Rescue" / "Open Plan" / "Review Plan")
//
// Source-of-truth driven: progress is derived entirely from the Firestore
// task stream via [ExamRescueSessionService.calculateTodayProgress] — no local
// fake progress increments.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'exam_rescue_models.dart';

/// Pure helper to calculate today's rescue progress from task maps.
ExamRescueTodayProgress calculateTodayProgress({
  required List<Map<String, dynamic>> tasks,
  required DateTime today,
  String? sessionId,
}) {
  final startOfDay = DateTime(today.year, today.month, today.day);
  final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

  var total = 0;
  var completed = 0;
  var minutes = 0;

  for (final t in tasks) {
    if (t['source'] != 'exam_rescue') continue;
    if (sessionId != null &&
        sessionId.isNotEmpty &&
        t['rescueSessionId'] != sessionId) {
      continue;
    }

    final dueAtRaw = t['dueAt'];
    DateTime? dueAt;
    if (dueAtRaw is DateTime) {
      dueAt = dueAtRaw;
    } else if (dueAtRaw is String && dueAtRaw.isNotEmpty) {
      dueAt = DateTime.tryParse(dueAtRaw);
    } else if (dueAtRaw != null && dueAtRaw.toString().isNotEmpty) {
      try {
        dueAt = (dueAtRaw as dynamic).toDate() as DateTime?;
      } catch (_) {}
    }

    if (dueAt != null &&
        !dueAt.isBefore(startOfDay) &&
        !dueAt.isAfter(endOfDay)) {
      total++;
      if (t['done'] == true) {
        completed++;
      }
      final est = t['estimatedMinutes'];
      if (est is num) {
        minutes += est.toInt();
      }
    }
  }

  return ExamRescueTodayProgress(
    overallTotal: total,
    overallCompleted: completed,
    todayTotal: total,
    todayCompleted: completed,
    todayPlannedMinutes: minutes,
  );
}

/// Hero card displaying active exam rescue progress on Home / Study Today.
class ExamRescueActiveCard extends StatelessWidget {
  const ExamRescueActiveCard({
    super.key,
    required this.session,
    required this.progress,
    required this.onContinueRescue,
    this.now,
  });

  final ExamRescueSession session;
  final ExamRescueTodayProgress progress;
  final VoidCallback onContinueRescue;
  final DateTime? now;

  String _daysLabel(BuildContext context) {
    final isBangla = GochanoLanguage.current.value == GochanoLocale.bangla;
    final days = session.localDaysRemaining(now ?? DateTime.now());
    if (isBangla) {
      if (days <= 0) return 'পরীক্ষা আজ';
      if (days == 1) return '১ দিন বাকি';
      return '${GochanoLanguage.formatNumber(days)} দিন বাকি';
    }
    if (days <= 0) return 'Exam Today';
    if (days == 1) return '1 day left';
    return '$days days left';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    // State precedence: whole-plan done > nothing today > everything today
    // done > in progress.
    final String headline;
    final String ctaLabel;
    if (progress.isPlanAllDone) {
      headline = GochanoLanguage.text(
        'All rescue tasks completed! Great work!',
        'সব রেসকিউ কাজ সম্পন্ন! দারুণ কাজ!',
      );
      ctaLabel = GochanoLanguage.text('Review Plan', 'প্ল্যান দেখুন');
    } else if (!progress.hasTasksToday) {
      headline = GochanoLanguage.text(
        'No rescue tasks scheduled for today.',
        'আজ কোনো রেসকিউ কাজ নির্ধারিত নেই।',
      );
      ctaLabel = GochanoLanguage.text('Open Plan', 'প্ল্যান খুলুন');
    } else if (progress.isTodayAllDone) {
      headline = GochanoLanguage.text(
        "All of today's rescue tasks are completed!",
        'আজকের সব রেসকিউ কাজ সম্পন্ন হয়েছে!',
      );
      ctaLabel = GochanoLanguage.text('Open Plan', 'প্ল্যান খুলুন');
    } else {
      headline = GochanoLanguage.text(
        '${progress.todayCompleted} of ${progress.todayTotal} rescue tasks completed',
        '${GochanoLanguage.formatNumber(progress.todayTotal)}-এর মধ্যে ${GochanoLanguage.formatNumber(progress.todayCompleted)}টি কাজ সম্পন্ন',
      );
      ctaLabel = GochanoLanguage.text('Continue Rescue', 'উদ্ধার চালিয়ে যান');
    }

    final showProgress = progress.hasTasksToday && !progress.isPlanAllDone;

    return AppCard(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: colors.brand),
              const SizedBox(width: GochanoSpacing.xxs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('EXAM RESCUE', 'পরীক্ষা উদ্ধার'),
                  style: type.caption.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.brand.withValues(alpha: 0.1),
                    borderRadius: GochanoRadius.smAll,
                  ),
                  child: Text(
                    _daysLabel(context),
                    style: type.caption.copyWith(
                      color: colors.brand,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            session.examTitle,
            style: type.cardHeading.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            headline,
            style: type.bodySecondary.copyWith(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (showProgress) ...[
            const SizedBox(height: GochanoSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.ratio,
                minHeight: 8,
                backgroundColor: colors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(colors.brand),
              ),
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: GochanoSpacing.xs,
              runSpacing: 2,
              children: [
                Text(
                  '${progress.percentage}%',
                  style: type.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  GochanoLanguage.text(
                    '${progress.todayPlannedMinutes} min planned today',
                    'আজ ${GochanoLanguage.formatNumber(progress.todayPlannedMinutes)} মিনিট নির্ধারিত',
                  ),
                  style: type.caption.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onContinueRescue,
              style: FilledButton.styleFrom(
                backgroundColor: colors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: const RoundedRectangleBorder(
                  borderRadius: GochanoRadius.smAll,
                ),
              ),
              child: Text(
                ctaLabel,
                style: type.button.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
