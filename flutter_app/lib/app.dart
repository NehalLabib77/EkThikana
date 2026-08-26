import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/navigation.dart';
import 'core/theme.dart';
import 'screens/auth/auth_gate.dart';
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
      home: const AuthGate(),
      builder: (context, child) => NotificationActionHost(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
