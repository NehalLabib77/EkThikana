import 'package:flutter/material.dart';

import '../app_gradients.dart';
import '../app_motion.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// The approved Priority Task Card for Gochano Today.
///
/// Clean, soft semantic pastel surface with category icon, title, context,
/// duration chip, category chip, and circular completion control.
class AppPriorityTaskCard extends StatefulWidget {
  const AppPriorityTaskCard({
    super.key,
    required this.title,
    this.subtitle,
    this.durationMinutes,
    this.category = 'Practice',
    this.categoryTint,
    this.icon = Icons.menu_book_rounded,
    this.isCompleted = false,
    required this.onComplete,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final int? durationMinutes;
  final String category;
  final CategoryTint? categoryTint;
  final IconData icon;
  final bool isCompleted;
  final VoidCallback onComplete;
  final VoidCallback? onTap;

  @override
  State<AppPriorityTaskCard> createState() => _AppPriorityTaskCardState();
}

class _AppPriorityTaskCardState extends State<AppPriorityTaskCard> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checked = widget.isCompleted;
  }

  @override
  void didUpdateWidget(covariant AppPriorityTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted != oldWidget.isCompleted) {
      _checked = widget.isCompleted;
    }
  }

  void _handleComplete() {
    if (_checked) return;
    setState(() => _checked = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = context.isDark;

    final tint = widget.categoryTint ??
        CategoryTint.resolve(widget.category, isDark: isDark);

    final cardBg = isDark
        ? colors.surface
        : tint.background;
    final cardBorder = isDark
        ? colors.border
        : tint.border;

    return Semantics(
      container: true,
      label: 'Task: ${widget.title}, ${widget.subtitle ?? ""}',
      child: Material(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: cardBorder, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(GochanoSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: Icon container + completion circle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark ? colors.surfaceVariant : Colors.white,
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        boxShadow: [
                          BoxShadow(
                            color: tint.accent.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.icon,
                        size: 20,
                        color: tint.accent,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: _checked ? 'Completed' : 'Mark task completed',
                      child: InkWell(
                        key: const Key('task_complete_button'),
                        onTap: _handleComplete,
                        borderRadius: const BorderRadius.all(Radius.circular(999)),
                        child: AnimatedContainer(
                          duration: AppMotion.fast,
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _checked
                                ? colors.success
                                : (isDark ? colors.surfaceVariant : Colors.white),
                            border: Border.all(
                              color: _checked ? colors.success : colors.borderStrong,
                              width: 1.6,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: _checked
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),

                // Title
                Text(
                  widget.title,
                  style: type.cardHeading.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: colors.textPrimary,
                    decoration: _checked ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),

                // Subtitle / context
                if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                  Text(
                    widget.subtitle!,
                    style: type.bodySecondary.copyWith(
                      fontSize: 12.5,
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                ] else ...[
                  const SizedBox(height: GochanoSpacing.sm),
                ],

                // Bottom row: duration & action chip
                Row(
                  children: [
                    if (widget.durationMinutes != null &&
                        widget.durationMinutes! > 0) ...[
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.durationMinutes} min',
                        style: type.label.copyWith(
                          fontSize: 11.5,
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.xs + 2,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? colors.surfaceVariant : tint.chipBackground,
                        borderRadius: const BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        widget.category,
                        style: TextStyle(
                          color: isDark ? colors.textSecondary : tint.chipText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: GochanoTypography.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
