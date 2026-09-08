// Session completion reward dialog.
//
// Shows a compact bottom sheet after a successfully completed Focus session,
// displaying the XP/Gems earned, and a level-up notification when applicable.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../domain/reward_model.dart';

/// Shows the reward completion sheet. Returns when the user dismisses it.
Future<void> showRewardCompletionSheet(
  BuildContext context, {
  required RewardGrantResult result,
  required int plannedMinutes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _RewardCompletionBody(
      result: result,
      plannedMinutes: plannedMinutes,
    ),
  );
}

class _RewardCompletionBody extends StatelessWidget {
  const _RewardCompletionBody({
    required this.result,
    required this.plannedMinutes,
  });

  final RewardGrantResult result;
  final int plannedMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Center(
              child: Text(
                GochanoLanguage.text('Great work!', 'দারুণ কাজ!'),
                style: context.type.pageTitle,
              ),
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Center(
              child: Text(
                GochanoLanguage.text(
                  '$plannedMinutes min focused',
                  '$plannedMinutes মিনিট ফোকাস',
                ),
                style: context.type.bodySecondary,
              ),
            ),
            const SizedBox(height: GochanoSpacing.lg),

            // Rewards earned
            _RewardRow(
              icon: Icons.star_rounded,
              label: GochanoLanguage.text('XP earned', 'XP প্রাপ্ত'),
              value: '+${result.xpGranted}',
              color: colors.study,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            _RewardRow(
              icon: Icons.diamond_rounded,
              label: GochanoLanguage.text('Gems earned', 'জেম প্রাপ্ত'),
              value: '+${result.gemsGranted}',
              color: colors.info,
            ),

            // Daily cap warning
            if (result.gemsGranted < rewardForMinutesPlanned(plannedMinutes)) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text(
                  'Daily Gem limit reached',
                  'আজকের জেম সীমা পূর্ণ হয়েছে',
                ),
                style: context.type.caption.copyWith(
                  color: colors.warning,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Level up section
            if (result.levelUp) ...[
              const SizedBox(height: GochanoSpacing.lg),
              Container(
                padding: const EdgeInsets.all(GochanoSpacing.md),
                decoration: BoxDecoration(
                  color: colors.study.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(GochanoRadius.md),
                  border: Border.all(
                    color: colors.study.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      GochanoLanguage.text(
                        'LEVEL UP',
                        'লেভেল উপ',
                      ),
                      style: context.type.sectionHeading.copyWith(
                        color: colors.study,
                      ),
                    ),
                    const SizedBox(height: GochanoSpacing.xs),
                    Text(
                      GochanoLanguage.text(
                        'Level ${result.oldLevel} → Level ${result.newLevel}',
                        'লেভেল ${result.oldLevel} → লেভেল ${result.newLevel}',
                      ),
                      style: context.type.body,
                    ),
                    if (result.unlockedReactions != null &&
                        result.unlockedReactions!.isNotEmpty) ...[
                      const SizedBox(height: GochanoSpacing.xs),
                      Text(
                        GochanoLanguage.text(
                          'New reactions unlocked',
                          'নতুন রিঅ্যাকশন আনলক হয়েছে',
                        ),
                        style: context.type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: GochanoSpacing.xxs),
                      Text(
                        result.unlockedReactions!.join(' '),
                        style: context.type.body.copyWith(fontSize: 24),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: GochanoSpacing.lg),

            // Done button
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(GochanoLanguage.text('Done', 'শেষ')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: Text(label, style: context.type.body),
        ),
        Text(
          value,
          style: context.type.body.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Helper to show raw gem value for the daily cap comparison in the sheet.
int _rawGemForMinutes(int plannedMinutes) {
  switch (plannedMinutes) {
    case 15:
      return 1;
    case 25:
      return 2;
    case 45:
      return 4;
    case 60:
      return 5;
    default:
      return 0;
  }
}

int rewardForMinutesPlanned(int plannedMinutes) => _rawGemForMinutes(plannedMinutes);
