import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/services/dev_auth_config.dart';
import 'package:gochano/core/services/telecom_auth_service.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  // -------------------------------------------------------------------
  // 1. Dev login requires kDebugMode AND DEV_AUTH_BYPASS
  // -------------------------------------------------------------------

  group('Developer auth double gate', () {
    test('pure truth table: both must be true', () {
      expect(devAuthEnabledFor(debugMode: true, bypass: true), isTrue);
      expect(devAuthEnabledFor(debugMode: true, bypass: false), isFalse);
      expect(devAuthEnabledFor(debugMode: false, bypass: true), isFalse);
      expect(devAuthEnabledFor(debugMode: false, bypass: false), isFalse);
    });

    test('source contains compile-time const gate expression', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      expect(source, contains('kDebugMode && _devAuthBypass'));
    });

    test('source uses bool.fromEnvironment for DEV_AUTH_BYPASS', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      expect(source, contains("bool.fromEnvironment("));
      expect(source, contains("'DEV_AUTH_BYPASS'"));
      expect(source, contains('defaultValue: false'));
    });

    test('devLogin throws StateError when disabled', () {
      expect(
        () => devLogin(),
        throwsA(isA<StateError>()),
      );
    });

    test('devLoginStateError message mentions production', () async {
      try {
        await devLogin();
        fail('Should have thrown');
      } on StateError catch (e) {
        expect(e.toString(), contains('production'));
      }
    });
  });

  // -------------------------------------------------------------------
  // 2. Normal login routing remains unchanged
  // -------------------------------------------------------------------

  group('Normal telecom routing unchanged', () {
    TelecomSubscriptionResult r(String body) {
      return TelecomAuthService.parseSubscriptionResponseForTest(body);
    }

    test('REGISTERED → shouldEnterApp=true, maySendOtp=false', () {
      final result = r('{"subscriptionStatus":"REGISTERED"}');
      expect(result.shouldEnterApp, isTrue);
      expect(result.maySendOtp, isFalse);
      expect(result.status, TelecomSubscriptionStatus.registered);
    });

    test('NOT SUBSCRIBED → shouldEnterApp=false, maySendOtp=true', () {
      final result = r('{"subscriptionStatus":"NOT SUBSCRIBED"}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isTrue);
      expect(result.status, TelecomSubscriptionStatus.notSubscribed);
    });

    test('TEMPORARY BLOCKED → shouldEnterApp=false, maySendOtp=false', () {
      final result =
          r('{"subscriptionStatus":"TEMPORARY BLOCKED","isSubscribed":false}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
      expect(result.status, TelecomSubscriptionStatus.temporaryBlocked);
    });

    test('UNKNOWN → shouldEnterApp=false, maySendOtp=false', () {
      final result = r('{"subscriptionStatus":"WEIRD NEW STATUS"}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
      expect(result.status, TelecomSubscriptionStatus.unknown);
    });

    test('source _continue still calls checkSubscription', () {
      final source = _read('lib/features/auth/presentation/login_screen.dart');
      expect(source, contains('TelecomAuthService.checkSubscription('));
    });
  });

  // -------------------------------------------------------------------
  // 3. Developer Login does not call telecom endpoints
  // -------------------------------------------------------------------

  group('Developer Login does not call telecom endpoints', () {
    late String devSource;

    setUpAll(() {
      devSource = _read('lib/core/services/dev_auth_config.dart');
    });

    test('dev_auth_config has no telecom endpoint strings', () {
      expect(devSource, isNot(contains('check_subscription.php')));
      expect(devSource, isNot(contains('send_otp.php')));
      expect(devSource, isNot(contains('verify_otp.php')));
      expect(devSource, isNot(contains('/v1/auth/telecom/exchange')));
      expect(devSource, isNot(contains('exchangeSubscriptionForFirebaseSession')));
    });

    test('dev_auth_config has no signInWithCustomToken', () {
      expect(devSource, isNot(contains('signInWithCustomToken')));
    });

    test('dev_auth_config uses signInWithEmailAndPassword', () {
      expect(devSource, contains('signInWithEmailAndPassword'));
    });

    test('_devLogin method does not call checkSubscription', () {
      final loginSource =
          _read('lib/features/auth/presentation/login_screen.dart');
      final devStart = loginSource.indexOf('Future<void> _devLogin()');
      expect(devStart, greaterThanOrEqualTo(0));
      final devEnd = loginSource.indexOf('String? _validatePhone', devStart);
      final devBody = loginSource.substring(devStart, devEnd);
      expect(devBody, isNot(contains('checkSubscription')));
      expect(devBody, isNot(contains('sendOtp')));
      expect(devBody, isNot(contains('verifyOtp')));
      expect(devBody, isNot(contains('exchangeSubscriptionForFirebaseSession')));
      expect(devBody, isNot(contains('signInWithCustomToken')));
    });
  });

  // -------------------------------------------------------------------
  // 4. Developer Login requires Firebase sign-in
  // -------------------------------------------------------------------

  group('Developer Login requires Firebase sign-in', () {
    test('dev_auth_config calls signInWithEmailAndPassword', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      expect(source, contains('FirebaseAuth.instance.signInWithEmailAndPassword'));
    });

    test('dev_auth_config calls getIdToken(true)', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      expect(source, contains('getIdToken(true)'));
    });

    test('dev_auth_config checks emailVerified', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      expect(source, contains('emailVerified'));
    });

    test('_devLogin calls checkProfileState after Firebase sign-in', () {
      final source =
          _read('lib/features/auth/presentation/login_screen.dart');
      final devStart = source.indexOf('Future<void> _devLogin()');
      final devEnd = source.indexOf('String? _validatePhone', devStart);
      final devBody = source.substring(devStart, devEnd);
      expect(devBody, contains('FirestoreService.checkProfileState()'));
    });

    test('_devLogin checks currentUser null after sign-in', () {
      final source =
          _read('lib/features/auth/presentation/login_screen.dart');
      final devStart = source.indexOf('Future<void> _devLogin()');
      final devEnd = source.indexOf('String? _validatePhone', devStart);
      final devBody = source.substring(devStart, devEnd);
      final signInIdx = devBody.indexOf('devLogin()');
      final nullGuardIdx = devBody.indexOf('currentUser == null');
      expect(signInIdx, greaterThanOrEqualTo(0));
      expect(nullGuardIdx, greaterThan(signInIdx),
          reason: 'currentUser null check must come after devLogin()');
    });

    test('_devLogin calls persistSession for AuthGate compatibility', () {
      final source =
          _read('lib/features/auth/presentation/login_screen.dart');
      final devStart = source.indexOf('Future<void> _devLogin()');
      final devEnd = source.indexOf('String? _validatePhone', devStart);
      final devBody = source.substring(devStart, devEnd);
      expect(devBody, contains('TelecomAuthService.persistSession'));
    });
  });

  // -------------------------------------------------------------------
  // 5. Release/profile build cannot expose Developer Login
  // -------------------------------------------------------------------

  group('Release/profile build cannot expose Developer Login', () {
    test('button is inside if (isDevAuthEnabled) guard', () {
      final source =
          _read('lib/features/auth/presentation/login_screen.dart');
      final buttonIdx = source.indexOf("label: const Text('Developer Login')");
      expect(buttonIdx, greaterThanOrEqualTo(0));
      final guardIdx = source.lastIndexOf('if (isDevAuthEnabled)', buttonIdx);
      expect(guardIdx, greaterThanOrEqualTo(0),
          reason: 'Developer Login button must be inside isDevAuthEnabled guard');
    });

    test('pure gate returns false when debugMode is false', () {
      expect(devAuthEnabledFor(debugMode: false, bypass: true), isFalse);
    });

    test('pure gate returns false when bypass is false', () {
      expect(devAuthEnabledFor(debugMode: true, bypass: false), isFalse);
    });

    test('pure gate returns false when both are false', () {
      expect(devAuthEnabledFor(debugMode: false, bypass: false), isFalse);
    });

    test('source has kDebugMode in const expression', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      expect(source, contains('const bool devAuthEnabled = kDebugMode'));
    });
  });

  // -------------------------------------------------------------------
  // 6. No hardcoded test credentials in source
  // -------------------------------------------------------------------

  group('No hardcoded test credentials in source', () {
    test('lib/core/services has no email addresses', () {
      final dir = Directory('lib/core/services');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final emailRegex =
          RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
      for (final file in files) {
        final content = file.readAsStringSync();
        final matches = emailRegex.allMatches(content);
        final realMatches = matches.where((m) {
          final matched = m.group(0)!;
          return !matched.contains('@example') &&
              !matched.contains('@placeholder') &&
              !matched.contains('@override') &&
              !matched.contains('@drawable');
        });
        expect(realMatches, isEmpty,
            reason: '${file.path} contains a hardcoded email address');
      }
    });

    test('dev_auth_config uses String.fromEnvironment for credentials', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      expect(source, contains("String.fromEnvironment('DEV_TEST_EMAIL')"));
      expect(source, contains("String.fromEnvironment('DEV_TEST_PASSWORD')"));
    });

    test('dev_auth_config has no hardcoded password assignment', () {
      final source = _read('lib/core/services/dev_auth_config.dart');
      final lines = source.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        final lower = trimmed.toLowerCase();
        final hasPassword =
            lower.contains('password') &&
            (lower.contains('=') || lower.contains(':'));
        if (hasPassword) {
          final isAssignment = RegExp(
            r'''password\s*[:=]\s*['"]''',
          ).hasMatch(trimmed);
          expect(
            isAssignment,
            isFalse,
            reason: 'No hardcoded password in: $trimmed',
          );
        }
      }
    });

    test('no Firebase custom token is hardcoded', () {
      final devSource = _read('lib/core/services/dev_auth_config.dart');
      expect(devSource, isNot(contains('customToken')));
      expect(devSource, isNot(contains('signInWithCustomToken')));
    });

    test('no password is logged', () {
      final devSource = _read('lib/core/services/dev_auth_config.dart');
      expect(devSource, isNot(contains('debugPrint')));
      expect(devSource, isNot(contains('print(')));
      expect(devSource, isNot(contains('_debugLog')));
    });
  });

  // -------------------------------------------------------------------
  // 7. No direct GochanoShell navigation before Firebase auth succeeds
  // -------------------------------------------------------------------

  group('No direct GochanoShell navigation before Firebase auth', () {
    test('_devLogin: devLogin() before GochanoShell', () {
      final source =
          _read('lib/features/auth/presentation/login_screen.dart');
      final devStart = source.indexOf('Future<void> _devLogin()');
      final devEnd = source.indexOf('String? _validatePhone', devStart);
      final devBody = source.substring(devStart, devEnd);
      final signInIdx = devBody.indexOf('devLogin()');
      final shellIdx = devBody.indexOf('GochanoShell(');
      expect(signInIdx, lessThan(shellIdx),
          reason: 'Firebase sign-in must occur before GochanoShell navigation');
    });

    test('_devLogin: currentUser null check before GochanoShell', () {
      final source =
          _read('lib/features/auth/presentation/login_screen.dart');
      final devStart = source.indexOf('Future<void> _devLogin()');
      final devEnd = source.indexOf('String? _validatePhone', devStart);
      final devBody = source.substring(devStart, devEnd);
      final nullGuardIdx = devBody.indexOf('currentUser == null');
      final shellIdx = devBody.indexOf('GochanoShell(');
      expect(nullGuardIdx, lessThan(shellIdx),
          reason: 'currentUser null guard must precede GochanoShell');
    });

    test('_devLogin: profile check before GochanoShell', () {
      final source =
          _read('lib/features/auth/presentation/login_screen.dart');
      final devStart = source.indexOf('Future<void> _devLogin()');
      final devEnd = source.indexOf('String? _validatePhone', devStart);
      final devBody = source.substring(devStart, devEnd);
      final profileIdx = devBody.indexOf('checkProfileState()');
      final shellIdx = devBody.indexOf('GochanoShell(');
      expect(profileIdx, lessThan(shellIdx),
          reason: 'Profile check must precede GochanoShell navigation');
    });
  });

  // -------------------------------------------------------------------
  // 8. AuthGate remains production dual gate
  // -------------------------------------------------------------------

  group('AuthGate remains production dual gate', () {
    test('AuthGate requires readIsLoggedIn AND currentUser', () {
      final source =
          _read('lib/features/auth/presentation/auth_gate.dart');
      expect(source, contains('readIsLoggedIn'));
      expect(source, contains('currentUser'));
      expect(source, contains('GochanoShell('));
    });

    test('AuthGate does not reference dev auth', () {
      final source =
          _read('lib/features/auth/presentation/auth_gate.dart');
      expect(source, isNot(contains('DEV_AUTH_BYPASS')));
      expect(source, isNot(contains('isDevAuthEnabled')));
      expect(source, isNot(contains('dev_auth_config')));
      expect(source, isNot(contains('devLogin')));
    });
  });

  // -------------------------------------------------------------------
  // 9. DevLoginOutcome data class
  // -------------------------------------------------------------------

  group('DevLoginOutcome', () {
    test('success constructor', () {
      const outcome = DevLoginOutcome.success();
      expect(outcome.success, isTrue);
      expect(outcome.errorMessage, isNull);
    });

    test('missingCredentials constructor', () {
      const outcome = DevLoginOutcome.missingCredentials();
      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, isNull);
    });

    test('firebaseError constructor', () {
      const outcome = DevLoginOutcome.firebaseError('test error');
      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, 'test error');
    });
  });
}
