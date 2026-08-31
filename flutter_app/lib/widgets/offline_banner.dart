// Gochano offline banner.
//
// A sticky top-of-screen banner that fades in whenever the device has no
// usable connectivity.  Lives inside the MaterialApp `builder:` so it
// overlays every screen (auth, splash->home, dialogs) without each screen
// having to wire it up.
//
// Design notes:
//   - Uses EkColors.orange (warn, not red) because offline is recoverable,
//     not destructive -- users can still read cached data, browse study
//     materials, etc.  A red error colour would imply the app is broken.
//   - Fade-in via AnimatedSwitcher so the banner does not pop abruptly
//     when the user walks through a tunnel for 2 seconds.
//   - Semantics label is one short sentence so TalkBack reads it once at
//     the top of every screen flip.
//   - Banner consumes SafeArea top padding so it does not collide with
//     notches on Android 13+ devices.
//   - Surface + text colors come from `_OfflineBannerPalette.of(context)`
//     so light and dark themes both render correctly without a per-mode
//     branch inside the widget itself.

import 'package:flutter/material.dart';

import '../core/language.dart';
import '../services/connectivity_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  static const Key _bannerKey = ValueKey('offline-banner-visible');
  static const Key _hiddenKey = ValueKey('offline-banner-hidden');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.online,
      builder: (context, isOnline, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: isOnline
              ? const SizedBox(
                  key: _hiddenKey,
                  width: double.infinity,
                  height: 0,
                )
              : _OfflineBannerSurface(key: _bannerKey, theme: theme),
        );
      },
    );
  }
}

class _OfflineBannerSurface extends StatelessWidget {
  const _OfflineBannerSurface({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final palette = _OfflineBannerPalette.of(context);

    return Semantics(
      container: true,
      liveRegion: true,
      label: EkLanguage.text(
        'You are offline. Showing cached data.',
        'আপনি অফলাইনে আছেন। ক্যাশ করা ডেটা দেখানো হচ্ছে।',
      ),
      child: Material(
        key: const Key('offline-banner-surface'),
        color: palette.surface,
        child: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 18,
                  color: palette.foreground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    EkLanguage.text(
                      'You are offline. Showing cached data.',
                      'আপনি অফলাইনে আছেন। ক্যাশ করা ডেটা দেখানো হচ্ছে।',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.foreground,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
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

class _OfflineBannerPalette {
  const _OfflineBannerPalette({required this.surface, required this.foreground});

  final Color surface;
  final Color foreground;

  static _OfflineBannerPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _OfflineBannerPalette(
      surface: dark ? const Color(0xFF3A2510) : const Color(0xFFFFE7CC),
      foreground: dark ? const Color(0xFFF1C26B) : const Color(0xFF6B3D00),
    );
  }
}

