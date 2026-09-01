import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/design_system/gochano_theme.dart';
import 'core/localization/gochano_language.dart';
import 'core/navigation.dart';
import 'core/settings/gochano_appearance.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/shell/presentation/splash_screen.dart';
import 'widgets/notification_action_host.dart';
import 'widgets/offline_banner.dart';

/// The Gochano application root.
///
/// Two scopes sit above `MaterialApp`:
///
///   * [GochanoAppearanceScope] supplies `themeMode` from the student's saved
///     Light / Dark / Follow-system choice (spec §72). The app used to be
///     hardcoded to `ThemeMode.system` with no way to change it.
///
///   * [GochanoLanguageScope] rebuilds the entire tree on a language change.
///     Rebuilding from the root is what guarantees no subtree is left showing
///     the previous language — the "mixed-language accidental strings" spec
///     §73 warns about.
///
/// Both preferences are restored during bootstrap in `main()`, so the first
/// painted frame is already in the right language and theme rather than
/// flipping a moment later.
class GochanoApp extends StatelessWidget {
  const GochanoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoAppearanceScope(
      builder: (context, themeMode) => GochanoLanguageScope(
        builder: (context, locale) => MaterialApp(
          navigatorKey: AppNavigation.navigatorKey,
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: GochanoTheme.light(),
          darkTheme: GochanoTheme.dark(),
          themeMode: themeMode,
          locale: locale.locale,
          supportedLocales: [
            for (final value in GochanoLocale.values) value.locale,
          ],
          home: const _BootRouter(),
          // `builder:` wraps every route (including dialogs) so the offline
          // banner and the notification action host layer above any screen
          // without per-screen wiring.
          builder: (context, child) {
            final body = child ?? const SizedBox.shrink();
            return NotificationActionHost(
              child: Stack(
                children: [
                  Positioned.fill(child: body),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: OfflineBanner(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Boots the branded splash and, as soon as real initialization completes,
/// hands control to [AuthGate].
///
/// We deliberately avoid `Navigator.pushReplacement` here. The splash and
/// AuthGate are both rendered as the single `home:` child of MaterialApp.
/// The splash calls `onReady` when it is finished, which flips
/// [_BootRouterState._ready]; the next rebuild swaps the body to [AuthGate]
/// inside the same Navigator slot, with no route transition.
///
/// That pattern is what avoids the `'!_debugLocked'` assertion in
/// navigator.dart, and the companion `'scope != null'` assertion in
/// routes.dart, that fired when the splash route was popped while its
/// fade-out was still in progress.
class _BootRouter extends StatefulWidget {
  const _BootRouter();

  @override
  State<_BootRouter> createState() => _BootRouterState();
}

class _BootRouterState extends State<_BootRouter> {
  bool _ready = false;

  void _handleReady() {
    if (_ready) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ready) return;
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ready
        ? const AuthGate()
        : GochanoSplashScreen(onReady: _handleReady);
  }
}
