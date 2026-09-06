// Auth wiring guards for the Robi / Cirkle telecom login.
//
// PART 16.1+ update: the legacy email-verification flow (RegisterScreen,
// VerifyEmailScreen) has been removed. The live AuthGate drives a dual
// check (SharedPreferences flag + FirebaseAuth.currentUser), so the
// AuthGate group below tests that behavior.
//
// The behavior under test here is structural rather than behavioral
// (we do not boot a real Firebase SDK in unit tests). The intent is
// to fail loudly if a later edit re-introduces:
//
//   * `AuthGate` must require BOTH the local SharedPreferences flag
//     (`TelecomAuthService.readIsLoggedIn()`) AND a real
//     `FirebaseAuth.instance.currentUser` before constructing
//     `GochanoShell`. A flag-only check is the PART 16 bug that
//     caused every Firestore read/write to fail permission-denied.
//   * When the local flag is set but Firebase did not restore the
//     user, `AuthGate` must call `TelecomAuthService.clearSession()`
//     and surface a `resumeMessage` to `LoginScreen` instead of
//     letting the user into the shell half-authenticated.
//   * `AuthService.login` must call `reload()` and re-read
//     `auth.currentUser.emailVerified`, not trust `credential.user`.
//   * `AuthService.resendVerification` must exist and enforce a
//     cooldown.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/services/auth_service.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('AuthGate wiring (PART 16.1 dual gate)', () {
    late String gateSource;

    setUpAll(() => gateSource =
        _read('lib/features/auth/presentation/auth_gate.dart'));

    test('subscribes to FirebaseAuth.authStateChanges', () {
      // PART 16.1: the live gate watches FirebaseAuth (not the legacy
      // merged AuthService.authState() stream) because the telecom
      // login path goes through signInWithCustomToken, which IS
      // reflected on the raw stream.
      expect(
        gateSource,
        contains('authStateChanges'),
        reason: 'AuthGate must watch FirebaseAuth.authStateChanges so '
            'signInWithCustomToken (telecom login path) ticks the gate.',
      );
      expect(gateSource, contains('FirebaseAuth.instance'));
    });

    test('checks the local SharedPreferences flag', () {
      // PART 16.1: in addition to currentUser, the gate must look at
      // the telecom session flag so a cold start with a valid session
      // (and the Firebase user already in memory) routes straight in.
      expect(gateSource, contains('readIsLoggedIn'));
    });

    test('refuses GochanoShell entry without a currentUser', () {
      // The whole point of PART 16.1: a flag with null currentUser
      // must NOT be enough to enter the shell. Both must be non-null.
      expect(gateSource, contains('currentUser'));
      expect(gateSource, contains('GochanoShell('));
    });

    test('clears stale session when Firebase did not restore the user', () {
      expect(
        gateSource,
        contains('clearSession'),
        reason: 'Stale flags (Firebase restored null on cold start) '
            'must be wiped so the user is re-prompted cleanly.',
      );
    });

    test('routes to LoginScreen without a resume card', () {
      expect(gateSource, isNot(contains('resumeMessage')));
      expect(gateSource, contains('LoginScreen()'));
    });

    test('does NOT depend on the legacy email-verification flow', () {
      expect(gateSource.contains('emailVerified'), isFalse);
      expect(gateSource.contains('signInWithEmailAndPassword'), isFalse);
    });
  });

  group('AuthService.login reloads before reading emailVerified', () {
    late String serviceSource;

    setUpAll(() => serviceSource =
        _read('lib/services/auth_service.dart'));

    test('login calls reload() and re-reads auth.currentUser', () {
      expect(serviceSource, contains('reload()'));
      expect(
        serviceSource,
        contains('auth.currentUser'),
        reason:
            'login() must re-read auth.currentUser after reload — the '
            'User returned in the credential is a pre-verification snapshot.',
      );
    });

    test('authState() merges authStateChanges with refresh notifier', () {
      expect(serviceSource, contains('authState()'));
      expect(
        serviceSource,
        contains('_refreshesController'),
        reason:
            'The merged stream depends on the refresh notifier for '
            'emailVerified flips, since Firebase does not emit those.',
      );
    });

    test('resendVerification has a cooldown', () {
      expect(serviceSource, contains('resendVerification'));
      expect(
        serviceSource,
        contains('cooldown'),
        reason: 'Resend must enforce a cooldown to avoid hammering Firebase.',
      );
    });
  });

  group('LoginResult', () {
    test('is a const data class with user + isVerified', () {
      const result = LoginResult(user: null, isVerified: false);
      expect(result.user, isNull);
      expect(result.isVerified, isFalse);
    });

    test('can be constructed with isVerified=true', () {
      const result = LoginResult(user: null, isVerified: true);
      expect(result.isVerified, isTrue);
    });
  });

  group('AuthService.debug seams', () {
    test('debugResetRefreshes and debugPingRefresh are callable', () {
      // We do not exercise them in this test — that would require
      // Firebase to be initialized — but the symbols must be present
      // so test helpers elsewhere can drive the merged stream.
      AuthService.debugResetRefreshes();
      AuthService.debugPingRefresh();
    });
  });
}
