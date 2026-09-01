import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'core/design_system/gochano_spacing.dart';
import 'core/localization/gochano_language.dart';
import 'core/navigation.dart';
import 'core/settings/gochano_appearance.dart';
import 'firebase_options.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';

const String _kLogoAsset = 'assets/branding/Gochano.png';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  // Always start each cold launch with a fresh Navigator key. Without
  // this hook, a hot-restart on a developer build would reuse the same
  // `GlobalKey<NavigatorState>` instance for both the outgoing and the
  // incoming root `Navigator`, tripping Flutter's
  // "Duplicate GlobalKey detected" assertion.
  AppNavigation.resetForColdStart();

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

    // Restore the saved language and appearance *before* the first frame, so
    // the app does not paint in English/system and then visibly flip to the
    // student's choice. Both restores swallow their own failures and fall
    // back to the default, so neither can block startup.
    await Future.wait([
      GochanoLanguage.restore(),
      GochanoAppearance.restore(),
    ]);

    runApp(const GochanoApp());
    // Defer non-critical platform setup so the first frame paints sooner.
    // Notifications aren't required for the app to be usable, and the
    // permission prompt can take seconds on slow Android devices.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.init().catchError((_) {
        // Swallow - app stays usable even if notification setup fails.
        return Future<void>.value();
      });
      ConnectivityService.instance.init().catchError((_) {
        // Swallow - the offline banner falls back to "online" if the
        // platform channel is unavailable, so the app stays usable.
        return Future<void>.value();
      });
    });
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
                    Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: GochanoShadows.overlay,
                      ),
                      child: Image.asset(
                        _kLogoAsset,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        // Drawn at ~64 logical px inside an 80 px plate.
                        cacheWidth: 512,
                        semanticLabel: 'Gochano logo',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Gochano needs configuration',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
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
