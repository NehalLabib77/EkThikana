// Phase T5/T6 — Active Exam Rescue Experience Card
//
// Displays the active Exam Rescue status on Home / Study Today:
// - Exam title & days remaining
// - Today's rescue task completion count and progress bar
// - Planned minutes for today
// - "Continue Rescue" CTA navigating to PlanView
//
// Source-of-truth driven: progress is derived entirely from the Firestore
// task stream via [calculateTodayProgress] — no local fake progress increments.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

/// Pure progress statistics derived from real tasks for the current day.
@immutable
class ExamRescueTodayProgress {
  final int completedTasks;
  final int totalTasks;
  final int plannedMinutes;

  const ExamRescueTodayProgress({
    required this.completedTasks,
    required this.totalTasks,
    required this.plannedMinutes,
  });

  double get ratio =>
      totalTasks > 0 ? (completedTasks / totalTasks).clamp(0.0, 1.0) : 0.0;

  int get percentage => (ratio * 100).round();
}

/// Pure helper to calculate today's rescue progress from tasks.
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
    completedTasks: completed,
    totalTasks: total,
    plannedMinutes: minutes,
  );
}

/// Hero card displaying active exam rescue progress on Home / Study Today.
class ExamRescueActiveCard extends StatelessWidget {
  const ExamRescueActiveCard({
    super.key,
    required this.examTitle,
    required this.daysRemaining,
    required this.progress,
    this.onContinue,
  });

  final String examTitle;
  final int daysRemaining;
  final ExamRescueTodayProgress progress;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final daysLabel = daysRemaining == 1
        ? GochanoLanguage.text('1 day remaining', '১ দিন বাকি')
        : GochanoLanguage.text(
            '$daysRemaining days remaining',
            '${GochanoLanguage.formatNumber(daysRemaining)} দিন বাকি',
          );

    return AppCard(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: colors.brand),
              const SizedBox(width: GochanoSpacing.xxs),
              Flexible(
                child: Text(
                  GochanoLanguage.text('EXAM RESCUE', 'পরীক্ষা রেসকিউ'),
                  style: type.caption.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.brand.withValues(alpha: 0.1),
                  borderRadius: GochanoRadius.smAll,
                ),
                child: Text(
                  daysLabel,
                  style: type.caption.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            examTitle,
            style: type.cardHeading.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              'Today: ${progress.completedTasks} of ${progress.totalTasks} rescue tasks completed',
              'আজ: ${GochanoLanguage.formatNumber(progress.totalTasks)}-এর মধ্যে ${GochanoLanguage.formatNumber(progress.completedTasks)}টি কাজ সম্পন্ন',
            ),
            style: type.bodySecondary.copyWith(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
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
                  '${progress.plannedMinutes} min planned today',
                  'আজ ${GochanoLanguage.formatNumber(progress.plannedMinutes)} মিনিট নির্ধারিত',
                ),
                style: type.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
          if (onContinue != null) ...[
            const SizedBox(height: GochanoSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: const RoundedRectangleBorder(
                    borderRadius: GochanoRadius.smAll,
                  ),
                ),
                child: Text(
                  GochanoLanguage.text('Continue Rescue', 'রেসকিউ চালিয়ে যান'),
                  style: type.button.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
