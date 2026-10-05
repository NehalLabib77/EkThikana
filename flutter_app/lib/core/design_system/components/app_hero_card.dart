import 'package:flutter/material.dart';

import '../app_gradients.dart';
import '../gochano_spacing.dart';
import '../gochano_typography.dart';

/// Stat item definition for the hero card.
class HeroStatItem {
  const HeroStatItem({
    required this.icon,
    required this.value,
    this.label,
  });

  final IconData icon;
  final String value;
  final String? label;
}

/// The approved prominent Hero Card for Gochano Today.
///
/// Features a rich gradient, top urgency badge, bold title, supportive subtitle,
/// live metric pills, primary white CTA button, and optional illustration.
class AppHeroCard extends StatelessWidget {
  const AppHeroCard({
    super.key,
    required this.badgeText,
    this.badgeIcon = Icons.local_fire_department_rounded,
    this.badgeColor = const Color(0xFFFF9500),
    required this.title,
    required this.subtitle,
    required this.stats,
    required this.ctaLabel,
    required this.onCta,
    this.ctaIcon = Icons.play_arrow_rounded,
    this.gradient = AppGradients.examRescue,
    this.illustration,
  });

  final String badgeText;
  final IconData badgeIcon;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final List<HeroStatItem> stats;
  final String ctaLabel;
  final VoidCallback onCta;
  final IconData ctaIcon;
  final LinearGradient gradient;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332F6BFF),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Ambient background glow / decorations
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.cyan.withValues(alpha: 0.15),
              ),
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.all(GochanoSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 360;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Badge pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.sm,
                        vertical: GochanoSpacing.xxs + 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: const BorderRadius.all(Radius.circular(999)),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 14, color: badgeColor),
                          const SizedBox(width: 4),
                          Text(
                            badgeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: GochanoTypography.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: GochanoSpacing.sm),

                    // Title & Subtitle with optional right illustration
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  letterSpacing: -0.3,
                                  fontFamily: GochanoTypography.fontFamily,
                                ),
                              ),
                              const SizedBox(height: GochanoSpacing.xxs),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.90),
                                  fontSize: 13,
                                  height: 1.4,
                                  fontFamily: GochanoTypography.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (illustration != null && isWide) ...[
                          const SizedBox(width: GochanoSpacing.sm),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 110,
                              maxHeight: 110,
                            ),
                            child: illustration!,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: GochanoSpacing.md),

                    // Live stats chips row
                    if (stats.isNotEmpty) ...[
                      Wrap(
                        spacing: GochanoSpacing.sm,
                        runSpacing: GochanoSpacing.xs,
                        children: [
                          for (final stat in stats)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  stat.icon,
                                  size: 15,
                                  color: Colors.white.withValues(alpha: 0.95),
                                ),
                                const SizedBox(width: 5),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      stat.value,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: GochanoTypography.fontFamily,
                                      ),
                                    ),
                                    if (stat.label != null && stat.label!.isNotEmpty)
                                      Text(
                                        stat.label!,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.80),
                                          fontSize: 10,
                                          fontFamily: GochanoTypography.fontFamily,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: GochanoSpacing.md),
                    ],

                    // Primary CTA Button
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: onCta,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1E3A8A),
                          elevation: 2,
                          shadowColor: Colors.black.withValues(alpha: 0.25),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: GochanoSpacing.md + 4,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(ctaIcon, size: 18, color: const Color(0xFF1E3A8A)),
                            const SizedBox(width: 6),
                            Text(
                              ctaLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                                fontFamily: GochanoTypography.fontFamily,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Color(0xFF1E3A8A),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
