import 'package:flutter/material.dart';

import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// Standard section header for dashboard screens.
///
/// Pairs a semantic icon, a clean title, and an optional trailing action
/// like "See All →" with proper touch targets and semantics.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 20,
              color: iconColor ?? colors.brand,
            ),
            const SizedBox(width: GochanoSpacing.xs),
          ],
          Expanded(
            child: Text(
              title,
              style: type.sectionHeading.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null && onAction != null)
            Semantics(
              button: true,
              label: actionLabel,
              child: InkWell(
                onTap: onAction,
                borderRadius: GochanoRadius.smAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GochanoSpacing.xs,
                    vertical: GochanoSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel!,
                        style: type.bodySecondary.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
