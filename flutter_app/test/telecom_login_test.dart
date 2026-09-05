// Robi / Cirkle telecom login flow (PART 16.1).
//
// PART 16.1 — corrected assertion shape. PART 16 had:
//   * wrong API contracts (used `phone` instead of `user_mobile`,
//     simplified verify_otp body, missed subscriptionStatus field,
//     missed E1351 polling)
//   * an AuthGate that let the user into GochanoShell with
//     FirebaseAuth.currentUser == null (causing
//     `permission-denied` on every Firestore read/write)
//
// This file fails loudly if a later edit re-introduces:
//
//   * an email/password field in login_screen.dart
//   * an Airtel or SmartList string anywhere in the new auth UI
//   * the PART 16 wrong-body bug (`{phone: ...}` instead of
//     `{user_mobile: ...}`)
//   * the PART 16 simplified verify_otp.php body (must keep
//     duplicate Otp/otp/referenceNo/reference_no keys)
//   * an AuthGate that lets the user into GochanoShell with
//     `FirebaseAuth.instance.currentUser == null`
//   * a validator that lets unsupported prefixes through
//   * a non-Robi/Cirkle branding copy on the OTP screen

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/services/telecom_auth_service.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('TelecomAuthService prefix validation', () {
    test('accepts Robi 016 numbers', () {
      expect(TelecomAuthService.isSupportedPhone('01612345678'), isTrue);
    });

    test('accepts Cirkle 018 numbers', () {
      expect(TelecomAuthService.isSupportedPhone('01812345678'), isTrue);
    });

    test('rejects unsupported 017 (GP) numbers', () {
      expect(TelecomAuthService.isSupportedPhone('01712345678'), isFalse);
    });

    test('rejects unsupported 019 (Banglalink) numbers', () {
      expect(TelecomAuthService.isSupportedPhone('01912345678'), isFalse);
    });

    test('rejects 015 (Teletalk) numbers', () {
      expect(TelecomAuthService.isSupportedPhone('01512345678'), isFalse);
    });

    test('rejects empty input', () {
      expect(TelecomAuthService.isSupportedPhone(''), isFalse);
    });

    test('rejects too-short input', () {
      expect(TelecomAuthService.isSupportedPhone('01612345'), isFalse);
    });

    test('rejects too-long input', () {
      expect(TelecomAuthService.isSupportedPhone('016123456789'), isFalse);
    });

    test('rejects non-digit input', () {
      expect(TelecomAuthService.isSupportedPhone('0161234567a'), isFalse);
    });

    test('trims whitespace before validating', () {
      expect(TelecomAuthService.isSupportedPhone('  01612345678  '), isTrue);
    });
  });

  group('TelecomAuthService SharedPreferences keys', () {
    test('primary keys are isLoggedIn / userPhone (not telecom_*)', () {
      expect(TelecomAuthService.prefIsLoggedIn, 'isLoggedIn');
      expect(TelecomAuthService.prefUserPhone, 'userPhone');
    });
  });

  group('TelecomSubscriptionResult', () {
    test('registered result allows entering the app', () {
      const r = TelecomSubscriptionResult.registered;
      expect(r.shouldEnterApp, isTrue);
      expect(r.status, TelecomSubscriptionStatus.registered);
    });

    test('initialChargingPending result also allows entering the app', () {
      const r = TelecomSubscriptionResult.initialChargingPending;
      expect(r.shouldEnterApp, isTrue);
      expect(r.status, TelecomSubscriptionStatus.initialChargingPending);
    });

    test('notSubscribed result requires OTP', () {
      const r = TelecomSubscriptionResult.notSubscribed;
      expect(r.shouldEnterApp, isFalse);
      expect(r.status, TelecomSubscriptionStatus.notSubscribed);
    });
  });

  group('TelecomAuthService source contract (PART 16.1)', () {
    late String source;

    setUpAll(() => source =
        _read('lib/core/services/telecom_auth_service.dart'));

    test('uses user_mobile (NOT phone) in check_subscription body', () {
      // The PART 16 bug was sending {"phone": ...} instead of
      // {"user_mobile": ...}. The map literal in checkSubscription must
      // contain `user_mobile` and must NOT contain a bare `phone` key
      // (the only legitimate `phone` uses are inside the
      // exchangeOtpForFirebaseSession / exchangeSubscription body, where
      // it is paired with `reference_no` / `already_subscribed`).
      final bodyLiteral =
          RegExp(r"\{[^}]*'user_mobile'[^}]*\}", multiLine: true).firstMatch(source);
      expect(bodyLiteral, isNotNull,
          reason: 'check_subscription must POST {user_mobile: phone}');
      expect(bodyLiteral!.group(0)!.contains("'phone'"), isFalse,
          reason:
              'check_subscription body must not include a bare `phone` key');
    });

    test('uses user_mobile in send_otp body', () {
      final bodyLiteral =
          RegExp(r"\{[^}]*'user_mobile'[^}]*\}", multiLine: true);
      expect(bodyLiteral.hasMatch(source), isTrue);
    });

    test('verify_otp body contains duplicate compatibility keys', () {
      // The supplied PHP backend can read either case. PART 16
      // collapsed the body to {referenceNo, otp} and broke /verify_otp.
      // PART 16.1 sends BOTH cases of Otp/otp AND referenceNo/reference_no
      // PLUS user_mobile so the backend picks whichever it expects.
      expect(source, contains("'Otp'"));
      expect(source, contains("'otp'"));
      expect(source, contains("'referenceNo'"));
      expect(source, contains("'reference_no'"));
      expect(source, contains("'user_mobile'"));
    });

    test('reads subscriptionStatus field with trim+toUpperCase', () {
      expect(source, contains('subscriptionStatus'));
      expect(source, contains('toUpperCase'));
    });

    test('REGISTERED grants access', () {
      expect(source, contains("'REGISTERED'"));
      expect(source, contains('initialChargingPending'));
    });

    test('E1351 / already-registered triggers a re-poll of check_subscription',
        () {
      expect(source, contains('E1351'));
      expect(source, contains('alreadyRegistered'));
      expect(source, contains('pollSubscription'));
    });

    test('Firebase custom-token exchange seam exists', () {
      expect(source, contains('exchangeOtpForFirebaseSession'));
      expect(source, contains('signInWithCustomToken'));
      expect(source, contains('customToken'));
    });

    test('subscription-path exchange exists for no-OTP branches', () {
      expect(source, contains('exchangeSubscriptionForFirebaseSession'));
    });

    test('enterSession bundles persist + Firebase sign-in', () {
      expect(source, contains('enterSession'));
      expect(source, contains('persistSession'));
    });

    test('readIsLoggedIn checks legacy telecom_* key for backward compat', () {
      expect(source, contains('_legacyPrefIsLoggedIn'));
      expect(source, contains("'telecom_isLoggedIn'"));
    });
  });

  group('LoginScreen structural checks', () {
    late String screenSource;

    setUpAll(() => screenSource =
        _read('lib/features/auth/presentation/login_screen.dart'));

    test('contains Robi / Cirkle branding copy', () {
      expect(screenSource, contains('Robi'));
      expect(screenSource, contains('Cirkle'));
    });

    test('does NOT contain any "Airtel" copy', () {
      expect(
        screenSource.toLowerCase().contains('airtel'),
        isFalse,
        reason: 'The previous "Airtel" branding must be fully removed.',
      );
    });

    test('does NOT contain any email/password field', () {
      expect(screenSource.contains('TextField'), isFalse);
      expect(screenSource.contains('TextInputType.phone'), isTrue);
    });

    test('does NOT call signInWithEmailAndPassword / EmailAuthProvider', () {
      expect(screenSource.contains('signInWithEmailAndPassword'), isFalse);
      expect(screenSource.contains('EmailAuthProvider'), isFalse);
    });

    test('validates the 016/018 prefix before calling the network', () {
      expect(screenSource, contains('isSupportedPhone'));
    });

    test('PART 16.1: REGISTERED branch exchanges with backend before push', () {
      // The whole point of PART 16.1 is that LoginScreen must NOT
      // bypass the Firebase exchange on the no-OTP branches — the
      // REGISTERED / INITIAL CHARGING PENDING branches must call the
      // backend custom-token endpoint, then enterSession (which signs
      // in to Firebase), then push the shell.
      expect(screenSource,
          contains('exchangeSubscriptionForFirebaseSession'));
      expect(screenSource, contains('enterSession'));
      expect(screenSource, contains('result.rawStatus'));
    });

    test('PART 16.1: LoginScreen accepts a resumeMessage for re-entry', () {
      expect(screenSource, contains('resumeMessage'));
    });

    test('routes REGISTERED / INITIAL CHARGING PENDING to the shell', () {
      expect(screenSource, contains('shouldEnterApp'));
      expect(screenSource, contains('GochanoShell('));
      expect(screenSource, contains("role: 'student'"));
    });
  });

  group('OtpVerifyScreen structural checks', () {
    late String screenSource;

    setUpAll(() => screenSource =
        _read('lib/features/auth/presentation/otp_verify_screen.dart'));

    test('shows a back button in the app bar', () {
      expect(screenSource, contains('GochanoAppBar'));
    });

    test('counts down 240s before allowing resend', () {
      expect(screenSource.contains('Duration(seconds: 240)'), isTrue);
      expect(screenSource.contains('Timer.periodic'), isTrue);
    });

    test('offers a "Wrong number? Change number" link', () {
      expect(screenSource, contains('Wrong number'));
      expect(screenSource, contains('Change number'));
    });

    test('does NOT contain any "Airtel" copy', () {
      expect(screenSource.toLowerCase().contains('airtel'), isFalse);
    });

    test('PART 16.1: exchanges OTP for Firebase session before push', () {
      // After verifyOtp succeeds we MUST call
      // exchangeOtpForFirebaseSession + enterSession BEFORE pushing the
      // shell — otherwise AuthGate sees
      // FirebaseAuth.instance.currentUser == null and refuses entry
      // (or, worse, lets the user through and Firestore denies every
      // read/write).
      expect(screenSource, contains('exchangeOtpForFirebaseSession'));
      expect(screenSource, contains('enterSession'));
      expect(screenSource, contains('GochanoShell('));
      expect(screenSource, contains("role: 'student'"));
    });

    test('no longer relies on persistSession as the entrypoint', () {
      // persistSession is called by enterSession — but if it is
      // called directly here, something has reverted to the PART 16
      // half-authenticated path.
      expect(screenSource.contains('persistSession('), isFalse,
          reason:
              'persistSession must be invoked by enterSession, not '
              'directly from OtpVerifyScreen');
    });
  });

  group('AuthGate structural checks (PART 16.1 dual gate)', () {
    late String gateSource;

    setUpAll(() => gateSource =
        _read('lib/features/auth/presentation/auth_gate.dart'));

    test('subscribes to FirebaseAuth.authStateChanges', () {
      // The PART 16.1 dual gate must watch FirebaseAuth in addition
      // to the local SharedPreferences flag.
      expect(gateSource, contains('authStateChanges'));
      expect(gateSource, contains('FirebaseAuth.instance'));
    });

    test('refuses GochanoShell entry without a FirebaseAuth.currentUser', () {
      // Build() must include both the local flag check AND a
      // currentUser null-check before constructing GochanoShell.
      expect(gateSource, contains('readIsLoggedIn'));
      expect(gateSource, contains('currentUser'));
      expect(gateSource, contains('GochanoShell('));
    });

    test('clears stale session when Firebase did not restore the user', () {
      expect(gateSource, contains('clearSession'));
    });

    test('surfaces a resume message on the LoginScreen', () {
      expect(gateSource, contains('resumeMessage'));
      expect(gateSource, contains('LoginScreen('));
    });

    test('does NOT depend on the legacy email-verification flow', () {
      expect(gateSource.contains('emailVerified'), isFalse);
      expect(gateSource.contains('signInWithEmailAndPassword'), isFalse);
    });

    test('does NOT mention Airtel', () {
      expect(gateSource.toLowerCase().contains('airtel'), isFalse);
    });
  });
}
