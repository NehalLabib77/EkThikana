import 'package:flutter/material.dart';

import '../app_gradients.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// The approved Focus Session Card for Gochano Today.
///
/// Features target header, big timer display (e.g. 25:00), deep work benefits,
/// cozy illustration slot, and primary gradient/solid CTA button.
class AppFocusCard extends StatelessWidget {
  const AppFocusCard({
    super.key,
    required this.timerDisplay,
    this.statusSubtitle = 'Deep work. Real progress.',
    this.ctaLabel = 'Start Focus Session',
    this.ctaIcon = Icons.play_arrow_rounded,
    required this.onTap,
    required this.onStart,
    this.isRunning = false,
  });

  final String timerDisplay;
  final String statusSubtitle;
  final String ctaLabel;
  final IconData ctaIcon;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? null : AppGradients.focusSession,
        color: isDark ? colors.surface : null,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color: isDark ? colors.border : const Color(0xFFDDD6FE),
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
              vertical: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FE),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        size: 16,
                        color: Color(0xFF7048F5),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        'Focus Session',
                        style: type.cardHeading.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  statusSubtitle,
                  style: type.bodySecondary.copyWith(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: GochanoSpacing.xs),

                // Timer display & feature benefits
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timerDisplay,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              fontFamily: GochanoTypography.fontFamily,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(
                                Icons.do_not_disturb_on_outlined,
                                size: 12,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'No distractions',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: GochanoTypography.fontFamily,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.trending_up_rounded,
                                size: 12,
                                color: Color(0xFF10B981),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Boosts retention',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: GochanoTypography.fontFamily,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Cozy focus graphic / window badge
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFEF3C7), Color(0xFFEDE9FE)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.all(Radius.circular(14)),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7048F5).withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.wb_sunny_rounded,
                        color: Color(0xFFF59E0B),
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs + 3),

                // Action CTA button
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton(
                    onPressed: onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7048F5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.sm,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(ctaIcon, size: 15, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            ctaLabel,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: GochanoTypography.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
