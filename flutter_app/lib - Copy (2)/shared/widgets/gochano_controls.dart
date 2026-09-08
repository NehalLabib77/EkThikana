// Gochano interactive components: buttons, chips, search, list rows, sheets.
//
// The pieces screens tap, type into and choose from (spec §84). Centralising
// them is what enforces the accessibility floor — every tappable thing here
// is at least 48dp and carries a semantic label (spec §24) — and what keeps a
// card from sprouting six competing buttons (spec §32).

import 'package:flutter/material.dart';

import '../../core/design_system/gochano_art.dart';
import '../../core/design_system/gochano_colors.dart';
import '../../core/design_system/gochano_illustration.dart';
import '../../core/design_system/gochano_spacing.dart';
import '../../core/design_system/gochano_typography.dart';
import '../../core/localization/gochano_language.dart';

/// The single main action on a screen or in a dialog.
///
/// Set [busy] while an action is in flight: the button disables itself and
/// swaps its label for [busyLabel], which both prevents a double submit and
/// tells the student what is happening (spec §12, §77).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.busyLabel,
    this.expand = true,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final String? busyLabel;
  final bool expand;

  /// Paints the button in the error role. Use for Delete / Remove confirms.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveLabel = busy
        ? (busyLabel ?? GochanoLanguage.text('Working…', 'কাজ চলছে…'))
        : label;

    final button = FilledButton(
      onPressed: busy ? null : onPressed,
      style: destructive
          ? FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onBrand,
              minimumSize: const Size(0, GochanoSizes.buttonHeight),
              shape: const RoundedRectangleBorder(
                borderRadius: GochanoRadius.mdAll,
              ),
            )
          : null,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null && !busy) ...[
            Icon(icon, size: GochanoSizes.iconSm),
            const SizedBox(width: GochanoSpacing.xs),
          ],
          Flexible(
            child: Text(
              effectiveLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: !busy && onPressed != null,
      label: effectiveLabel,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// A lower-emphasis action that sits beside a [PrimaryButton].
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: GochanoSizes.iconSm),
            const SizedBox(width: GochanoSpacing.xs),
          ],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// An icon-only action with a mandatory label.
///
/// The label is required rather than optional because an unlabelled icon
/// button is invisible to Talk-back and ambiguous to everyone else (spec §24).
class IconActionButton extends StatelessWidget {
  const IconActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: accent),
      tooltip: label,
      constraints: const BoxConstraints(
        minWidth: GochanoSizes.minTouchTarget,
        minHeight: GochanoSizes.minTouchTarget,
      ),
    );
  }
}

/// Status/metadata pill.
///
/// [icon] is not decoration: pairing every tone with a glyph is what stops
/// status being carried by colour alone (spec §24).
enum GochanoBadgeTone { neutral, success, warning, error, info, brand }

class GochanoBadge extends StatelessWidget {
  const GochanoBadge({
    super.key,
    required this.label,
    this.tone = GochanoBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final GochanoBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg) = switch (tone) {
      GochanoBadgeTone.success => (c.success, c.successSoft),
      GochanoBadgeTone.warning => (c.warning, c.warningSoft),
      GochanoBadgeTone.error => (c.error, c.errorSoft),
      GochanoBadgeTone.info => (c.info, c.infoSoft),
      GochanoBadgeTone.brand => (c.brand, c.brandSoft),
      GochanoBadgeTone.neutral => (c.textSecondary, c.surfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: GochanoRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.type.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one search field shape in the app.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.trailing,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      style: context.type.body,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: GochanoSizes.iconMd),
        suffixIcon: trailing,
        isDense: true,
      ),
    );
  }
}

/// A horizontally scrolling row of single-select filters.
///
/// Scrolls rather than wraps so a long filter set never pushes content off a
/// small phone (spec §23).
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T value) labelOf;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GochanoSizes.minTouchTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: GochanoSpacing.xs),
        itemBuilder: (context, i) {
          final option = options[i];
          final isSelected = option == selected;
          return Center(
            child: ChoiceChip(
              label: Text(labelOf(option)),
              selected: isSelected,
              onSelected: (_) => onSelected(option),
            ),
          );
        },
      ),
    );
  }
}

