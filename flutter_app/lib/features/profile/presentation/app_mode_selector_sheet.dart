// App Mode Selector bottom sheet (Phase B).
//
// Allows students and users to choose between Study Mode and Utility Mode.
//
// Houses two selectable cards, a compact preview of visible destinations for
// each mode, and an explicit "Save Mode" button. Selection is staged locally
// and only persisted to SharedPreferences upon tapping "Save Mode".

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/settings/gochano_app_mode.dart';
import '../../../../shared/widgets/gochano_controls.dart';

/// Opens the App Mode selector bottom sheet.
Future<bool?> showAppModeSelectorSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AppModeSelectorSheet(),
  );
}

class AppModeSelectorSheet extends StatefulWidget {
  const AppModeSelectorSheet({super.key});

  @override
  State<AppModeSelectorSheet> createState() => _AppModeSelectorSheetState();
}

class _AppModeSelectorSheetState extends State<AppModeSelectorSheet> {
  late GochanoAppMode _stagedMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stagedMode = GochanoAppModePreferences.current.value;
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    await GochanoAppModePreferences.select(_stagedMode);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.xs,
          GochanoSpacing.md,
          GochanoSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              GochanoLanguage.text('App Mode', 'অ্যাপ মোড'),
              style: type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text(
                'Choose how Gochano is organized for you.',
                'আপনার পছন্দ অনুযায়ী গোছানো সাজান।',
              ),
              style: type.bodySecondary,
            ),
            const SizedBox(height: GochanoSpacing.md),

            // Mode Selection Cards (Vertical stack to prevent narrow-screen overflow)
            ModeCard(
              key: const ValueKey('app_mode_study_card'),
              mode: GochanoAppMode.study,
              isSelected: _stagedMode == GochanoAppMode.study,
              icon: Icons.menu_book_rounded,
              title: GochanoLanguage.text('Study Mode', 'স্টাডি মোড'),
              description: GochanoLanguage.text(
                'Focus on learning, planning, and your academic community.',
                'পড়াশোনা, পরিকল্পনা এবং একাডেমিক কমিউনিটিতে ফোকাস করুন।',
              ),
              accentColor: colors.brand,
              features: [
                GochanoLanguage.text('Today', 'আজ'),
                GochanoLanguage.text('Workspace', 'ওয়ার্কস্পেস'),
                GochanoLanguage.text('Plan', 'পরিকল্পনা'),
                GochanoLanguage.text('Community', 'কমিউনিটি'),
                GochanoLanguage.text('Profile', 'প্রোফাইল'),
              ],
              onTap: () {
                if (_stagedMode != GochanoAppMode.study) {
                  setState(() => _stagedMode = GochanoAppMode.study);
                }
              },
            ),
            const SizedBox(height: GochanoSpacing.sm),

            ModeCard(
              key: const ValueKey('app_mode_utility_card'),
              mode: GochanoAppMode.utility,
              isSelected: _stagedMode == GochanoAppMode.utility,
              icon: Icons.directions_bus_rounded,
              title: GochanoLanguage.text('Utility Mode', 'ইউটিলিটি মোড'),
              description: GochanoLanguage.text(
                'Focus on daily commute and expense management.',
                'দৈনন্দিন যাতায়াত ও খরচ ব্যবস্থাপনায় ফোকাস করুন।',
              ),
              accentColor: colors.commute,
              features: [
                GochanoLanguage.text('Today', 'আজ'),
                GochanoLanguage.text('Commute', 'যাতায়াত'),
                GochanoLanguage.text('Money', 'টাকা'),
                GochanoLanguage.text('Profile', 'প্রোফাইল'),
              ],
              onTap: () {
                if (_stagedMode != GochanoAppMode.utility) {
                  setState(() => _stagedMode = GochanoAppMode.utility);
                }
              },
            ),
            const SizedBox(height: GochanoSpacing.lg),

            // Save Action
            PrimaryButton(
              key: const ValueKey('save_app_mode_button'),
              label: GochanoLanguage.text('Save Mode', 'মোড সংরক্ষণ করুন'),
              busy: _saving,
              busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
              onPressed: _handleSave,
            ),
          ],
        ),
      ),
    );
  }
}

class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.mode,
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.features,
    required this.onTap,
  });

  final GochanoAppMode mode;
  final bool isSelected;
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final List<String> features;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Semantics(
      selected: isSelected,
      button: true,
      label: '$title, $description',
      child: Material(
        color: isSelected
            ? accentColor.withValues(alpha: 0.05)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: GochanoRadius.mdAll,
          side: BorderSide(
            color: isSelected ? accentColor : colors.border,
            width: isSelected ? 2.0 : GochanoBorders.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(GochanoSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: GochanoRadius.smAll,
                      ),
                      child: Icon(icon, color: accentColor, size: 22),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: type.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? accentColor
                                  : colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? accentColor : colors.border,
                          width: isSelected ? 6.0 : 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Wrap(
                  spacing: GochanoSpacing.xs,
                  runSpacing: GochanoSpacing.xs,
                  children: [
                    for (final feature in features)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.xs + 2,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accentColor.withValues(alpha: 0.10)
                              : colors.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          feature,
                          style: type.caption.copyWith(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? accentColor
                                : colors.textSecondary,
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
