import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'screens/auth/auth_gate.dart';

class EkThikanaApp extends StatelessWidget {
  const EkThikanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: EkTheme.light(),
      home: const AuthGate(),
    );
  }
}
