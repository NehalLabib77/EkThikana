import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../app_gradients.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// The approved Ziku Coach Card for Gochano Today.
///
/// Features a robot avatar header, friendly mascot illustration, live speech bubble
/// with contextual coaching, and an "I'm ready! 🚀" CTA button.
class AppCoachCard extends StatelessWidget {
  const AppCoachCard({
    super.key,
    required this.message,
    required this.onTap,
    this.ctaLabel = "I'm ready! 🚀",
    this.onCta,
    this.isFallback = false,
  });

  final String message;
  final VoidCallback onTap;
  final String ctaLabel;
  final VoidCallback? onCta;
  final bool isFallback;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? null : AppGradients.zikuCoach,
        color: isDark ? colors.surface : null,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color: isDark ? colors.border : const Color(0xFFBAE6FD),
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
                        color: const Color(0xFFE0F2FE),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFBAE6FD)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        size: 16,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        'Ziku Coach',
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
                const SizedBox(height: GochanoSpacing.xs + 3),

                // Content row: Ziku mascot + speech bubble
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Mascot illustration
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: Image.asset(
                        AppAssets.zikuMascot,
                        fit: BoxFit.contain,
                        semanticLabel: 'Ziku Coach Mascot',
                        errorBuilder: (context, error, stackTrace) => Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFF0F9FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.smart_toy_rounded,
                            size: 28,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xs + 3),

                    // Message text
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.sm,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? colors.surfaceVariant
                              : Colors.white.withValues(alpha: 0.85),
                          borderRadius: const BorderRadius.all(Radius.circular(12)),
                          border: Border.all(
                            color: isDark
                                ? colors.border
                                : const Color(0xFFE0F2FE),
                          ),
                        ),
                        child: Text(
                          message,
                          style: type.bodySecondary.copyWith(
                            fontSize: 12.5,
                            height: 1.35,
                            color: colors.textPrimary,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs + 3),

                // CTA button
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: TextButton(
                    onPressed: onCta ?? onTap,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 4),
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
