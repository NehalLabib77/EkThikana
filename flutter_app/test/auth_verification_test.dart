// Email verification flow guards.
//
// The behavior under test here is structural rather than behavioral
// (we do not boot a real Firebase SDK in unit tests). The intent is
// to fail loudly if a later edit re-introduces the bug that the
// verify-screen rewrite fixed:
//
//   * `AuthGate` must listen to `AuthService.authState()` — the merged
//     stream — not raw `auth.authStateChanges()`. The raw stream does
//     not emit on `emailVerified` flip; only the merged stream does.
//   * `VerifyEmailScreen` must drive verification detection from at
//     least one automatic source (lifecycle resume or polling), and
//     must never push to a home shell itself.
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
  group('AuthGate wiring', () {
    late String gateSource;

    setUpAll(() => gateSource =
        _read('lib/features/auth/presentation/auth_gate.dart'));

    test('listens to AuthService.authState() (merged stream)', () {
      expect(
        gateSource,
        contains("AuthService.authState()"),
        reason:
            'AuthGate must listen to the merged stream so the gate can see '
            'emailVerified flips — Firebase authStateChanges does not emit '
            'on its own when emailVerified changes.',
      );
    });

    test('does NOT listen to raw authStateChanges', () {
      // The gate should never directly subscribe to `firebase_auth`'s
      // raw stream, because that stream does not tick on emailVerified.
      expect(
        gateSource.contains('authStateChanges()'),
        isFalse,
        reason: 'AuthGate must go through AuthService.authState() — the raw '
            'stream does not emit on emailVerified flip.',
      );
    });

    test('routes on emailVerified from FirebaseAuth.currentUser', () {
      expect(gateSource, contains('emailVerified'));
    });
  });

  group('VerifyEmailScreen auto-detection', () {
    late String screenSource;

    setUpAll(() => screenSource =
        _read('lib/features/auth/presentation/verify_email_screen.dart'));

    test('observes AppLifecycleState.resumed', () {
      expect(
        screenSource,
        contains('AppLifecycleState.resumed'),
        reason:
            'When the user comes back from the mail app, the screen must '
            'kick a verification check immediately.',
      );
    });

    test('runs a periodic Timer poll', () {
      expect(
        screenSource.contains('Timer.periodic'),
        isTrue,
        reason:
            'A periodic poll is one of the three triggers that auto-detect '
            'verification while the screen is mounted.',
      );
    });

    test('cancels timers in dispose()', () {
      expect(
        screenSource,
        contains('_pollTimer?.cancel()'),
        reason: 'The poll timer must be cancelled when the screen unmounts.',
      );
      expect(screenSource, contains('dispose()'));
    });

    test('does NOT push to a home shell from the verify screen', () {
      // Routing must be the AuthGate's job, not the verify screen's.
      expect(screenSource.contains('GochanoShell'), isFalse);
      expect(screenSource.contains('Navigator.push'), isFalse);
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
