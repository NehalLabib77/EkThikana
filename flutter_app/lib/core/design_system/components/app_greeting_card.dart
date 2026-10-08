import 'package:flutter/material.dart';

import '../../../../features/study/presentation/today/greeting_presentation.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// The approved dynamic time-of-day greeting box for Gochano Study Mode.
///
/// Features:
/// - Semantic time-of-day gradient (Early Morning, Morning, Afternoon, Evening, Night)
/// - Integrated user name and warm waving hand gesture
/// - Deterministic supportive message
/// - Micro visual cue badge representing the time-of-day period
/// - Responsive and compact density (zero overflow on narrow viewports)
class AppGreetingCard extends StatelessWidget {
  const AppGreetingCard({
    super.key,
    required this.userName,
    this.dateTime,
    this.presentationOverride,
  });

  final String userName;
  final DateTime? dateTime;
  final GreetingPresentation? presentationOverride;

  @override
  Widget build(BuildContext context) {
    final now = dateTime ?? DateTime.now().toLocal();
    final presentation = presentationOverride ?? GreetingPresentation.forTime(now);
    final isDark = context.isDark;

    // In dark mode, for non-night periods we use dark surface with subtle tint
    final effectiveGradient = isDark && presentation.period != GreetingPeriod.night
        ? null
        : presentation.gradient;

    final effectiveBgColor = isDark && presentation.period != GreetingPeriod.night
        ? context.colors.surface
        : null;

    final effectiveTextColor = isDark && presentation.period != GreetingPeriod.night
        ? context.colors.textPrimary
        : presentation.textColor;

    final effectiveSubtitleColor = isDark && presentation.period != GreetingPeriod.night
        ? context.colors.textSecondary
        : presentation.subtitleColor;

    final effectiveIconColor = isDark && presentation.period != GreetingPeriod.night
        ? context.colors.brand
        : presentation.iconColor;

    final effectiveContainerColor = isDark && presentation.period != GreetingPeriod.night
        ? context.colors.surfaceElevated
        : presentation.iconContainerColor;

    return Container(
      decoration: BoxDecoration(
        color: effectiveBgColor,
        gradient: effectiveGradient,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(
          color: isDark
              ? context.colors.border
              : (presentation.period == GreetingPeriod.night
                  ? const Color(0xFF334155)
                  : const Color(0x1F000000)),
          width: 1.1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.md,
          vertical: 13,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 340;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Greeting Title & Supporting Message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${presentation.greetingText}, $userName 👋',
                        style: TextStyle(
                          fontFamily: GochanoTypography.fontFamily,
                          fontSize: isNarrow ? 16 : 18.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: effectiveTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        presentation.supportingMessage,
                        style: TextStyle(
                          fontFamily: GochanoTypography.fontFamily,
                          fontSize: isNarrow ? 11 : 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                          color: effectiveSubtitleColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: GochanoSpacing.sm),

                // Right: Time-of-day Icon Badge
                Container(
                  width: isNarrow ? 36 : 42,
                  height: isNarrow ? 36 : 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effectiveContainerColor,
                    border: Border.all(
                      color: effectiveTextColor.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    presentation.icon,
                    size: isNarrow ? 19 : 22,
                    color: effectiveIconColor,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
