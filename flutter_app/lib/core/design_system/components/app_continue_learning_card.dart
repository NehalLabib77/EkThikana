import 'package:flutter/material.dart';

import '../app_gradients.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// The approved Continue Learning Card for Gochano Today.
///
/// Surfaces ongoing/recent study material with subject artwork thumbnail,
/// title, context, honest progress bar (or clean metadata), and chevron.
class AppContinueLearningCard extends StatelessWidget {
  const AppContinueLearningCard({
    super.key,
    required this.title,
    this.subtitle,
    this.progressFraction,
    this.progressLabel,
    this.thumbnail,
    required this.onTap,
    this.isEmbedded = false,
  });

  final String title;
  final String? subtitle;
  final double? progressFraction;
  final String? progressLabel;
  final Widget? thumbnail;
  final VoidCallback onTap;
  final bool isEmbedded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = context.isDark;

    return Container(
      decoration: isEmbedded
          ? null
          : BoxDecoration(
              gradient: isDark ? null : AppGradients.continueLearning,
              color: isDark ? colors.surface : null,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: Border.all(
                color: isDark ? colors.border : const Color(0xFFDDD6FE),
                width: 1.1,
              ),
            ),
      clipBehavior: isEmbedded ? Clip.none : Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isEmbedded ? 2 : 14,
              vertical: isEmbedded ? 4 : 11,
            ),
            child: Row(
              children: [
                // Subject thumbnail / artwork
                thumbnail ??
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.all(Radius.circular(12)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                const SizedBox(width: GochanoSpacing.sm + 4),

                // Title, subtitle & progress
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: type.cardHeading.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
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
                            fontSize: 12.5,
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (progressFraction != null) ...[
                        const SizedBox(height: GochanoSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.all(Radius.circular(999)),
                                child: LinearProgressIndicator(
                                  value: progressFraction!.clamp(0.0, 1.0),
                                  minHeight: 5,
                                  backgroundColor: isDark
                                      ? colors.surfaceVariant
                                      : const Color(0xFFE2E8F0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2F6BFF),
                                  ),
                                ),
                              ),
                            ),
                            if (progressLabel != null) ...[
                              const SizedBox(width: GochanoSpacing.xs),
                              Text(
                                progressLabel!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2F6BFF),
                                  fontFamily: GochanoTypography.fontFamily,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
