// Gochano unified AppBar.
//
// Replaces per-screen AppBars with a single shape so every screen has
// the same greeting + subtitle + language-toggle layout. Screens can
// still customize the leading / actions slots when they need to.
//
// Visual contract:
//   - bilingual title (default English, switchable to Bangla),
//   - small muted subtitle below the title,
//   - right-aligned LanguageToggle (replaced via [actions] if needed),
//   - soft elevation so it reads as a single floating header rather
//     than a stock Material AppBar.
//
// Built on the same tokens as the rest of the design system
// (design_tokens.dart) so it auto-adapts to dark mode.

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/language.dart';

/// A branded AppBar with greeting + subtitle + language toggle.
class GochanoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GochanoAppBar({
    super.key,
    required this.titleEn,
    required this.titleBn,
    this.subtitleEn,
    this.subtitleBn,
    this.actions,
    this.leading,
    this.scrolledUnderElevation = 0,
    this.showLanguageToggle = true,
  });

  /// Title string in English.
  final String titleEn;

  /// Title string in Bangla.
  final String titleBn;

  /// Optional subtitle in English.
  final String? subtitleEn;

  /// Optional subtitle in Bangla.
  final String? subtitleBn;

  /// Optional override for the right-side action area. Pass an empty
  /// list to suppress the language toggle. Defaults to
  /// `[LanguageToggle]` when [showLanguageToggle] is true and no
  /// custom actions are provided.
  final List<Widget>? actions;

  /// Optional leading widget (back button etc.).
  final Widget? leading;

  final double scrolledUnderElevation;

  /// When true and no [actions] are provided, the default LanguageToggle
  /// is appended on the right.
  final bool showLanguageToggle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = EkSurfaces.muted(context);
    final title = EkLanguage.text(titleEn, titleBn);
    final subtitle = (subtitleEn == null && subtitleBn == null)
        ? null
        : EkLanguage.text(
            subtitleEn ?? subtitleBn!,
            subtitleBn ?? subtitleEn!,
          );

    final resolvedActions = actions ??
        (showLanguageToggle ? const [LanguageToggle()] : const <Widget>[]);

    return AppBar(
      leading: leading,
      automaticallyImplyLeading: leading == null ? false : true,
      scrolledUnderElevation: scrolledUnderElevation,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      toolbarHeight: preferredSize.height,
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EkText.headline(context).copyWith(
              fontSize: 19,
              height: 1.15,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: muted,
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
      actions: [
        ...resolvedActions,
        const SizedBox(width: EkSpace.sm),
      ],
    );
  }
}

/// A simple search-bar header that sits below a [GochanoAppBar] and
/// mirrors the design tokens of the system. Use to standardize the
/// search affordance on top of lists.
class GochanoSearchField extends StatelessWidget {
  const GochanoSearchField({
    super.key,
    required this.hintEn,
    required this.hintBn,
    this.onTap,
    this.controller,
  });

  final String hintEn;
  final String hintBn;
  final VoidCallback? onTap;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final hint = EkLanguage.text(hintEn, hintBn);
    return TextField(
      readOnly: onTap != null,
      controller: controller,
      onTap: onTap,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
      ),
    );
  }
}
