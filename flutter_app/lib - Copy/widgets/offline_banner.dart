// Offline banner (spec §77).
//
// A sticky top-of-screen strip shown whenever the device has no usable
// connectivity. It lives inside the MaterialApp `builder:`, so it overlays
// every screen and dialog without each one wiring it up.
//
// Warning tone, not error: being offline is recoverable and the student can
// still read what is already loaded. Painting it red would say the app is
// broken.
//
// It appears and disappears instantly. The previous version cross-faded over
// 220 ms via `AnimatedSwitcher`; that is decorative motion on a status
// indicator whose whole job is to be noticed immediately (spec §11, §12).

import 'package:flutter/material.dart';

import '../core/design_system/gochano_colors.dart';
import '../core/design_system/gochano_spacing.dart';
import '../core/design_system/gochano_typography.dart';
import '../core/localization/gochano_language.dart';
import '../services/connectivity_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  static const Key bannerKey = ValueKey('offline-banner-visible');
  static const Key hiddenKey = ValueKey('offline-banner-hidden');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.online,
      builder: (context, isOnline, _) {
        if (isOnline) {
          return const SizedBox(
            key: hiddenKey,
            width: double.infinity,
            height: 0,
          );
        }
        return const _OfflineBannerSurface(key: bannerKey);
      },
    );
  }
}

class _OfflineBannerSurface extends StatelessWidget {
  const _OfflineBannerSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = GochanoLanguage.text(
      'You are offline. Showing what is already loaded.',
      'আপনি অফলাইনে আছেন। যা আগে লোড হয়েছে তা দেখানো হচ্ছে।',
    );

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Material(
        key: const Key('offline-banner-surface'),
        color: colors.warningSoft,
        child: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.md,
              vertical: GochanoSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: GochanoSizes.iconSm,
                  color: colors.warning,
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      style: context.type.bodySecondary.copyWith(
                        color: colors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
