// Gochano surface components: scaffold, app bar, cards, section headers.
//
// These are the surfaces every screen composes from (spec §84). Building them
// once here is what stops screens inventing their own card padding, their own
// heading size and their own "white box with a shadow".
//
// House rules encoded here:
//   * a card is a flat surface with a hairline border — never a shadow, never
//     a gradient (spec §15);
//   * a screen has exactly one page title (spec §85);
//   * nothing animates on appear (spec §11).

import 'package:flutter/material.dart';

import '../../core/design_system/gochano_colors.dart';
import '../../core/design_system/gochano_spacing.dart';
import '../../core/design_system/gochano_typography.dart';

/// The standard Gochano screen frame.
///
/// Wraps [Scaffold] so every screen gets the same background, the same safe
/// area behaviour and the same "content clears the bottom nav" padding
/// contract without repeating it (spec §23).
class GochanoScaffold extends StatelessWidget {
  const GochanoScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.bottomBar,
    this.padBody = true,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  /// A persistent action row pinned above the keyboard/safe area — used for
  /// "Save" on form screens so the primary action is never scrolled away.
  final Widget? bottomBar;

  /// Applies the standard horizontal page inset. Pass false for screens that
  /// manage their own padding (a full-bleed reader, a map).
  final bool padBody;

  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget content = body;
    if (padBody) {
      content = Padding(padding: GochanoSpacing.page, child: content);
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: appBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: SafeArea(top: appBar == null, bottom: false, child: content),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      persistentFooterAlignment: AlignmentDirectional.center,
      bottomSheet: bottomBar == null
          ? null
          : _BottomActionBar(child: bottomBar!),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(GochanoSpacing.md),
          child: child,
        ),
      ),
    );
  }
}

/// The one Gochano app bar.
///
/// [title] is the answer to "where am I?" (spec §85). [subtitle] is optional
/// context — a semester name, a group name — and is truncated rather than
/// allowed to push the title around.
class GochanoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GochanoAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        (subtitle == null ? kToolbarHeight : kToolbarHeight + 14) +
            (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppBar(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      titleSpacing: leading == null && !automaticallyImplyLeading
          ? GochanoSpacing.md
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: type.pageTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              style: type.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}

/// A flat content surface with a hairline border.
///
/// The default Gochano container. Set [onTap] to make the whole card the
/// touch target — which is what a card should be, rather than hiding the
/// action behind a small chevron.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = GochanoSpacing.card,
    this.onTap,
    this.accent,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// When set, a 3px accent rule is drawn down the leading edge. Used to
  /// mark a card's feature area without colouring the whole surface
  /// (spec §16).
  final Color? accent;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget content = Padding(padding: padding, child: child);

    if (accent != null) {
      // IntrinsicHeight is load-bearing, not decoration. `stretch` needs a
      // bounded height to stretch to, and a card in a ListView or a
      // SingleChildScrollView is handed an unbounded one -- which threw
      // "BoxConstraints forces an infinite height" for every accented card
      // in a scrolling list, including the Recommended fare card.
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent),
            Expanded(child: content),
          ],
        ),
      );
    }

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.border, width: GochanoBorders.hairline),
      ),
      child: ClipRRect(borderRadius: GochanoRadius.lgAll, child: content),
    );

    if (onTap == null) {
      return semanticLabel == null
          ? decorated
          : Semantics(label: semanticLabel, container: true, child: decorated);
    }

    return Semantics(
      label: semanticLabel,
      button: true,
      container: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: GochanoRadius.lgAll,
          child: decorated,
        ),
      ),
    );
  }
}

/// Heading above a group of cards or rows.
///
/// [action] is an optional trailing affordance ("See all"). Keeping it in the
/// header rather than as a separate button below the list is what keeps
/// content-heavy screens from accumulating stray CTAs (spec §86).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.only(
      top: GochanoSpacing.xl,
      bottom: GochanoSpacing.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: type.sectionHeading),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: type.caption),
                ],
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// A single figure with a label — the building block of the Home and Expense
/// overviews (spec §14, §48).
///
/// Flat surface, no gradient. The optional [accent] tints only the label icon
/// and the value, never the background.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.accent,
    this.onTap,
    this.compact = false,
  });

  final String label;
  final String value;
  final String? caption;
  final Widget? icon;
  final Color? accent;
  final VoidCallback? onTap;

  /// Uses the smaller statistic role — for three-up rows on narrow phones.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final colors = context.colors;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(GochanoSpacing.md),
      // The card announces "label, value" as one node so Talk-back does not
      // read a bare number with no context (spec §24).
      semanticLabel: '$label: $value${caption == null ? '' : ', $caption'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: GochanoSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  style: type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: (compact ? type.statisticSmall : type.statistic)
                  .copyWith(color: accent ?? colors.textPrimary),
              maxLines: 1,
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: type.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Groups rows inside one bordered surface with hairline separators.
///
/// Used by Profile and any settings-style list, so a screen does not end up
/// as a stack of individually bordered cards (spec §86).
class CardGroup extends StatelessWidget {
  const CardGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: colors.divider));
      }
      rows.add(children[i]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.border, width: GochanoBorders.hairline),
      ),
      child: ClipRRect(
        borderRadius: GochanoRadius.lgAll,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}
