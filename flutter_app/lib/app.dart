import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/navigation.dart';
import 'core/theme.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/system/gochano_splash_screen.dart';
import 'widgets/notification_action_host.dart';

class GochanoApp extends StatelessWidget {
  const GochanoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigation.navigatorKey,
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: EkTheme.light(),
      darkTheme: EkTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _BootRouter(),
      builder: (context, child) =>
          NotificationActionHost(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Boots the branded splash and, as soon as real initialization completes,
/// hands control to [AuthGate].
///
/// We deliberately avoid `Navigator.pushReplacement` here. The splash and
/// AuthGate are both rendered as the single `home:` child of MaterialApp.
/// The splash calls [onReady] when it has finished its fade-out animation,
/// which flips [_BootRouter._ready]. The next rebuild swaps the body to
/// [AuthGate] inside the same Navigator slot, with no route transition.
///
/// This pattern is what avoids the
/// `'package:flutter/src/widgets/navigator.dart': Failed assertion:
/// line 5909 pos 12: '!_debugLocked': is not true.` runtime error and the
/// companion `'scope != null'` assertion in routes.dart that fired when
/// the splash route was popped while its fade-out animation was still in
/// progress.
class _BootRouter extends StatefulWidget {
  const _BootRouter();

  @override
  State<_BootRouter> createState() => _BootRouterState();
}

class _BootRouterState extends State<_BootRouter> {
  bool _ready = false;

  void _handleReady() {
    // The splash invokes [onReady] from inside its build cycle. Defer the
    // ready flip until the current frame has been laid out so setState never
    // runs during a build of a different widget. Without this deferral the
    // splash can deadlock against `_debugLocked` / `_debugBuildingDirtyElements`
    // and leave the user staring at the dark splash background forever.
    WidgetsBinding.instance.addPostFrameCallback((_) => _flipReady());
  }

  void _flipReady() {
    if (!mounted || _ready) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return _ready
        ? const AuthGate()
        : GochanoSplashScreen(onReady: _handleReady);
  }
}
