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
/// hands control to [AuthGate]. We use pushReplacement so the splash is
/// removed from the navigation stack and cannot be revisited via the system
/// back button. There is no artificial delay here - the splash's own
/// fade-out animation is the only transition; the app opens immediately
/// after real initialization finishes (bounded by a hard timeout inside
/// GochanoSplashScreen).
class _BootRouter extends StatelessWidget {
  const _BootRouter();

  @override
  Widget build(BuildContext context) {
    return GochanoSplashScreen(
      onReady: () async {
        if (!context.mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        );
      },
    );
  }
}