/// A content row with a static illustration, a title, supporting metadata and
/// an overflow menu.
///
/// This is the shape material cards, group resources, medicines and expense
/// rows all share. Actions live in the menu rather than as permanent buttons,
/// which is the rule spec §32 sets: "Do not permanently display six buttons
/// on every card."
class GochanoListRow extends StatelessWidget {
  const GochanoListRow({
    super.key,
    required this.illustration,
    required this.title,
    this.subtitle,
    this.metadata,
    this.trailing,
    this.badge,
    this.accent,
    this.onTap,
    this.menuItems,
  });

  /// An id from [GochanoArt].
  final String illustration;
  final String title;

  /// One line under the title — the subject, the uploader, the category.
  final String? subtitle;

  /// Low-emphasis facts joined with a middle dot: date, size, page count.
  final List<String>? metadata;

  final Widget? trailing;
  final Widget? badge;
  final Color? accent;
  final VoidCallback? onTap;

  /// Overflow menu entries. Omitted entirely when null, so a row without
  /// secondary actions does not show an empty menu button.
  final List<GochanoMenuAction>? menuItems;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final meta = (metadata ?? const <String>[])
        .where((e) => e.trim().isNotEmpty)
        .join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GochanoSpacing.sm,
            vertical: GochanoSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GochanoIllustrationTile(illustration, accent: accent),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: type.cardHeading,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: GochanoSpacing.xs),
                          badge!,
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: type.bodySecondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: type.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (menuItems != null && menuItems!.isNotEmpty)
                GochanoOverflowMenu(items: menuItems!),
            ],
          ),
        ),
      ),
    );
  }
}

/// One entry in an overflow menu or action sheet.
class GochanoMenuAction {
  const GochanoMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
  final bool enabled;
}

/// The "…" menu used on content rows and cards.
class GochanoOverflowMenu extends StatelessWidget {
  const GochanoOverflowMenu({super.key, required this.items, this.tooltip});

  final List<GochanoMenuAction> items;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      tooltip: tooltip ?? GochanoLanguage.text('More actions', 'আরও অপশন'),
      icon: const Icon(Icons.more_vert_rounded),
      position: PopupMenuPosition.under,
      onSelected: (i) => items[i].onSelected(),
      itemBuilder: (context) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: items[i].enabled,
            child: Row(
              children: [
                Icon(
                  items[i].icon,
                  size: GochanoSizes.iconSm,
                  color: items[i].destructive ? c.error : c.textSecondary,
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Text(
                  items[i].label,
                  style: context.type.body.copyWith(
                    color: items[i].destructive ? c.error : c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Asks the student to confirm before something irreversible happens.
///
/// Returns true only on explicit confirmation. Used for delete, leave group,
/// unpurchase, and account actions.
Future<bool> showConfirmationSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  String illustration = GochanoArt.stateError,
  bool destructive = true,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final c = sheetContext.colors;
      final type = sheetContext.type;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.lg,
            GochanoSpacing.xs,
            GochanoSpacing.lg,
            GochanoSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GochanoIllustration(
                  illustration,
                  size: 64,
                  accent: destructive ? c.error : c.brand,
                ),
              ),
              const SizedBox(height: GochanoSpacing.md),
              Text(title, style: type.sectionHeading, textAlign: TextAlign.center),
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                message,
                style: type.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: GochanoSpacing.lg),
              PrimaryButton(
                label: confirmLabel,
                destructive: destructive,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: GochanoSpacing.xs),
              SecondaryButton(
                label: cancelLabel ?? GochanoLanguage.text('Cancel', 'বাতিল'),
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// Shows a short confirmation or failure message.
///
/// Routed through here so no screen builds its own SnackBar styling and no
/// screen accidentally dumps an exception into one (spec §76).
void showGochanoMessage(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final c = context.colors;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: GochanoSizes.iconSm,
              color: isError ? c.error : c.success,
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
}
