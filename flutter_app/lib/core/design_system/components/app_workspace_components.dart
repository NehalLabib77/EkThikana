import 'package:flutter/material.dart';

import '../../localization/gochano_language.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// Interactive tool card for the Study Workspace grid (spec §14, §16).
///
/// Features:
/// - Semantic soft gradient background
/// - Rounded 18dp corners (`GochanoRadius.appBarSurfaceAll` equivalent)
/// - Elevated 36x36dp icon container with semantic tint
/// - High-contrast title and short 1-2 line description
/// - Subtle directional arrow cue
/// - Accessible tap target (>=44dp)
/// - Light / dark mode support
class AppWorkspaceToolCard extends StatelessWidget {
  const AppWorkspaceToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Gradient? gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? colors.surface : Colors.white,
            gradient: isDark ? null : gradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? colors.border.withValues(alpha: 0.3)
                  : const Color(0xFFE2E8F0).withValues(alpha: 0.8),
              width: 1,
            ),
            boxShadow: isDark
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x0A000000), // Soft 4% shadow
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDark
                              ? accent.withValues(alpha: 0.2)
                              : accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 18, color: accent),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: colors.textTertiary,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: context.type.body.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Flexible(
                    child: Text(
                      subtitle,
                      style: context.type.caption.copyWith(
                        color: colors.textSecondary,
                        fontSize: 11.0,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact rounded search field for Study Workspace (spec §12).
class AppWorkspaceSearchField extends StatelessWidget {
  const AppWorkspaceSearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? colors.surfaceVariant : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? colors.border.withValues(alpha: 0.3)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: TextInputAction.search,
            style: context.type.body.copyWith(fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintText ??
                  GochanoLanguage.text(
                    'Search notes, materials, tools...',
                    'নোট, উপকরণ বা টুলস খুঁজুন...',
                  ),
              hintStyle: context.type.bodySecondary.copyWith(
                fontSize: 13.0,
                color: colors.textTertiary,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: colors.textTertiary,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              suffixIcon: hasText
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: colors.textTertiary,
                      onPressed: () {
                        controller.clear();
                        if (onClear != null) onClear!();
                        if (onChanged != null) onChanged!('');
                      },
                      tooltip: GochanoLanguage.text('Clear', 'মুছুন'),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Category filter chips for Study Workspace (spec §13).
class AppWorkspaceFilterChips extends StatelessWidget {
  const AppWorkspaceFilterChips({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (final cat in categories)
            Padding(
              padding: const EdgeInsets.only(right: GochanoSpacing.xs),
              child: _CategoryChip(
                label: cat,
                selected: selectedCategory == cat,
                onTap: () => onSelect(cat),
                colors: colors,
                isDark: isDark,
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.isDark,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final GochanoColors colors;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? (isDark ? colors.brand.withValues(alpha: 0.25) : colors.brand)
                  : (isDark ? colors.surfaceVariant : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? colors.brand
                    : (isDark ? colors.border : const Color(0xFFE2E8F0)),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: context.type.caption.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? (isDark ? Colors.white : Colors.white)
                      : colors.textSecondary,
                  fontSize: 12.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clean row for Recently Opened workspace items (spec §20, §21).
class AppRecentWorkspaceItem extends StatelessWidget {
  const AppRecentWorkspaceItem({
    super.key,
    required this.title,
    this.subtitle,
    this.metadata,
    required this.icon,
    this.accent,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? metadata;
  final IconData icon;
  final Color? accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final itemAccent = accent ?? colors.study;

    return Semantics(
      button: true,
      label: '$title, ${subtitle ?? ""}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 4.0,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark
                        ? itemAccent.withValues(alpha: 0.2)
                        : itemAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: itemAccent),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: context.type.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null || metadata != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (subtitle != null)
                              Flexible(
                                child: Text(
                                  subtitle!,
                                  style: context.type.caption.copyWith(
                                    color: colors.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (subtitle != null && metadata != null && metadata!.isNotEmpty)
                              Text(
                                ' · ',
                                style: context.type.caption.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                            if (metadata != null && metadata!.isNotEmpty)
                              Text(
                                metadata!,
                                style: context.type.caption.copyWith(
                                  color: colors.textTertiary,
                                  fontSize: 11.0,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
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
