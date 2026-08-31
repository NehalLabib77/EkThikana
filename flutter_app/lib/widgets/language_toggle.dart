// English / Bangla switch (spec §73).
//
// A two-segment control that shows exactly one active language. Each label is
// written in its own script, so a student who cannot read the other one can
// still find the switch.
//
// The previous version animated its selection pill. That is decorative motion
// on a control whose state change is already obvious, so the animation is
// gone (spec §11).

import 'package:flutter/material.dart';

import '../core/design_system/gochano_colors.dart';
import '../core/design_system/gochano_spacing.dart';
import '../core/design_system/gochano_typography.dart';
import '../core/localization/gochano_language.dart';

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(GochanoRadius.md),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final locale in GochanoLocale.values)
              _Segment(
                locale: locale,
                selected: GochanoLanguage.current.value == locale,
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.locale, required this.selected});

  final GochanoLocale locale;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      selected: selected,
      label: locale.nativeName,
      child: InkWell(
        onTap: () => GochanoLanguage.select(locale),
        borderRadius: BorderRadius.circular(GochanoRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: GochanoSpacing.xs,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(GochanoRadius.sm),
            border: Border.all(
              color: selected ? colors.border : Colors.transparent,
            ),
          ),
          child: Text(
            locale.shortLabel,
            style: context.type.caption.copyWith(
              color: selected ? colors.brand : colors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
