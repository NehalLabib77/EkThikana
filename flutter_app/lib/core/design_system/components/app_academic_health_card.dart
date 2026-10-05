import 'package:flutter/material.dart';

import '../app_gradients.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// The approved simplified Academic Health Card for Gochano Today.
///
/// Replaces the old 5-ring layout with a compact, encouraging summary:
/// circular score ring, on-track status, strongest metric chip, and streak chip.
class AppSimplifiedAcademicHealthCard extends StatelessWidget {
  const AppSimplifiedAcademicHealthCard({
    super.key,
    required this.score,
    required this.headline,
    this.subtitle,
    this.strongestMetric,
    this.attentionOrStreakMetric,
    required this.onTap,
    this.hasData = true,
  });

  final int? score;
  final String headline;
  final String? subtitle;
  final String? strongestMetric;
  final String? attentionOrStreakMetric;
  final VoidCallback onTap;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? null : AppGradients.academicHealth,
        color: isDark ? colors.surface : null,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color: isDark ? colors.border : const Color(0xFFA7F3D0),
          width: 1.1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
              if (!hasData || score == null) {
                // Encouraging empty / initial state (spec §26: No data ≠ poor performance)
                return Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.insights_rounded,
                        color: Color(0xFF16A34A),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            headline.isNotEmpty
                                ? headline
                                : 'Building your learning profile',
                            style: type.cardHeading.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle ??
                                "Complete a few study activities and we'll show your progress.",
                            style: type.bodySecondary.copyWith(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colors.textTertiary,
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Score ring
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                value: (score! / 100).clamp(0.0, 1.0),
                                strokeWidth: 4.5,
                                backgroundColor: isDark
                                    ? colors.surfaceVariant
                                    : Colors.white.withValues(alpha: 0.6),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  score! >= 70
                                      ? const Color(0xFF059669)
                                      : (score! >= 50
                                          ? const Color(0xFFD97706)
                                          : const Color(0xFFDC2626)),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$score',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    fontFamily: GochanoTypography.fontFamily,
                                  ),
                                ),
                                Text(
                                  '/100',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textTertiary,
                                    height: 1.1,
                                    fontFamily: GochanoTypography.fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.sm + 4),

                      // Status & subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              headline,
                              style: type.cardHeading.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                style: type.bodySecondary.copyWith(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Metric chips row (strongest & attention/streak)
                  if (strongestMetric != null ||
                      attentionOrStreakMetric != null) ...[
                    const SizedBox(height: GochanoSpacing.xs + 3),
                    Wrap(
                      spacing: GochanoSpacing.xs,
                      runSpacing: GochanoSpacing.xxs,
                      children: [
                        if (strongestMetric != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: GochanoSpacing.xs + 4,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? colors.surfaceVariant
                                  : Colors.white.withValues(alpha: 0.9),
                              borderRadius: const BorderRadius.all(Radius.circular(8)),
                              border: Border.all(
                                color: const Color(0xFFA7F3D0),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.trending_up_rounded,
                                  size: 13,
                                  color: Color(0xFF059669),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    strongestMetric!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF065F46),
                                      fontFamily: GochanoTypography.fontFamily,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (attentionOrStreakMetric != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: GochanoSpacing.xs + 4,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? colors.surfaceVariant
                                  : Colors.white.withValues(alpha: 0.9),
                              borderRadius: const BorderRadius.all(Radius.circular(8)),
                              border: Border.all(
                                color: const Color(0xFFFDE68A),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 13,
                                  color: Color(0xFFD97706),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    attentionOrStreakMetric!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF92400E),
                                      fontFamily: GochanoTypography.fontFamily,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
}
