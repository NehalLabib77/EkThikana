import 'package:flutter/material.dart';

import '../../localization/gochano_language.dart';
import '../../page_route.dart';
import '../../../../features/notifications/presentation/notification_center_screen.dart';
import '../../../../features/search/presentation/universal_search_screen.dart';
import '../../../../services/local_reminder_store.dart';
import '../../../../widgets/language_toggle.dart';
import '../app_assets.dart';
import '../app_gradients.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';

/// The approved fixed top header for Study Mode (Today, Workspace, Plan).
///
/// Features:
/// - Compact floating gradient surface (~46dp visual height)
/// - Responsive horizontal inset (14dp normal, 10dp < 340dp width)
/// - 4dp outer vertical margin, 4dp inner vertical padding
/// - 18dp rounded corners (`GochanoRadius.appBarSurfaceAll`)
/// - Circular logo mark only (30dp normal, 28dp narrow) - zero Gochano text, zero tagline, zero avatar
/// - Compact Language toggle (`EN | বাংলা`, 26dp visual height, >=44dp hit area)
/// - Search icon (32dp visual container, 44x44dp hit area)
/// - Notification icon with unread badge (32dp visual container, 44x44dp hit area)
/// - Pinned outside scrollable viewport.
class AppStudyHeader extends StatelessWidget {
  const AppStudyHeader({
    super.key,
    this.onSearchTap,
    this.onNotificationTap,
  });

  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalInset = constraints.maxWidth < 340 ? 10.0 : 14.0;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: 4.0,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: AppGradients.todayAppBarFor(isDark: isDark),
              borderRadius: GochanoRadius.appBarSurfaceAll,
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
                        color: Color(0x0D000000), // Soft light-mode shadow (5% black)
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.md,
              vertical: 4.0,
            ),
            child: _buildContent(context, constraints.maxWidth),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, double maxWidth) {
    final isVeryNarrow = maxWidth < 340;
    final logoSize = isVeryNarrow ? 28.0 : 30.0;

    return Row(
      children: [
        // LEFT: Compact logo mark only (no "Gochano" text, no tagline)
        Container(
          width: logoSize,
          height: logoSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            AppAssets.logo,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.school_rounded,
              color: const Color(0xFF2F6BFF),
              size: isVeryNarrow ? 18 : 20,
            ),
          ),
        ),

        const Spacer(),

        // RIGHT: Controls
        const LanguageToggle(isCompact: true),
        const SizedBox(width: 2),

        // Search icon (32dp visual container, 44x44dp effective touch target)
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            onPressed: onSearchTap ??
                () {
                  Navigator.of(context).push(
                    GochanoRoute.to(builder: (_) => const UniversalSearchScreen()),
                  );
                },
            tooltip: GochanoLanguage.text('Search', 'অনুসন্ধান'),
            icon: Icon(Icons.search_rounded, size: isVeryNarrow ? 19 : 20),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),

        // Notifications with badge (32dp visual, 44x44dp effective touch target)
        ValueListenableBuilder<int>(
          valueListenable: LocalReminderStore.instance.unreadCountNotifier,
          builder: (context, unreadCount, _) {
            return SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: onNotificationTap ??
                        () {
                          Navigator.of(context).push(
                            GochanoRoute.to(
                              builder: (_) => const NotificationCenterScreen(),
                            ),
                          );
                        },
                    tooltip: GochanoLanguage.text(
                      'Notification Center',
                      'নোটিফিকেশন সেন্টার',
                    ),
                    icon: Icon(
                      Icons.notifications_outlined,
                      size: isVeryNarrow ? 19 : 20,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

