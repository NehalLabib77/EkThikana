import 'package:flutter/material.dart';

import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// The approved unified Section Container for Gochano.
///
/// Groups a section's icon, title, action link, and related content
/// inside ONE unified, aesthetically pleasing outer card.
///
/// Features:
/// - Rounded corners (20dp)
/// - Subtle gradient or tinted surface
/// - Soft border and light elevation
/// - Integrated header row with title and action
/// - Compact internal spacing preventing nested-card chaos
class AppSectionContainer extends StatelessWidget {
  const AppSectionContainer({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.actionLabel,
    this.onAction,
    required this.child,
    this.gradient,
    this.backgroundColor,
    this.borderColor,
    this.padding,
    this.contentPadding,
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;
  final Gradient? gradient;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : (backgroundColor ?? Colors.white),
        gradient: isDark ? null : gradient,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(
          color: borderColor ??
              (isDark ? colors.border : const Color(0xFFE2E8F0)),
          width: 1.1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(GochanoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Integrated Header Row
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? colors.brand,
                  ),
                  const SizedBox(width: GochanoSpacing.xs + 2),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: type.cardHeading.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(width: GochanoSpacing.xs),
                  InkWell(
                    onTap: onAction,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel!,
                            style: type.bodySecondary.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.brand,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: colors.brand,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: GochanoSpacing.sm + 2),

            // Content Body
            if (contentPadding != null)
              Padding(
                padding: contentPadding!,
                child: child,
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}
