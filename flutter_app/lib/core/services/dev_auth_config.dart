// TEMPORARY DEVELOPMENT ACCESS.
// Remove before final release, or leave permanently disabled because
// kDebugMode prevents activation in release builds.
//
// This file provides a debug-only developer authentication path that
// bypasses the telecom/subscription flow. It can ONLY activate when
// ALL THREE conditions are met:
//
//   1. kDebugMode == true  (compile-time constant — false in release/profile)
//   2. --dart-define=DEV_AUTH_BYPASS=true  (runtime flag)
//   3. --dart-define=DEV_TEST_EMAIL=... and DEV_TEST_PASSWORD=...
//
// In release builds, isDevAuthEnabled is ALWAYS false regardless of
// dart-defines, because kDebugMode is a compile-time constant that
// the Dart compiler eliminates in release/profile mode.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Double-gated developer authentication flag.
///
/// `kDebugMode` is a compile-time constant: `true` in debug mode,
/// `false` in profile and release builds. The Dart compiler
/// eliminates the dead code path in non-debug builds, so even if
/// someone passes `--dart-define=DEV_AUTH_BYPASS=true` to a release
/// build, this getter still returns `false`.
const bool _devAuthBypass = bool.fromEnvironment(
  'DEV_AUTH_BYPASS',
  defaultValue: false,
);

/// Whether developer auth is enabled for the supplied build conditions.
///
/// This pure function makes the security contract explicit and testable:
/// both inputs must be true. Production uses [kDebugMode] and the
/// compile-time [DEV_AUTH_BYPASS] dart-define as those inputs.
bool devAuthEnabledFor({required bool debugMode, required bool bypass}) =>
    debugMode && bypass;

/// Compile-time developer auth availability.
///
/// Returns `true` ONLY when the app is compiled in debug mode
/// (`kDebugMode == true`) AND the `DEV_AUTH_BYPASS` dart-define
/// is set to `true`.
///
/// In release/profile builds, this is always `false` because
/// `kDebugMode` is `false` and the Dart compiler optimises away
/// the check.
const bool devAuthEnabled = kDebugMode && _devAuthBypass;

/// Runtime alias for code that prefers a getter.
bool get isDevAuthEnabled => devAuthEnabled;

/// Read-only dart-define values for the Firebase test account.
///
/// These are ONLY read when [isDevAuthEnabled] is true. In release
/// builds they are never accessed.
const String _devTestEmail = String.fromEnvironment('DEV_TEST_EMAIL');
const String _devTestPassword = String.fromEnvironment('DEV_TEST_PASSWORD');

/// Whether the dev-test email and password are provided.
bool get _hasDevCredentials =>
    _devTestEmail.isNotEmpty && _devTestPassword.isNotEmpty;

/// Outcome of a developer login attempt.
class DevLoginOutcome {
  /// Developer login succeeded. FirebaseAuth.currentUser is non-null.
  const DevLoginOutcome.success()
      : success = true,
        errorMessage = null;

  /// DEV_TEST_EMAIL or DEV_TEST_PASSWORD dart-defines are missing.
  const DevLoginOutcome.missingCredentials()
      : success = false,
        errorMessage = null;

  /// Firebase rejected the credentials or another error occurred.
  const DevLoginOutcome.firebaseError(String message)
      : success = false,
        errorMessage = message;

  final bool success;
  final String? errorMessage;
}

/// Perform developer login using Firebase email/password authentication.
///
/// This is a completely separate path from the telecom flow. It does NOT
/// call any telecom subscription or OTP endpoints.
///
/// Returns a [DevLoginOutcome] indicating success or failure.
///
/// Throws [StateError] if called when [isDevAuthEnabled] is false.
Future<DevLoginOutcome> devLogin() async {
  if (!isDevAuthEnabled) {
    throw StateError(
      'devLogin() called but dev auth is not enabled. '
      'This should never happen in production.',
    );
  }
  if (!_hasDevCredentials) {
    return DevLoginOutcome.missingCredentials();
  }

  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _devTestEmail,
      password: _devTestPassword,
    );
  } on FirebaseAuthException catch (e) {
    return DevLoginOutcome.firebaseError(e.message ?? 'Firebase sign-in failed');
  } catch (e) {
    return DevLoginOutcome.firebaseError(e.toString());
  }

  // Verify the sign-in actually produced a verified test user.
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return DevLoginOutcome.firebaseError(
      'Sign-in succeeded but no user found',
    );
  }
  if (!user.emailVerified) {
    return DevLoginOutcome.firebaseError(
      'Firebase test account email is not verified',
    );
  }

  // Refresh the ID token so downstream Firestore rules that check
  // verified() / email_verified pass.
  try {
    await user.getIdToken(true);
  } catch (_) {
    // Best-effort token refresh — non-fatal.
  }

  return DevLoginOutcome.success();
}
