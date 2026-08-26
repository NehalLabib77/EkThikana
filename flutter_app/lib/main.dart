import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  try {
    AppConfig.validateRelease();
  } on StateError catch (e) {
    runApp(_SetupRequiredApp(error: e));
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      await NotificationService.init();
    } catch (_) {
      // The app remains usable if OS notification setup is incomplete.
    }
    runApp(const GochanoApp());
  } catch (e) {
    runApp(_SetupRequiredApp(error: e));
  }
}

class _SetupRequiredApp extends StatelessWidget {
  const _SetupRequiredApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const Icon(Icons.home_work_outlined, size: 72),
                    const SizedBox(height: 16),
                    const Text(
                      'Gochano needs configuration',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Run flutterfire configure or rebuild with the correct --dart-define flags as described in docs/START_HERE.md.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(error.toString()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
