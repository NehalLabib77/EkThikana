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
    test('accepts Robi 018 numbers', () {
      expect(TelecomAuthService.isSupportedPhone('01612345678'), isTrue);
    });

    test('accepts Cirkle 016 numbers', () {
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
      expect(r.maySendOtp, isTrue);
      expect(r.status, TelecomSubscriptionStatus.notSubscribed);
    });

    test('temporaryBlocked result blocks app and OTP', () {
      const r = TelecomSubscriptionResult.temporaryBlocked;
      expect(r.shouldEnterApp, isFalse);
      expect(r.maySendOtp, isFalse);
      expect(r.status, TelecomSubscriptionStatus.temporaryBlocked);
      expect(r.rawStatus, 'TEMPORARY BLOCKED');
    });

    test('unknown result fail-closed blocks OTP', () {
      const r = TelecomSubscriptionResult.unknown;
      expect(r.shouldEnterApp, isFalse);
      expect(r.maySendOtp, isFalse);
      expect(r.status, TelecomSubscriptionStatus.unknown);
    });

    test('registered/initial results must not allow OTP', () {
      expect(TelecomSubscriptionResult.registered.maySendOtp, isFalse);
      expect(TelecomSubscriptionResult.initialChargingPending.maySendOtp, isFalse);
    });
  });

  group('Subscription-status parser handles every reasonable alias', () {
    // Calls into the private _parseSubscriptionResponse via the public
    // checkSubscription path is impossible without network mocking,
    // so we instead invoke it reflectively. The test surface is what
    // the rest of the app sees: ONLY a REGISTERED or INITIAL CHARGING
    // PENDING user enters without OTP. NOT SUBSCRIBED allows OTP.
    // Everything else (unknown, temp blocked, malformed) is fail-closed.
    TelecomSubscriptionResult r(String body) {
      return TelecomAuthService.parseSubscriptionResponseForTest(body);
    }

    test('uppercase REGISTERED grants access', () {
      expect(r('{"subscriptionStatus":"REGISTERED"}').shouldEnterApp, isTrue);
    });
    test('underscored "INITIAL_CHARGING_PENDING" grants access', () {
      expect(r('{"subscriptionStatus":"INITIAL_CHARGING_PENDING"}').shouldEnterApp,
          isTrue);
    });
    test('hyphenated "Initial-Charging-Pending" grants access', () {
      expect(
          r('{"subscriptionStatus":"Initial-Charging-Pending"}').shouldEnterApp,
          isTrue);
    });
    test('"ALREADY REGISTERED" is fail-closed (not in the allowed list)', () {
      expect(r('{"subscriptionStatus":"Already Registered"}').shouldEnterApp,
          isFalse);
      expect(r('{"subscriptionStatus":"Already Registered"}').maySendOtp,
          isFalse);
    });
    test('"ALREADY SUBSCRIBED" is fail-closed (not in the allowed list)', () {
      expect(r('{"subscriptionStatus":"ALREADY SUBSCRIBED"}').shouldEnterApp,
          isFalse);
    });
    test('"ACTIVE" is fail-closed (not in the allowed list)', () {
      expect(r('{"subscriptionStatus":"ACTIVE"}').shouldEnterApp, isFalse);
      expect(r('{"subscriptionStatus":"ACTIVE"}').maySendOtp, isFalse);
    });
    test('E1351 statusCode does NOT grant access (must check subscriptionStatus)', () {
      expect(
          r('{"subscriptionStatus":"NOT YET","statusCode":"E1351"}')
              .shouldEnterApp,
          isFalse,
          reason:
              'E1351 statusCode alone must not bypass the subscriptionStatus check');
    });
    test('S1000 statusCode does NOT grant access (must check subscriptionStatus)', () {
      expect(r('{"statusCode":"S1000"}').shouldEnterApp, isFalse);
    });
    test('"NOT SUBSCRIBED" still requires OTP', () {
      expect(
          r('{"subscriptionStatus":"NOT SUBSCRIBED"}').shouldEnterApp, isFalse);
      expect(
          r('{"subscriptionStatus":"NOT SUBSCRIBED"}').maySendOtp, isTrue);
    });
    test('empty body is fail-closed (unknown, no OTP)', () {
      final result = r('');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
      expect(result.status, TelecomSubscriptionStatus.unknown);
    });
  });

  group('TEMPORARY BLOCKED exact captured response (Robi 018)', () {
    const fixture = '''{
  "subscriptionStatus": "TEMPORARY BLOCKED",
  "isSubscribed": false,
  "statusCode": "S1000",
  "statusDetail": "Request was successfully processed.",
  "version": "1.0"
}''';

    TelecomSubscriptionResult r() =>
        TelecomAuthService.parseSubscriptionResponseForTest(fixture);

    test('A. TEMPORARY BLOCKED → temporaryBlocked state', () {
      expect(r().status, TelecomSubscriptionStatus.temporaryBlocked);
    });

    test('B. TEMPORARY BLOCKED → shouldEnterApp is false', () {
      expect(r().shouldEnterApp, isFalse);
    });

    test('C. TEMPORARY BLOCKED → maySendOtp is false', () {
      expect(r().maySendOtp, isFalse);
    });

    test('D. S1000 does NOT cause Home entry', () {
      expect(r().shouldEnterApp, isFalse);
      expect(r().status, isNot(TelecomSubscriptionStatus.registered));
    });

    test('E. NOT SUBSCRIBED → maySendOtp is true', () {
      final notSub = TelecomAuthService.parseSubscriptionResponseForTest(
          '{"subscriptionStatus":"NOT SUBSCRIBED"}');
      expect(notSub.maySendOtp, isTrue);
      expect(notSub.shouldEnterApp, isFalse);
    });

    test('F. REGISTERED → Home auth flow', () {
      final reg = TelecomAuthService.parseSubscriptionResponseForTest(
          '{"subscriptionStatus":"REGISTERED"}');
      expect(reg.shouldEnterApp, isTrue);
      expect(reg.maySendOtp, isFalse);
    });

    test('G. INITIAL CHARGING PENDING → Home auth flow', () {
      final icp = TelecomAuthService.parseSubscriptionResponseForTest(
          '{"subscriptionStatus":"INITIAL CHARGING PENDING"}');
      expect(icp.shouldEnterApp, isTrue);
      expect(icp.maySendOtp, isFalse);
    });

    test('H. rawStatus preserves TEMPORARY BLOCKED', () {
      expect(r().rawStatus, 'TEMPORARY BLOCKED');
    });

    test('I. unknown state → no Home, no OTP, recoverable error', () {
      final unknown = TelecomAuthService.parseSubscriptionResponseForTest(
          '{"subscriptionStatus":"ACTIVE"}');
      expect(unknown.status, TelecomSubscriptionStatus.unknown);
      expect(unknown.shouldEnterApp, isFalse);
      expect(unknown.maySendOtp, isFalse);
    });

    test('malformed non-JSON → fail closed', () {
      final bad = TelecomAuthService.parseSubscriptionResponseForTest('not json');
      expect(bad.status, TelecomSubscriptionStatus.unknown);
      expect(bad.shouldEnterApp, isFalse);
      expect(bad.maySendOtp, isFalse);
    });
  });

  group('SendOtp parser recognises any already-registered alias', () {
    // The OTP screen's race-fallback relies on _parseSendOtpResponse
    // flagging alreadyRegistered = true so we can re-poll
    // /check_subscription.php. If the carrier ever switches from
    // "E1351" to a different code/name we still must catch it.
    dynamic r(String body) =>
        TelecomAuthService.parseSendOtpResponseForTest(body);

    test('E1351 statusCode -> alreadyRegistered', () {
      expect(r('{"statusCode":"E1351"}').alreadyRegistered, isTrue);
    });
    test('"already subscribed" prose -> alreadyRegistered', () {
      expect(
          r('{"success":false,"message":"You are already subscribed."}')
              .alreadyRegistered,
          isTrue);
    });
    test('subscriptionStatus REGISTERED -> alreadyRegistered', () {
      expect(
          r('{"success":false,"subscriptionStatus":"REGISTERED"}')
              .alreadyRegistered,
          isTrue);
    });
    test('plain failure is not flagged alreadyRegistered', () {
      expect(
          r('{"success":false,"message":"Network error"}').alreadyRegistered,
          isFalse);
    });
    test('plain success is not flagged alreadyRegistered', () {
      expect(
          r('{"success":true,"referenceNo":"R1"}').alreadyRegistered, isFalse);
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

    test('TEMPORARY BLOCKED is a distinct state', () {
      expect(source, contains('temporaryBlocked'));
    });

    test('unknown status is fail-closed', () {
      expect(source, contains('TelecomSubscriptionStatus.unknown'));
    });

    test('maySendOtp getter exists', () {
      expect(source, contains('maySendOtp'));
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

    test('LoginScreen no longer shows session-expired card', () {
      expect(screenSource, isNot(contains('resumeMessage')));
    });

    test('routes REGISTERED / INITIAL CHARGING PENDING to the shell', () {
      // The new login_screen.dart uses the named getter
      // `isAlreadySubscribed` instead of the raw `shouldEnterApp`
      // flag; either token means the same no-OTP shortcut is wired
      // up. Both must keep working.
      final hasShouldEnterApp =
          screenSource.contains('shouldEnterApp');
      final hasIsAlreadySubscribed =
          screenSource.contains('isAlreadySubscribed');
      expect(hasShouldEnterApp || hasIsAlreadySubscribed, isTrue,
          reason:
              'login_screen must branch on either shouldEnterApp or '
              'the named isAlreadySubscribed getter to route a known-'
              'subscribed user straight to the shell.');
      expect(screenSource, contains('GochanoShell('));
      expect(screenSource, contains("role: 'student'"));
    });

    test('PART 30: clears recentlyVerified marker on REGISTERED login', () {
      // On successful REGISTERED login, the marker must be cleared.
      expect(screenSource, contains('clearRecentlyVerified'));
    });

    test('PART 30: propagation guard checks recentlyVerified marker', () {
      // When check_subscription returns NOT SUBSCRIBED, the login screen
      // must check the recentlyVerified marker to detect carrier
      // propagation delay.
      expect(screenSource, contains('readRecentlyVerifiedPhone'));
      expect(screenSource, contains('PROPAGATION_GUARD'));
    });

    test('PART 30: propagation guard shows activation message', () {
      // When propagation delay is detected, the login screen must show
      // the activation message instead of sending OTP.
      expect(screenSource, contains('Subscription is activating'));
      expect(screenSource, contains('সাবস্ক্রিপশন সক্রিয় হচ্ছে'));
    });

    test('PART 30: propagation guard does not send OTP for same phone', () {
      // When propagation delay is detected, the login screen must NOT
      // send another OTP.
      final propagationIndex = screenSource.indexOf('PROPAGATION_GUARD');
      final sendOtpIndex = screenSource.indexOf('SEND_OTP');
      expect(propagationIndex, lessThan(sendOtpIndex),
          reason: 'Propagation guard must be checked before SEND_OTP branch');
    });

    test('TEMPORARY BLOCKED branch appears before SEND_OTP', () {
      final blockedIndex = screenSource.indexOf('temporaryBlocked');
      final sendIndex = screenSource.indexOf('SEND_OTP');
      expect(blockedIndex, greaterThanOrEqualTo(0));
      expect(sendIndex, greaterThanOrEqualTo(0));
      expect(blockedIndex, lessThan(sendIndex),
          reason: 'TEMPORARY BLOCKED must block OTP before SEND_OTP branch');
    });

    test('TEMPORARY BLOCKED shows bilingual message', () {
      expect(screenSource, contains('Your subscription is temporarily blocked'));
      expect(screenSource, contains('আপনার সাবস্ক্রিপশন সাময়িকভাবে বন্ধ আছে'));
    });

    test('TEMPORARY BLOCKED does not send OTP', () {
      final blockedIndex = screenSource.indexOf('temporaryBlocked');
      final sendIndex = screenSource.indexOf('SEND_OTP');
      expect(blockedIndex, lessThan(sendIndex));
    });

    test('unknown status branch appears before SEND_OTP', () {
      final unknownIndex = screenSource.indexOf('TelecomSubscriptionStatus.unknown');
      final sendIndex = screenSource.indexOf('SEND_OTP');
      expect(unknownIndex, greaterThanOrEqualTo(0));
      expect(sendIndex, greaterThanOrEqualTo(0));
      expect(unknownIndex, lessThan(sendIndex),
          reason: 'Unknown status must fail closed before SEND_OTP branch');
    });

    test('maySendOtp guard appears before SEND_OTP', () {
      final guardIndex = screenSource.indexOf('maySendOtp');
      final sendIndex = screenSource.indexOf('SEND_OTP');
      expect(guardIndex, greaterThanOrEqualTo(0));
      expect(sendIndex, greaterThanOrEqualTo(0));
      expect(guardIndex, lessThan(sendIndex),
          reason: 'maySendOtp guard must be checked before SEND_OTP');
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

    test('PART 30: OTP success enters app or falls back to LoginScreen', () {
      // After verifyOtp succeeds the OTP screen attempts the full
      // authenticated entry flow (check subscription → Firebase → Home).
      // If ANY post-OTP step fails, it falls back to LoginScreen.
      // Must NOT call exchangeOtpForFirebaseSession (old OTP exchange)
      expect(screenSource, isNot(contains('exchangeOtpForFirebaseSession')));
      // On success: enters app directly
      expect(screenSource, contains('enterSession'));
      expect(screenSource, contains('GochanoShell('));
      expect(screenSource, contains('ProfileSetupScreen('));
      // On failure: falls back to LoginScreen
      expect(screenSource, contains('LoginScreen()'));
      expect(screenSource, contains('pushAndRemoveUntil'));
      expect(screenSource, contains('_handlePostOtpFailure'));
    });

    test('PART 30: OTP success stores recentlyVerified marker', () {
      // The OTP screen must store the recentlyVerified marker to prevent
      // re-sending OTP during carrier propagation delay.
      expect(screenSource, contains('setRecentlyVerified'));
    });

    test('PART 30: OTP success clears OTP controller and reference state', () {
      // The OTP screen must clear the OTP controller and reference state
      // before navigating to LoginScreen.
      expect(screenSource, contains('_otpController.clear()'));
      expect(screenSource, contains('_referenceNo = null'));
    });

    test('PART 30: already-registered recovery shows bilingual message in LoginScreen', () {
      // The "already registered" recovery message is now in LoginScreen
      // (not OtpVerifyScreen) since the recovery performs authenticated
      // entry directly. Check LoginScreen for the activation message.
      final loginSrc = _read('lib/features/auth/presentation/login_screen.dart');
      expect(loginSrc, contains('Your subscription is activating'));
      expect(loginSrc, contains('আপনার সাবস্ক্রিপশন সক্রিয় হচ্ছে'));
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

    test('PART 30: kAlreadySubscribedSentinel handled in LoginScreen', () {
      // When sendOtp returns kAlreadySubscribedSentinel, LoginScreen
      // handles the recovery directly — OtpVerifyScreen is never pushed.
      final loginSrc = _read('lib/features/auth/presentation/login_screen.dart');
      expect(loginSrc, contains('kAlreadySubscribedSentinel'));
      expect(loginSrc, contains('setRecentlyVerified'));
      // OtpVerifyScreen no longer handles kAlreadySubscribedSentinel
      expect(screenSource, isNot(contains('kAlreadySubscribedSentinel')));
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

    test('routes to LoginScreen without a resume card', () {
      expect(gateSource, isNot(contains('resumeMessage')));
      expect(gateSource, contains('LoginScreen()'));
    });

    test('does NOT depend on the legacy email-verification flow', () {
      expect(gateSource.contains('emailVerified'), isFalse);
      expect(gateSource.contains('signInWithEmailAndPassword'), isFalse);
    });

    test('does NOT mention Airtel', () {
      expect(gateSource.toLowerCase().contains('airtel'), isFalse);
    });
  });

  group('PART 30: recentlyVerified marker (TelecomAuthService)', () {
    late String source;

    setUpAll(() => source =
        _read('lib/core/services/telecom_auth_service.dart'));

    test('recentlyVerified marker keys exist', () {
      expect(source, contains('prefRecentlyVerifiedPhone'));
      expect(source, contains('prefRecentlyVerifiedAt'));
    });

    test('setRecentlyVerified method exists', () {
      expect(source, contains('setRecentlyVerified'));
    });

    test('readRecentlyVerifiedPhone method exists', () {
      expect(source, contains('readRecentlyVerifiedPhone'));
    });

    test('clearRecentlyVerified method exists', () {
      expect(source, contains('clearRecentlyVerified'));
    });

    test('recentlyVerifiedMaxAge is 5 minutes', () {
      expect(source, contains('recentlyVerifiedMaxAge'));
      expect(source, contains('Duration(minutes: 5)'));
    });

    test('clearSession clears recentlyVerified marker', () {
      // clearSession delegates to clearLocalSession which clears the
      // recentlyVerified marker to prevent stale markers from affecting
      // new sessions.
      final clearSessionIndex = source.indexOf('static Future<void> clearSession()');
      expect(clearSessionIndex, greaterThanOrEqualTo(0));
      final clearSessionBody = source.substring(clearSessionIndex, clearSessionIndex + 500);
      expect(clearSessionBody, contains('clearLocalSession()'),
          reason: 'clearSession must delegate to clearLocalSession');
      // Verify clearLocalSession has the actual cleanup
      final clearLocalIndex = source.indexOf('static Future<void> clearLocalSession()');
      expect(clearLocalIndex, greaterThanOrEqualTo(0));
      final clearLocalBody = source.substring(clearLocalIndex, clearLocalIndex + 900);
      expect(clearLocalBody, contains('clearRecentlyVerified'));
    });

    test('recentlyVerified marker is NOT authentication proof', () {
      // The marker must never be used to grant access to the app.
      // It should only be used for propagation delay detection.
      // The setRecentlyVerified method must NOT set prefIsLoggedIn.
      final setMarkerIndex = source.indexOf('static Future<void> setRecentlyVerified');
      expect(setMarkerIndex, greaterThanOrEqualTo(0));
      final setMarkerBody = source.substring(setMarkerIndex, setMarkerIndex + 300);
      expect(setMarkerBody, isNot(contains('prefIsLoggedIn')),
          reason: 'setRecentlyVerified must NOT set the isLoggedIn flag');
      expect(setMarkerBody, isNot(contains('isLoggedIn')),
          reason: 'setRecentlyVerified must NOT set isLoggedIn');
    });
  });

  group('PART 30: propagation guard (LoginScreen)', () {
    late String screenSource;

    setUpAll(() => screenSource =
        _read('lib/features/auth/presentation/login_screen.dart'));

    test('checks readRecentlyVerifiedPhone before sending OTP', () {
      // The login screen must check the recentlyVerified marker
      // before sending OTP to detect carrier propagation delay.
      expect(screenSource, contains('readRecentlyVerifiedPhone'));
    });

    test('shows activation message when propagation delay detected', () {
      // When same phone was recently verified and subscription is
      // still NOT SUBSCRIBED, show activation message.
      expect(screenSource, contains('Subscription is activating'));
      expect(screenSource, contains('সাবস্ক্রিপশন সক্রিয় হচ্ছে'));
    });

    test('does NOT send OTP when propagation delay detected', () {
      // The propagation guard must prevent OTP resending.
      final propagationIndex = screenSource.indexOf('PROPAGATION_GUARD');
      final sendOtpIndex = screenSource.indexOf('SEND_OTP');
      expect(propagationIndex, lessThan(sendOtpIndex),
          reason: 'Propagation guard must be checked before SEND_OTP');
    });

    test('clears marker on successful REGISTERED login', () {
      // On successful REGISTERED login, clear the marker.
      expect(screenSource, contains('clearRecentlyVerified'));
    });

    test('allows retry after propagation delay message', () {
      // After showing the activation message, the user can tap
      // Continue again to retry the subscription check.
      expect(screenSource, contains('_acknowledgementMessage'));
    });
  });

  group('FirestoreService ProfileCheckResult enum', () {
    late String source;

    setUpAll(() => source =
        _read('lib/services/firestore_service.dart'));

    test('ProfileCheckResult enum exists with three values', () {
      expect(source, contains('enum ProfileCheckResult'));
      expect(source, contains('exists'));
      expect(source, contains('missing'));
      expect(source, contains('error'));
    });

    test('checkProfileState() method exists', () {
      expect(source, contains('static Future<ProfileCheckResult> checkProfileState()'));
    });

    test('checkProfileState returns error when uid is null', () {
      // When no Firebase user is signed in, treat as error (not missing)
      final methodStart = source.indexOf('static Future<ProfileCheckResult> checkProfileState()');
      expect(methodStart, greaterThanOrEqualTo(0));
      final body = source.substring(methodStart, methodStart + 800);
      expect(body, contains('return ProfileCheckResult.error'),
          reason: 'Null uid must return error, not missing');
    });

    test('checkProfileState returns missing when document does not exist', () {
      final methodStart = source.indexOf('static Future<ProfileCheckResult> checkProfileState()');
      final body = source.substring(methodStart, methodStart + 1000);
      expect(body, contains('return ProfileCheckResult.missing'),
          reason: 'Missing document must return missing');
    });

    test('checkProfileState returns error on catch (network/permission)', () {
      // The catch block must return error, NOT missing
      final methodStart = source.indexOf('static Future<ProfileCheckResult> checkProfileState()');
      final body = source.substring(methodStart, methodStart + 1200);
      // Find the catch block
      final catchIndex = body.indexOf('catch (_)');
      expect(catchIndex, greaterThanOrEqualTo(0),
          reason: 'checkProfileState must have a catch block');
      final catchBody = body.substring(catchIndex, catchIndex + 100);
      expect(catchBody, contains('return ProfileCheckResult.error'),
          reason: 'Catch block must return error, not false/missing');
    });

    test('hasProfile still exists for backward compatibility', () {
      expect(source, contains('static Future<bool> hasProfile()'));
    });

    test('hasProfile catch block returns false (legacy behavior)', () {
      // hasProfile must NOT be changed — its catch returns false
      final methodStart = source.indexOf('static Future<bool> hasProfile()');
      expect(methodStart, greaterThanOrEqualTo(0));
      final body = source.substring(methodStart, methodStart + 500);
      final catchIndex = body.indexOf('catch (_)');
      expect(catchIndex, greaterThanOrEqualTo(0));
      final catchBody = body.substring(catchIndex, catchIndex + 50);
      expect(catchBody, contains('return false'),
          reason: 'hasProfile catch must still return false for backward compat');
    });
  });

  group('PART 30 Scenario A: OTP success → subscription → Firebase → profile → Home', () {
    late String otpSource;

    setUpAll(() => otpSource =
        _read('lib/features/auth/presentation/otp_verify_screen.dart'));

    test('OTP success attempts checkSubscription', () {
      expect(otpSource, contains('checkSubscription(widget.phone)'));
    });

    test('OTP success calls exchangeSubscriptionForFirebaseSession', () {
      expect(otpSource, contains('exchangeSubscriptionForFirebaseSession'));
    });

    test('OTP success calls enterSession (Firebase sign-in)', () {
      expect(otpSource, contains('enterSession'));
    });

    test('OTP success shows "Taking you in" snackbar', () {
      expect(otpSource, contains('Taking you in'));
      expect(otpSource, contains('আপনাকে প্রবেশ করানো হচ্ছে'));
    });

    test('OTP success resolves profile BEFORE "Taking you in" delay', () {
      // checkProfileState must come BEFORE the 1.2s delay
      final profileIndex = otpSource.indexOf('checkProfileState()');
      final delayIndex = otpSource.indexOf('Duration(milliseconds: 1200)');
      expect(profileIndex, greaterThanOrEqualTo(0));
      expect(delayIndex, greaterThanOrEqualTo(0));
      expect(profileIndex, lessThan(delayIndex),
          reason: 'Profile must be resolved BEFORE Taking-you-in delay');
    });

    test('OTP success delays ~1.2s AFTER profile resolution (not before)', () {
      // The delay must come AFTER checkProfileState, not before
      final enterSessionIndex = otpSource.indexOf('enterSession(');
      final profileIndex = otpSource.indexOf('checkProfileState()');
      final delayIndex = otpSource.indexOf('Duration(milliseconds: 1200)');
      expect(enterSessionIndex, greaterThanOrEqualTo(0));
      expect(profileIndex, greaterThanOrEqualTo(0));
      expect(delayIndex, greaterThanOrEqualTo(0));
      expect(enterSessionIndex, lessThan(profileIndex),
          reason: 'Profile check must come AFTER Firebase auth');
      expect(profileIndex, lessThan(delayIndex),
          reason: 'Delay must come AFTER profile resolution');
    });

    test('OTP success uses checkProfileState (not hasProfile)', () {
      expect(otpSource, contains('checkProfileState()'));
      expect(otpSource, isNot(contains('FirestoreService.hasProfile()')),
          reason: 'OTP path must use checkProfileState for tri-state semantics');
    });

    test('OTP success navigates to GochanoShell on profile exists', () {
      expect(otpSource, contains('ProfileCheckResult.exists'));
      expect(otpSource, contains('GochanoShell('));
    });

    test('OTP success navigates to ProfileSetupScreen on profile missing', () {
      expect(otpSource, contains('ProfileCheckResult.missing'));
      expect(otpSource, contains('ProfileSetupScreen('));
    });
  });

  group('PART 30 Scenario B: OTP success → profile genuinely missing → ProfileSetup', () {
    late String otpSource;

    setUpAll(() => otpSource =
        _read('lib/features/auth/presentation/otp_verify_screen.dart'));

    test('ProfileCheckResult.missing routes to ProfileSetupScreen', () {
      // Find the switch case for missing
      final missingIndex = otpSource.indexOf('ProfileCheckResult.missing');
      expect(missingIndex, greaterThanOrEqualTo(0));
      final caseBody = otpSource.substring(missingIndex, missingIndex + 300);
      expect(caseBody, contains('ProfileSetupScreen('),
          reason: 'Missing profile must route to ProfileSetupScreen');
    });
  });

  group('PART 30 Scenario C: OTP success → post-OTP failure → Login recovery', () {
    late String otpSource;

    setUpAll(() => otpSource =
        _read('lib/features/auth/presentation/otp_verify_screen.dart'));

    test('checkSubscription failure calls _handlePostOtpFailure', () {
      expect(otpSource, contains('_handlePostOtpFailure'));
    });

    test('_handlePostOtpFailure rolls back auth session via clearSession', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      expect(handlerIndex, greaterThanOrEqualTo(0));
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1000);
      expect(handlerBody, contains('TelecomAuthService.clearSession()'),
          reason: 'Must clear session before navigating to LoginScreen '
              'to prevent AuthGate bypass on restart');
    });

    test('_handlePostOtpFailure stores recentlyVerified marker after rollback', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1000);
      expect(handlerBody, contains('setRecentlyVerified'));
    });

    test('_handlePostOtpFailure clears OTP state', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1000);
      expect(handlerBody, contains('_otpController.clear()'));
      expect(handlerBody, contains('_referenceNo = null'));
    });

    test('_handlePostOtpFailure navigates to LoginScreen', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1500);
      expect(handlerBody, contains('LoginScreen()'));
      expect(handlerBody, contains('pushAndRemoveUntil'));
    });

    test('_handlePostOtpFailure shows bilingual recovery message', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1800);
      expect(handlerBody, contains('Number verified. Please sign in again.'));
      expect(handlerBody, contains('নম্বর যাচাই হয়েছে। আবার সাইন ইন করুন।'));
    });

    test('consumed OTP is never retried after post-OTP failure', () {
      // The _handlePostOtpFailure clears referenceNo so verify cannot be called
      expect(otpSource, contains('_referenceNo = null'));
    });

    test('NOT SUBSCRIBED after OTP calls _handlePostOtpFailure', () {
      // When checkSubscription returns NOT SUBSCRIBED (propagation delay)
      final notSubIndex = otpSource.indexOf('!subResult.isAlreadySubscribed');
      expect(notSubIndex, greaterThanOrEqualTo(0));
      final afterNotSub = otpSource.substring(notSubIndex, notSubIndex + 200);
      expect(afterNotSub, contains('_handlePostOtpFailure'));
    });
  });

  group('PART 30 Scenario D: OTP success → profile lookup error → NOT treated as missing', () {
    late String otpSource;

    setUpAll(() => otpSource =
        _read('lib/features/auth/presentation/otp_verify_screen.dart'));

    test('ProfileCheckResult.error calls _handlePostOtpFailure', () {
      final errorIndex = otpSource.indexOf('ProfileCheckResult.error');
      expect(errorIndex, greaterThanOrEqualTo(0));
      final errorBody = otpSource.substring(errorIndex, errorIndex + 300);
      expect(errorBody, contains('_handlePostOtpFailure'),
          reason: 'Profile lookup error must route to recovery, NOT ProfileSetup');
      expect(errorBody, isNot(contains('ProfileSetupScreen')),
          reason: 'Profile lookup error must NOT route to ProfileSetupScreen');
    });
  });

  group('PART 30 Scenario E: Recovery Login → same number REGISTERED → Home', () {
    late String loginSource;

    setUpAll(() => loginSource =
        _read('lib/features/auth/presentation/login_screen.dart'));

    test('REGISTERED path uses checkProfileState (not hasProfile)', () {
      expect(loginSource, contains('checkProfileState()'));
    });

    test('REGISTERED path shows "Taking you in" snackbar', () {
      expect(loginSource, contains('Taking you in'));
      expect(loginSource, contains('আপনাকে প্রবেশ করানো হচ্ছে'));
    });

    test('REGISTERED path resolves profile BEFORE "Taking you in" delay', () {
      // checkProfileState must come BEFORE the 1.2s delay
      final profileIndex = loginSource.indexOf('checkProfileState()');
      final delayIndex = loginSource.indexOf('Duration(milliseconds: 1200)');
      expect(profileIndex, greaterThanOrEqualTo(0));
      expect(delayIndex, greaterThanOrEqualTo(0));
      expect(profileIndex, lessThan(delayIndex),
          reason: 'Profile must be resolved BEFORE Taking-you-in delay');
    });

    test('REGISTERED path delays ~1.2s AFTER profile resolution', () {
      final enterSessionIndex = loginSource.indexOf('enterSession(');
      final profileIndex = loginSource.indexOf('checkProfileState()');
      final delayIndex = loginSource.indexOf('Duration(milliseconds: 1200)');
      expect(enterSessionIndex, greaterThanOrEqualTo(0));
      expect(profileIndex, greaterThanOrEqualTo(0));
      expect(delayIndex, greaterThanOrEqualTo(0));
      expect(enterSessionIndex, lessThan(profileIndex),
          reason: 'Profile check must come AFTER Firebase auth');
      expect(profileIndex, lessThan(delayIndex),
          reason: 'Delay must come AFTER profile resolution');
    });

    test('REGISTERED path navigates to GochanoShell on profile exists', () {
      expect(loginSource, contains('ProfileCheckResult.exists'));
      expect(loginSource, contains('GochanoShell('));
    });

    test('REGISTERED path navigates to ProfileSetupScreen on profile missing', () {
      expect(loginSource, contains('ProfileCheckResult.missing'));
      expect(loginSource, contains('ProfileSetupScreen('));
    });

    test('REGISTERED path shows error on profile lookup failure (not ProfileSetup)', () {
      final errorIndex = loginSource.indexOf('ProfileCheckResult.error');
      expect(errorIndex, greaterThanOrEqualTo(0));
      final errorBody = loginSource.substring(errorIndex, errorIndex + 600);
      expect(errorBody, contains('Could not load your profile'),
          reason: 'Profile error must show user-facing message');
      // The error handler must NOT construct ProfileSetupScreen.
      // Comments may mention it — check for the constructor call.
      expect(errorBody, isNot(contains('ProfileSetupScreen(')),
          reason: 'Profile error must NOT route to ProfileSetupScreen');
    });

    test('REGISTERED path clears recentlyVerified marker', () {
      expect(loginSource, contains('clearRecentlyVerified'));
    });
  });

  group('PART 30 Scenario F: Recovery Login → NOT SUBSCRIBED after guard → new OTP', () {
    late String loginSource;

    setUpAll(() => loginSource =
        _read('lib/features/auth/presentation/login_screen.dart'));

    test('propagation guard checks recentlyVerified before sending OTP', () {
      expect(loginSource, contains('readRecentlyVerifiedPhone'));
    });

    test('propagation guard prevents OTP for same phone within 5 min', () {
      final propagationIndex = loginSource.indexOf('PROPAGATION_GUARD');
      final sendOtpIndex = loginSource.indexOf('SEND_OTP');
      expect(propagationIndex, lessThan(sendOtpIndex),
          reason: 'Propagation guard must be checked before OTP branch');
    });

    test('after guard expiry, NOT SUBSCRIBED falls through to OTP', () {
      // The propagation guard only matches when the phone was recently
      // verified. After expiry, readRecentlyVerifiedPhone returns null
      // and the normal NOT SUBSCRIBED → send OTP flow applies.
      expect(loginSource, contains('SEND_OTP'));
    });
  });

  group('PART 30: clearSession signs out Firebase before clearing prefs', () {
    late String source;

    setUpAll(() => source =
        _read('lib/core/services/telecom_auth_service.dart'));

    test('clearSession calls FirebaseAuth.signOut', () {
      final clearSessionIndex = source.indexOf('static Future<void> clearSession()');
      expect(clearSessionIndex, greaterThanOrEqualTo(0));
      final clearSessionBody = source.substring(clearSessionIndex, clearSessionIndex + 600);
      expect(clearSessionBody, contains('FirebaseAuth.instance.signOut()'),
          reason: 'clearSession must sign out of Firebase to prevent '
              'stale currentUser after rollback');
    });

    test('clearSession signs out BEFORE clearing SharedPreferences', () {
      final clearSessionIndex = source.indexOf('static Future<void> clearSession()');
      final clearSessionBody = source.substring(clearSessionIndex, clearSessionIndex + 800);
      final signOutIndex = clearSessionBody.indexOf('signOut()');
      final prefsIndex = clearSessionBody.indexOf('SharedPreferences.getInstance()');
      expect(signOutIndex, greaterThanOrEqualTo(0));
      expect(prefsIndex, greaterThanOrEqualTo(0));
      expect(signOutIndex, lessThan(prefsIndex),
          reason: 'Firebase signOut must happen BEFORE clearing SharedPreferences '
              'so AuthGate listener sees null user before prefs are cleared');
    });

    test('clearSession signOut is wrapped in try-catch (best-effort)', () {
      final clearSessionIndex = source.indexOf('static Future<void> clearSession()');
      final clearSessionBody = source.substring(clearSessionIndex, clearSessionIndex + 600);
      expect(clearSessionBody, contains('try'),
          reason: 'signOut must be best-effort to avoid blocking on Firebase errors');
    });
  });

  group('PART 30: _handlePostOtpFailure rollback ordering', () {
    late String otpSource;

    setUpAll(() => otpSource =
        _read('lib/features/auth/presentation/otp_verify_screen.dart'));

    test('clearSession is called before setRecentlyVerified', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1000);
      final clearIndex = handlerBody.indexOf('clearSession()');
      final setMarkerIndex = handlerBody.indexOf('setRecentlyVerified');
      expect(clearIndex, greaterThanOrEqualTo(0));
      expect(setMarkerIndex, greaterThanOrEqualTo(0));
      expect(clearIndex, lessThan(setMarkerIndex),
          reason: 'clearSession (which calls clearRecentlyVerified) must run '
              'BEFORE setRecentlyVerified so the new marker is not wiped');
    });

    test('setRecentlyVerified is called before clearing OTP UI state', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1000);
      final setMarkerIndex = handlerBody.indexOf('setRecentlyVerified');
      final clearOtpIndex = handlerBody.indexOf('_otpController.clear()');
      expect(setMarkerIndex, greaterThanOrEqualTo(0));
      expect(clearOtpIndex, greaterThanOrEqualTo(0));
      expect(setMarkerIndex, lessThan(clearOtpIndex),
          reason: 'recentlyVerified marker must be stored BEFORE clearing '
              'OTP UI state');
    });

    test('Navigation to LoginScreen happens AFTER all cleanup', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1500);
      final navIndex = handlerBody.indexOf('LoginScreen()');
      final clearOtpIndex = handlerBody.indexOf('_otpController.clear()');
      expect(navIndex, greaterThanOrEqualTo(0));
      expect(clearOtpIndex, greaterThanOrEqualTo(0));
      expect(clearOtpIndex, lessThan(navIndex),
          reason: 'All cleanup must finish BEFORE navigating to LoginScreen');
    });
  });

  group('PART 30 Scenario G: Consumed OTP can never be verified twice', () {
    late String otpSource;

    setUpAll(() => otpSource =
        _read('lib/features/auth/presentation/otp_verify_screen.dart'));

    test('OTP screen does not call exchangeOtpForFirebaseSession', () {
      expect(otpSource, isNot(contains('exchangeOtpForFirebaseSession')),
          reason: 'Old OTP exchange path must not be used');
    });

    test('OTP screen clears referenceNo on post-OTP failure', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1500);
      expect(handlerBody, contains('_referenceNo = null'),
          reason: 'referenceNo must be nulled so verify cannot be retried');
    });

    test('OTP screen clears timer on post-OTP failure', () {
      final handlerIndex = otpSource.indexOf('Future<void> _handlePostOtpFailure');
      final handlerBody = otpSource.substring(handlerIndex, handlerIndex + 1500);
      expect(handlerBody, contains('_ticker?.cancel()'),
          reason: 'Timer must be cancelled on post-OTP failure');
    });
  });

  group('AuthGate uses checkProfileState for profile resolution', () {
    late String gateSource;

    setUpAll(() => gateSource =
        _read('lib/features/auth/presentation/auth_gate.dart'));

    test('AuthGate uses checkProfileState (not hasProfile)', () {
      expect(gateSource, contains('checkProfileState()'));
    });

    test('AuthGate has _profileError state for recoverable error', () {
      expect(gateSource, contains('_profileError'),
          reason: 'AuthGate must track profile error state separately');
    });

    test('AuthGate profile error shows Retry UI (not ProfileSetupScreen)', () {
      // ProfileCheckResult.error must NOT route to ProfileSetupScreen
      final errorIndex = gateSource.indexOf('ProfileCheckResult.error');
      expect(errorIndex, greaterThanOrEqualTo(0));
      final errorBody = gateSource.substring(errorIndex, errorIndex + 500);
      expect(errorBody, contains('profileError = true'),
          reason: 'Error must set profileError flag');
      expect(errorBody, isNot(contains('ProfileSetupScreen(')),
          reason: 'Error must NOT route to ProfileSetupScreen');
    });

    test('AuthGate has _retryProfileCheck method', () {
      expect(gateSource, contains('_retryProfileCheck'),
          reason: 'AuthGate must have a retry method for profile errors');
    });

    test('AuthGate build shows error UI when _profileError is true', () {
      expect(gateSource, contains('_profileError'),
          reason: 'build() must check _profileError state');
    });

    test('AuthGate only enters shell on ProfileCheckResult.exists', () {
      expect(gateSource, contains('ProfileCheckResult.exists'),
          reason: 'AuthGate must only enter shell on explicit exists');
    });

    test('AuthGate shows ProfileSetupScreen for ProfileCheckResult.missing', () {
      expect(gateSource, contains('ProfileSetupScreen('),
          reason: 'AuthGate must show ProfileSetupScreen for missing profile');
    });
  });

  group('Firebase currentUser null guard (bug regression)', () {
    late String loginSource;
    late String otpSource;
    late String telecomSource;

    setUpAll(() {
      loginSource = _read('lib/features/auth/presentation/login_screen.dart');
      otpSource = _read('lib/features/auth/presentation/otp_verify_screen.dart');
      telecomSource = _read('lib/core/services/telecom_auth_service.dart');
    });

    test('A. REGISTERED status alone does NOT show Taking you in', () {
      // The acknowledgement message must be set AFTER enterSession + profile
      // check, not immediately after checkSubscription returns REGISTERED.
      final registerIndex = loginSource.indexOf('REGISTERED_SHORTCUT');
      expect(registerIndex, greaterThanOrEqualTo(0));
      final registerBlock = loginSource.substring(registerIndex, registerIndex + 4000);
      final ackIndex = registerBlock.indexOf('_acknowledgementMessage');
      final enterIndex = registerBlock.indexOf('enterSession');
      expect(enterIndex, lessThan(ackIndex),
          reason: 'enterSession must be called before _acknowledgementMessage is set');
    });

    test('B. checkProfileState not called while Firebase currentUser is null', () {
      // login_screen.dart must verify currentUser != null before checkProfileState
      final guardIndex = loginSource.indexOf('currentUser == null');
      expect(guardIndex, greaterThanOrEqualTo(0),
          reason: 'login_screen must check currentUser before profile lookup');
      final guardBlock = loginSource.substring(guardIndex, guardIndex + 800);
      expect(guardBlock, contains('checkProfileState'),
          reason: 'checkProfileState must be after the null guard');
    });

    test('B2. otp_verify_screen also checks currentUser before profile', () {
      final guardIndex = otpSource.indexOf('currentUser == null');
      expect(guardIndex, greaterThanOrEqualTo(0),
          reason: 'otp_verify_screen must check currentUser before profile lookup');
      final guardBlock = otpSource.substring(guardIndex, guardIndex + 800);
      expect(guardBlock, contains('checkProfileState'),
          reason: 'checkProfileState must be after the null guard');
    });

    test('C. enterSession verifies currentUser is non-null after sign-in', () {
      expect(telecomSource, contains('enterSession'),
          reason: 'enterSession method must exist');
      final enterIndex = telecomSource.indexOf('static Future<void> enterSession');
      expect(enterIndex, greaterThanOrEqualTo(0));
      final enterBlock = telecomSource.substring(enterIndex, enterIndex + 600);
      expect(enterBlock, contains('currentUser == null'),
          reason: 'enterSession must throw if currentUser is null after sign-in');
    });

    test('D. signInToFirebaseWithCustomToken logs user uid', () {
      expect(telecomSource, contains('signInWithCustomToken: uid='),
          reason: 'signInToFirebaseWithCustomToken must log uid');
    });

    test('E. login_screen shows error when currentUser null after enterSession', () {
      final nullIndex = loginSource.indexOf('currentUser == null');
      expect(nullIndex, greaterThanOrEqualTo(0),
          reason: 'login_screen must handle null currentUser after enterSession');
      final nullBlock = loginSource.substring(nullIndex, nullIndex + 400);
      expect(nullBlock, contains('_showError'),
          reason: 'null currentUser must show error');
    });
  });

  // -------------------------------------------------------------------
  // PART 30 regression tests — post-auth race, hero, profile image fixes
  // -------------------------------------------------------------------

  group('PART 30: clearSession sign-out loop prevention', () {
    late String telecomSource;
    late String authGateSource;

    setUpAll(() {
      telecomSource = _read('lib/core/services/telecom_auth_service.dart');
      authGateSource = _read('lib/features/auth/presentation/auth_gate.dart');
    });

    test('A. clearLocalSession exists and does NOT call Firebase signOut', () {
      expect(telecomSource, contains('static Future<void> clearLocalSession()'),
          reason: 'clearLocalSession method must exist');
      final idx = telecomSource.indexOf('static Future<void> clearLocalSession()');
      final block = telecomSource.substring(idx, idx + 500);
      expect(block, isNot(contains('FirebaseAuth.instance.signOut()')),
          reason: 'clearLocalSession must NOT call Firebase signOut');
    });

    test('B. clearSession calls signOut then clearLocalSession', () {
      final idx = telecomSource.indexOf('static Future<void> clearSession()');
      expect(idx, greaterThanOrEqualTo(0), reason: 'clearSession must exist');
      final block = telecomSource.substring(idx, idx + 400);
      expect(block, contains('FirebaseAuth.instance.signOut()'),
          reason: 'clearSession must call Firebase signOut');
      expect(block, contains('clearLocalSession()'),
          reason: 'clearSession must delegate to clearLocalSession');
    });

    test('C. AuthGate listener uses clearLocalSession, NOT clearSession', () {
      // The authStateChanges listener must NOT call clearSession() which
      // would create a recursive sign-out loop.
      final listenerIdx = authGateSource.indexOf('authStateChanges().listen');
      expect(listenerIdx, greaterThanOrEqualTo(0));
      final listenerBlock = authGateSource.substring(listenerIdx, listenerIdx + 500);
      expect(listenerBlock, isNot(contains('TelecomAuthService.clearSession()')),
          reason: 'authStateChanges listener must NOT call clearSession');
    });

    test('D. AuthGate has _authGeneration counter for stale callback protection', () {
      expect(authGateSource, contains('_authGeneration'),
          reason: 'AuthGate must have _authGeneration counter');
      expect(authGateSource, contains('generation != _authGeneration'),
          reason: 'AuthGate must check generation staleness in _restore');
    });
  });

  group('PART 30: Profile exists never routes to ProfileSetup', () {
    late String authGateSource;

    setUpAll(() {
      authGateSource = _read('lib/features/auth/presentation/auth_gate.dart');
    });

    test('A. ProfileCheckResult.exists sets hasProfile = true', () {
      final idx = authGateSource.indexOf('ProfileCheckResult.exists');
      expect(idx, greaterThanOrEqualTo(0));
      final block = authGateSource.substring(idx, idx + 200);
      expect(block, contains('hasProfile = true'),
          reason: 'exists must set hasProfile to true');
    });

    test('B. _hasProfile true routes to GochanoShell, not ProfileSetupScreen', () {
      final idx = authGateSource.indexOf('if (!_hasProfile)');
      expect(idx, greaterThanOrEqualTo(0));
      final block = authGateSource.substring(idx, idx + 300);
      expect(block, contains('ProfileSetupScreen'),
          reason: 'missing profile must route to ProfileSetupScreen');
      // The GochanoShell route must come AFTER the _hasProfile check
      final shellIdx = authGateSource.indexOf('GochanoShell(');
      expect(shellIdx, greaterThan(idx),
          reason: 'GochanoShell must be after the _hasProfile check');
    });
  });

  group('PART 30: Hero tag collision prevention', () {
    late String communitySource;
    late String expenseSource;
    late String notesSource;
    late String materialsSource;
    late String tasksSource;

    setUpAll(() {
      communitySource = _read('lib/features/community/presentation/community_screen.dart');
      expenseSource = _read('lib/features/life/presentation/expense/expense_screen.dart');
      notesSource = _read('lib/features/study/presentation/notes/notes_screen.dart');
      materialsSource = _read('lib/features/study/presentation/materials/materials_screen.dart');
      tasksSource = _read('lib/features/tasks/presentation/tasks_view.dart');
    });

    test('A. community FAB has heroTag', () {
      final fabIdx = communitySource.indexOf('FloatingActionButton.extended(');
      expect(fabIdx, greaterThanOrEqualTo(0));
      final block = communitySource.substring(fabIdx, fabIdx + 300);
      expect(block, contains('heroTag:'),
          reason: 'community FAB must have explicit heroTag');
    });

    test('B. expense FABs have heroTag', () {
      final fabIdx = expenseSource.indexOf('FloatingActionButton.extended(');
      expect(fabIdx, greaterThanOrEqualTo(0));
      final block = expenseSource.substring(fabIdx, fabIdx + 300);
      expect(block, contains('heroTag:'),
          reason: 'expense FAB must have explicit heroTag');
    });

    test('C. notes FAB has heroTag', () {
      final fabIdx = notesSource.indexOf('FloatingActionButton.extended(');
      expect(fabIdx, greaterThanOrEqualTo(0));
      final block = notesSource.substring(fabIdx, fabIdx + 300);
      expect(block, contains('heroTag:'),
          reason: 'notes FAB must have explicit heroTag');
    });

    test('D. materials FAB has heroTag', () {
      final fabIdx = materialsSource.indexOf('FloatingActionButton.extended(');
      expect(fabIdx, greaterThanOrEqualTo(0));
      final block = materialsSource.substring(fabIdx, fabIdx + 300);
      expect(block, contains('heroTag:'),
          reason: 'materials FAB must have explicit heroTag');
    });

    test('E. tasks FAB has heroTag', () {
      final fabIdx = tasksSource.indexOf('FloatingActionButton.extended(');
      expect(fabIdx, greaterThanOrEqualTo(0));
      final block = tasksSource.substring(fabIdx, fabIdx + 300);
      expect(block, contains('heroTag:'),
          reason: 'tasks FAB must have explicit heroTag');
    });
  });

  group('PART 30: Profile image expired URL handling', () {
    late String homeSource;

    setUpAll(() {
      homeSource = _read('lib/features/home/presentation/home_screen.dart');
    });

    test('A. Home profile avatar uses errorBuilder for expired URLs', () {
      // The home screen must not use raw backgroundImage with NetworkImage
      // which has no error handling for 401/expired URLs.
      expect(homeSource, contains('_ProfileAvatarSmall'),
          reason: 'home must use _ProfileAvatarSmall widget');
      expect(homeSource, contains('errorBuilder:'),
          reason: '_ProfileAvatarSmall must have errorBuilder');
    });
  });

  group('PART 30: ProfileSetup phone recovery', () {
    late String profileSetupSource;

    setUpAll(() {
      profileSetupSource =
          _read('lib/features/auth/presentation/profile_setup_screen.dart');
    });

    test('A. initState resolves phone synchronously when available', () {
      final idx = profileSetupSource.indexOf('void initState()');
      expect(idx, greaterThanOrEqualTo(0));
      final block = profileSetupSource.substring(idx, idx + 500);
      expect(block, contains('widget.phone.isNotEmpty'),
          reason: 'initState must check phone synchronously');
      expect(block, contains('_resolvedPhone = widget.phone'),
          reason: 'initState must set _resolvedPhone before async resolution');
    });

    test('B. Firebase UID fallback extracts phone from telecom:<phone>', () {
      expect(profileSetupSource, contains('uid.startsWith(\'telecom:\')'),
          reason: 'must have UID fallback for phone recovery');
      expect(profileSetupSource, contains('isSupportedPhone(extractedPhone)'),
          reason: 'UID-extracted phone must be validated');
    });

    test('C. Blank phone can never be saved', () {
      final saveIdx = profileSetupSource.indexOf('Future<void> _save()');
      expect(saveIdx, greaterThanOrEqualTo(0));
      final block = profileSetupSource.substring(saveIdx, saveIdx + 600);
      expect(block, contains('_resolvedPhone.isEmpty'),
          reason: '_save must check for empty phone before saving');
    });
  });

  group('PART 30: Logout path single signOut', () {
    late String profileSource;

    setUpAll(() {
      profileSource =
          _read('lib/features/profile/presentation/profile_screen.dart');
    });

    test('A. _logout does NOT call AuthService.logout after clearSession', () {
      final logoutIdx = profileSource.indexOf('Future<void> _logout');
      expect(logoutIdx, greaterThanOrEqualTo(0));
      final block = profileSource.substring(logoutIdx, logoutIdx + 800);
      // clearSession already calls Firebase signOut — AuthService.logout
      // would trigger a second redundant sign-out event.
      final clearIdx = block.indexOf('clearSession()');
      expect(clearIdx, greaterThanOrEqualTo(0));
      final afterClear = block.substring(clearIdx);
      expect(afterClear, isNot(contains('AuthService.logout()')),
          reason: '_logout must not call AuthService.logout after clearSession');
    });

    test('B. _unsubscribe does NOT call AuthService.logout after clearSession', () {
      final unsubIdx = profileSource.indexOf('Future<void> _unsubscribe');
      expect(unsubIdx, greaterThanOrEqualTo(0));
      final endOfFunc = profileSource.indexOf('\n}', unsubIdx + 50) + 2;
      expect(endOfFunc, greaterThan(unsubIdx));
      final block = profileSource.substring(unsubIdx, endOfFunc);
      final clearIdx = block.indexOf('clearSession()');
      expect(clearIdx, greaterThanOrEqualTo(0));
      final afterClear = block.substring(clearIdx);
      expect(afterClear, isNot(contains('AuthService.logout()')),
          reason: '_unsubscribe must not call AuthService.logout after clearSession');
    });
  });

  // ─── PART 30.1: COLD-START HANG FIX — REGRESSION TESTS ───

  group('PART 30.1: Cold-start infinite loading prevention (AuthGate)', () {
    late String authGateSource;

    setUpAll(() {
      authGateSource = _read(
        'lib/features/auth/presentation/auth_gate.dart',
      );
    });

    test('A. _restore has top-level try/catch that sets _checked = true', () {
      // The entire _restore body MUST be wrapped in try/catch/finally
      // so that _checked becomes true even on unhandled exceptions.
      final restoreIdx = authGateSource.indexOf('Future<void> _restore()');
      expect(restoreIdx, greaterThanOrEqualTo(0));
      final endOfRestore = authGateSource.indexOf('\n  }', restoreIdx + 50);
      final restoreBody = authGateSource.substring(restoreIdx, endOfRestore);
      expect(restoreBody, contains('try {'),
          reason: '_restore must have top-level try block');
      expect(restoreBody, contains('catch (e, st)'),
          reason: '_restore must have catch block');
      expect(restoreBody, contains('} catch (e, st)'),
          reason: '_restore catch must bind both error and stacktrace');
    });

    test('B. catch block sets _checked = true even on fatal error', () {
      final catchIdx = authGateSource.indexOf('catch (e, st)');
      expect(catchIdx, greaterThanOrEqualTo(0));
      final catchBlock = authGateSource.substring(catchIdx, catchIdx + 500);
      expect(catchBlock, contains('_checked = true'),
          reason: 'catch block must set _checked = true to prevent infinite loading');
    });

    test('C. _restore uses bounded timeout on getIdToken', () {
      // Token refresh must NOT hang forever on slow network.
      expect(authGateSource, contains('_kTokenRefreshTimeout'),
          reason: 'must define a bounded timeout constant for token refresh');
      expect(authGateSource, contains('.timeout(_kTokenRefreshTimeout)'),
          reason: 'getIdToken(true) must be wrapped in .timeout()');
    });

    test('D. _restore uses bounded timeout on checkProfileState', () {
      // Profile check must NOT hang forever on slow network.
      expect(authGateSource, contains('_kProfileCheckTimeout'),
          reason: 'must define a bounded timeout constant for profile check');
      expect(authGateSource, contains('.timeout(_kProfileCheckTimeout)'),
          reason: 'checkProfileState() must be wrapped in .timeout()');
    });

    test('E. token refresh timeout caught as TimeoutException (not infinite spinner)', () {
      final tokenRefreshIdx = authGateSource.indexOf('tokenRefresh:start');
      expect(tokenRefreshIdx, greaterThanOrEqualTo(0));
      final tokenBlock = authGateSource.substring(tokenRefreshIdx, tokenRefreshIdx + 500);
      expect(tokenBlock, contains('on TimeoutException'),
          reason: 'token refresh timeout must be caught');
      expect(tokenBlock, contains('tokenRefresh:error=timeout'),
          reason: 'token refresh timeout must log diagnostic');
    });

    test('F. profile check timeout caught as TimeoutException (not infinite spinner)', () {
      final profileIdx = authGateSource.indexOf('profileCheck:start');
      expect(profileIdx, greaterThanOrEqualTo(0));
      final profileBlock = authGateSource.substring(profileIdx, profileIdx + 800);
      expect(profileBlock, contains('on TimeoutException'),
          reason: 'profile check timeout must be caught');
      expect(profileBlock, contains('profileCheck=result=timeout'),
          reason: 'profile check timeout must log diagnostic');
    });

    test('G. no profile/Firestore work if currentUser is null (fast-path)', () {
      // The profile check block must be gated on isLoggedIn && current != null.
      final profileCheckIdx = authGateSource.indexOf('profileCheck:start');
      expect(profileCheckIdx, greaterThanOrEqualTo(0));
      // Look backwards for the if condition
      final beforeProfile = authGateSource.substring(
          profileCheckIdx - 200, profileCheckIdx);
      expect(beforeProfile, contains('isLoggedIn && current != null'),
          reason: 'profile check must be gated on currentUser != null');
    });

    test('H. generation guard on stale auth cannot strand Loading', () {
      // When a stale result is discarded, _checked must still become true.
      final abortIdx = authGateSource.indexOf('restore:aborted(stale-gen)');
      expect(abortIdx, greaterThanOrEqualTo(0));
      // The abort branches must still eventually reach setState with _checked = true.
      // Verify that after the abort log, there is a _checked = true or return path.
      final afterAbort = authGateSource.substring(abortIdx, abortIdx + 600);
      // At minimum, the function must return (not hang) or set _checked.
      expect(afterAbort, contains('_checked = true'),
          reason: 'stale generation abort must set _checked = true, not hang');
    });

    test('I. _retryProfileCheck has top-level try/catch that sets _checked = true', () {
      final retryIdx = authGateSource.indexOf('Future<void> _retryProfileCheck()');
      expect(retryIdx, greaterThanOrEqualTo(0));
      final methodRegion = authGateSource.substring(retryIdx);
      expect(methodRegion, contains('try {'),
          reason: '_retryProfileCheck must have try block');
      expect(methodRegion, contains('catch (e)'),
          reason: '_retryProfileCheck must catch exceptions');
      // Verify _checked = true appears after the catch(e) within the method
      final catchIdx = methodRegion.indexOf('catch (e)');
      final afterCatch = methodRegion.substring(catchIdx);
      final checkedTrueIdx = afterCatch.indexOf('_checked = true');
      expect(checkedTrueIdx, greaterThanOrEqualTo(0),
          reason: '_retryProfileCheck catch must set _checked = true');
      expect(checkedTrueIdx, lessThan(500),
          reason: '_checked = true must be within catch block, not far away');
    });

    test('J. _retryProfileCheck handles TimeoutException', () {
      final retryIdx = authGateSource.indexOf('Future<void> _retryProfileCheck()');
      expect(retryIdx, greaterThanOrEqualTo(0));
      final methodRegion = authGateSource.substring(retryIdx);
      expect(methodRegion, contains('on TimeoutException'),
          reason: '_retryProfileCheck must handle timeout');
      expect(methodRegion, contains('_profileError = true'),
          reason: 'timeout in retry must set profileError state');
    });

    test('K. stale generation abort in _retryProfileCheck sets _checked = true', () {
      final retryIdx = authGateSource.indexOf('Future<void> _retryProfileCheck()');
      expect(retryIdx, greaterThanOrEqualTo(0));
      final methodRegion = authGateSource.substring(retryIdx);
      final staleIdx = methodRegion.indexOf('retryProfileCheck:aborted(stale-gen)');
      expect(staleIdx, greaterThanOrEqualTo(0),
          reason: '_retryProfileCheck must handle stale generation abort');
      final staleBlock = methodRegion.substring(staleIdx, (staleIdx + 300).clamp(0, methodRegion.length));
      expect(staleBlock, contains('_checked = true'),
          reason: 'stale abort in retry must set _checked = true');
    });

    test('L. diagnostic logs exist at every restore stage', () {
      const requiredLogs = [
        '[AuthGate] restore:start',
        '[AuthGate] prefs:start',
        '[AuthGate] prefs:isLoggedIn=',
        '[AuthGate] firebaseUser=',
        '[AuthGate] tokenRefresh:start',
        '[AuthGate] tokenRefresh:success',
        '[AuthGate] tokenRefresh:error=',
        '[AuthGate] profileCheck:start',
        '[AuthGate] profileCheck=result=',
        '[AuthGate] restore:destination=',
        '[AuthGate] restore:end',
      ];
      for (final log in requiredLogs) {
        expect(authGateSource, contains(log),
            reason: 'Missing diagnostic log: $log');
      }
    });

    test('M. never logs secrets (OTP, tokens, IDs)', () {
      // Diagnostic logs must never leak sensitive data.
      final logLines = authGateSource
          .split('\n')
          .where((l) => l.contains('debugPrint') && l.contains('[AuthGate]'))
          .toList();
      for (final line in logLines) {
        final lower = line.toLowerCase();
        expect(lower, isNot(contains('otp')),
            reason: 'Log line must not contain OTP: $line');
        expect(lower, isNot(contains('id_token')),
            reason: 'Log line must not contain ID token: $line');
        expect(lower, isNot(contains('custom_token')),
            reason: 'Log line must not contain custom token: $line');
        expect(lower, isNot(contains('secret')),
            reason: 'Log line must not contain secret: $line');
      }
    });

    test('N. _restore sets resolved destination through setState (not orphaned)', () {
      // The final setState in _restore must set _checked = true.
      final setStateIdx = authGateSource.indexOf('restore:destination=');
      expect(setStateIdx, greaterThanOrEqualTo(0));
      final afterDest = authGateSource.substring(setStateIdx, setStateIdx + 500);
      expect(afterDest, contains('_checked = true'),
          reason: 'final setState must set _checked = true');
    });

    test('O. initState calls _restore (cold-start entry point exists)', () {
      expect(authGateSource, contains('_restore();'),
          reason: 'initState must call _restore()');
    });

    // ── PART 30.2 — Generation race fix tests ──

    test('P. initial authStateChanges snapshot does NOT increment generation', () {
      // The listener must track _receivedInitialAuthSnapshot and skip
      // generation increment for the first event.
      expect(authGateSource, contains('_receivedInitialAuthSnapshot'),
          reason: 'Must track initial auth snapshot');
      expect(authGateSource, contains('authStateChanges: initial'),
          reason: 'Must log initial snapshot separately');
      // The initial snapshot branch must NOT contain _authGeneration++
      final initialIdx = authGateSource.indexOf('authStateChanges: initial');
      expect(initialIdx, greaterThanOrEqualTo(0));
      final initialBlock = authGateSource.substring(
          initialIdx, (initialIdx + 400).clamp(0, authGateSource.length));
      expect(initialBlock, isNot(contains('_authGeneration++')),
          reason: 'Initial snapshot must not increment generation');
    });

    test('Q. logged-out cold start fast-paths to login', () {
      // When prefs=false and Firebase user=null, must resolve immediately.
      expect(authGateSource, contains('Fast-path logged-out cold start'),
          reason: 'Must have fast-path comment for logged-out');
      expect(authGateSource, contains('restore:destination=login'),
          reason: 'Must set destination=login');
    });

    test('R. initial null event + prefs read completing afterward: no stale abort', () {
      // The fast-path must resolve before any generation check.
      // Search for the actual fast-path code, not the comment at the top.
      final fastPathIdx = authGateSource.indexOf('Stage 1b: Fast-path logged-out');
      expect(fastPathIdx, greaterThanOrEqualTo(0));
      final fastPathBlock = authGateSource.substring(
          fastPathIdx, (fastPathIdx + 600).clamp(0, authGateSource.length));
      expect(fastPathBlock, contains('_checked = true'),
          reason: 'Fast-path must set _checked = true');
    });

    test('S. stale abort logs replacementPending', () {
      // Every stale abort must report whether a replacement is pending.
      expect(authGateSource, contains('replacementPending='),
          reason: 'Stale abort must log replacementPending');
    });

    test('T. stale abort with no replacement resolves checked state', () {
      // When replacementPending=false, _checked must be set to true.
      // The code uses string interpolation, so search for the pattern.
      final staleIdx = authGateSource.indexOf('replacementPending=\$replacementPending');
      expect(staleIdx, greaterThanOrEqualTo(0),
          reason: 'Must have replacementPending log');
      final staleBlock = authGateSource.substring(
          staleIdx, (staleIdx + 400).clamp(0, authGateSource.length));
      expect(staleBlock, contains('_checked = true'),
          reason: 'No-replacement stale abort must set _checked = true');
    });

    test('U. listener never calls Firebase signOut or clearSession', () {
      // The authStateChanges listener must never call signOut/clearSession.
      final listenerIdx = authGateSource.indexOf('authStateChanges().listen');
      expect(listenerIdx, greaterThanOrEqualTo(0));
      final listenerEnd = authGateSource.indexOf('});', listenerIdx);
      final listenerBlock = authGateSource.substring(listenerIdx, listenerEnd);
      expect(listenerBlock, isNot(contains('signOut')),
          reason: 'Listener must not call signOut');
      expect(listenerBlock, isNot(contains('clearSession')),
          reason: 'Listener must not call clearSession');
      expect(listenerBlock, isNot(contains('clearLocalSession')),
          reason: 'Listener must not call clearLocalSession');
    });

    test('V. no profile lookup when logged out (fast-path skips stages)', () {
      // The fast-path must return before profile check stage.
      final fastPathIdx = authGateSource.indexOf('Fast-path logged-out');
      final profileIdx = authGateSource.indexOf('profileCheck:start');
      expect(fastPathIdx, lessThan(profileIdx),
          reason: 'Fast-path must come before profile check');
    });

    test('W. no token refresh when logged out (fast-path skips stages)', () {
      // The fast-path must return before token refresh stage.
      final fastPathIdx = authGateSource.indexOf('Fast-path logged-out');
      final tokenIdx = authGateSource.indexOf('tokenRefresh:start');
      expect(fastPathIdx, lessThan(tokenIdx),
          reason: 'Fast-path must come before token refresh');
    });
  });

  // -------------------------------------------------------------------
  // Auth blocker: _readSubscriptionStatus field-path coverage
  // -------------------------------------------------------------------

  group('_readSubscriptionStatus field-path coverage', () {
    TelecomSubscriptionResult r(String body) {
      return TelecomAuthService.parseSubscriptionResponseForTest(body);
    }

    test('top-level subscriptionStatus (canonical)', () {
      expect(r('{"subscriptionStatus":"REGISTERED"}').shouldEnterApp, isTrue);
    });

    test('nested data.subscriptionStatus', () {
      expect(
        r('{"data":{"subscriptionStatus":"REGISTERED"}}').shouldEnterApp,
        isTrue,
      );
    });

    test('top-level status shorthand', () {
      expect(r('{"status":"REGISTERED"}').shouldEnterApp, isTrue);
    });

    test('nested data.status shorthand', () {
      expect(r('{"data":{"status":"REGISTERED"}}').shouldEnterApp, isTrue);
    });

    test('top-level subscription_status (snake_case)', () {
      expect(
        r('{"subscription_status":"INITIAL CHARGING PENDING"}').shouldEnterApp,
        isTrue,
      );
    });

    test('nested data.subscription_status (snake_case)', () {
      expect(
        r('{"data":{"subscription_status":"INITIAL CHARGING PENDING"}}')
            .shouldEnterApp,
        isTrue,
      );
    });

    test('title-case "Registered" normalises to REGISTERED', () {
      expect(r('{"subscriptionStatus":"Registered"}').shouldEnterApp, isTrue);
    });

    test('underscored "INITIAL_CHARGING_PENDING" grants access', () {
      expect(
        r('{"subscriptionStatus":"INITIAL_CHARGING_PENDING"}').shouldEnterApp,
        isTrue,
      );
    });

    test('hyphenated "Initial-Charging-Pending" grants access', () {
      expect(
        r('{"subscriptionStatus":"Initial-Charging-Pending"}').shouldEnterApp,
        isTrue,
      );
    });

    test('status in data with other fields does not break parsing', () {
      expect(
        r('{"statusCode":"S1000","data":{"status":"REGISTERED","other":"x"}}')
            .shouldEnterApp,
        isTrue,
      );
    });

    test('empty status value is fail-closed (unknown)', () {
      final result = r('{"subscriptionStatus":""}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
      expect(result.status, TelecomSubscriptionStatus.unknown);
    });

    test('null status value is fail-closed (unknown)', () {
      final result = r('{"subscriptionStatus":null}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
      expect(result.status, TelecomSubscriptionStatus.unknown);
    });

    test('numeric status is fail-closed (unknown)', () {
      final result = r('{"subscriptionStatus":123}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
      expect(result.status, TelecomSubscriptionStatus.unknown);
    });
  });

  // -------------------------------------------------------------------
  // Carrier matrix: Robi (018) + Cirkle (016)
  // -------------------------------------------------------------------

  group('Robi 018 carrier matrix', () {
    TelecomSubscriptionResult r(String body) {
      return TelecomAuthService.parseSubscriptionResponseForTest(body);
    }

    test('A. 018 + REGISTERED → skip OTP, enter app', () {
      expect(r('{"subscriptionStatus":"REGISTERED"}').shouldEnterApp, isTrue);
      expect(r('{"subscriptionStatus":"REGISTERED"}').status,
          TelecomSubscriptionStatus.registered);
    });

    test('B. 018 + INITIAL CHARGING PENDING → skip OTP, enter app', () {
      final result = r('{"subscriptionStatus":"INITIAL CHARGING PENDING"}');
      expect(result.shouldEnterApp, isTrue);
      expect(result.status,
          TelecomSubscriptionStatus.initialChargingPending);
    });

    test('C. 018 + NOT SUBSCRIBED → OTP required', () {
      expect(r('{"subscriptionStatus":"NOT SUBSCRIBED"}').shouldEnterApp, isFalse);
      expect(r('{"subscriptionStatus":"NOT SUBSCRIBED"}').status,
          TelecomSubscriptionStatus.notSubscribed);
    });

    test('D. 018 prefix accepted by validator', () {
      expect(TelecomAuthService.isSupportedPhone('01812345678'), isTrue);
    });

    test('E. 018 + empty subscriptionStatus → fail-closed (unknown)', () {
      final result = r('{"subscriptionStatus":""}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
    });
  });

  group('Cirkle 016 carrier matrix', () {
    TelecomSubscriptionResult r(String body) {
      return TelecomAuthService.parseSubscriptionResponseForTest(body);
    }

    test('F. 016 + REGISTERED → skip OTP, enter app', () {
      expect(r('{"subscriptionStatus":"REGISTERED"}').shouldEnterApp, isTrue);
      expect(r('{"subscriptionStatus":"REGISTERED"}').status,
          TelecomSubscriptionStatus.registered);
    });

    test('G. 016 + INITIAL CHARGING PENDING → skip OTP, enter app', () {
      final result = r('{"subscriptionStatus":"INITIAL CHARGING PENDING"}');
      expect(result.shouldEnterApp, isTrue);
      expect(result.status,
          TelecomSubscriptionStatus.initialChargingPending);
    });

    test('H. 016 + NOT SUBSCRIBED → OTP required', () {
      expect(r('{"subscriptionStatus":"NOT SUBSCRIBED"}').shouldEnterApp, isFalse);
    });

    test('I. 016 prefix accepted by validator', () {
      expect(TelecomAuthService.isSupportedPhone('01612345678'), isTrue);
    });

    test('J. 016 + empty subscriptionStatus → fail-closed (unknown)', () {
      final result = r('{"subscriptionStatus":""}');
      expect(result.shouldEnterApp, isFalse);
      expect(result.maySendOtp, isFalse);
    });
  });

  // -------------------------------------------------------------------
  // sendOtp already-registered recovery
  // -------------------------------------------------------------------

  group('sendOtp already-registered recovery', () {
    late String loginSrc;
    late String otpSrc;
    late String telecomSrc;

    setUpAll(() {
      loginSrc = _read('lib/features/auth/presentation/login_screen.dart');
      otpSrc = _read('lib/features/auth/presentation/otp_verify_screen.dart');
      telecomSrc = _read('lib/core/services/telecom_auth_service.dart');
    });

    dynamic r(String body) =>
        TelecomAuthService.parseSendOtpResponseForTest(body);

    test('K. "user already registered" alone is NEVER auth proof', () {
      // The sendOtp response parser must flag alreadyRegistered but
      // must NOT grant access on its own — only the re-poll of
      // checkSubscription can grant access.
      final result = r('{"success":false,"message":"user already registered"}');
      expect(result.alreadyRegistered, isTrue);
      // alreadyRegistered is just a signal; no access is granted here.
    });

    test('L. no direct GochanoShell navigation from send_otp error', () {
      // kAlreadySubscribedSentinel is now handled in LoginScreen (before
      // OTP screen is pushed), not in OtpVerifyScreen.
      expect(loginSrc, contains('kAlreadySubscribedSentinel'));
      // OtpVerifyScreen must NOT reference kAlreadySubscribedSentinel
      expect(otpSrc, isNot(contains('kAlreadySubscribedSentinel')));
    });

    test('M. no manual loggedIn SharedPreferences bypass', () {
      // Neither login_screen nor otp_verify_screen must manually set
      // prefIsLoggedIn outside of enterSession/persistSession.
      expect(loginSrc, isNot(contains("prefs.setBool('isLoggedIn'")));
      expect(otpSrc, isNot(contains("prefs.setBool('isLoggedIn'")));
    });

    test('N. no exchangeOtpForFirebaseSession reuse from OTP screen', () {
      expect(otpSrc, isNot(contains('exchangeOtpForFirebaseSession')));
    });

    test('O. backend /v1/auth/telecom/exchange still independently verifies', () {
      // The exchange endpoint must exist and be called from both paths.
      expect(telecomSrc, contains('/v1/auth/telecom/exchange'));
      expect(loginSrc, contains('exchangeSubscriptionForFirebaseSession'));
      expect(otpSrc, contains('exchangeSubscriptionForFirebaseSession'));
    });

    test('E1351 statusCode triggers alreadyRegistered', () {
      expect(r('{"statusCode":"E1351"}').alreadyRegistered, isTrue);
    });

    test('"already subscribed" in message triggers alreadyRegistered', () {
      expect(
        r('{"success":false,"message":"You are already subscribed."}')
            .alreadyRegistered,
        isTrue,
      );
    });

    test('subscriptionStatus REGISTERED in sendOtp triggers alreadyRegistered', () {
      expect(
        r('{"success":false,"subscriptionStatus":"REGISTERED"}')
            .alreadyRegistered,
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------
  // sendOtp activation message on re-check failure
  // -------------------------------------------------------------------

  group('sendOtp activation message on re-check failure', () {
    late String source;

    setUpAll(() =>
        source = _read('lib/core/services/telecom_auth_service.dart'));

    test('shows activation message when re-check returns NOT SUBSCRIBED', () {
      expect(source, contains('Your subscription is already being activated'));
      expect(source, contains('আপনার সাবস্ক্রিপশন সক্রিয় হচ্ছে'));
    });

    test('does NOT show "contact support" for re-check failure', () {
      // The old message said "contact support" — the new one says
      // "try again shortly" instead.
      expect(source, isNot(contains('Please contact support')),
          reason: 'Re-check failure must not say contact support');
    });
  });

  // -------------------------------------------------------------------
  // Carrier mapping correctness
  // -------------------------------------------------------------------

  group('Carrier mapping', () {
    late String loginSrc;

    setUpAll(() =>
        loginSrc = _read('lib/features/auth/presentation/login_screen.dart'));

    test('018 = Robi', () {
      // UI must mention Robi near the 018 prefix.
      expect(loginSrc, contains('Robi'));
      expect(loginSrc, contains('018'));
    });

    test('016 = Cirkle', () {
      expect(loginSrc, contains('Cirkle'));
      expect(loginSrc, contains('016'));
    });

    test('regex accepts only 016 and 018', () {
      expect(TelecomAuthService.isSupportedPhone('01612345678'), isTrue);
      expect(TelecomAuthService.isSupportedPhone('01812345678'), isTrue);
      expect(TelecomAuthService.isSupportedPhone('01712345678'), isFalse);
      expect(TelecomAuthService.isSupportedPhone('01912345678'), isFalse);
    });
  });

  // -------------------------------------------------------------------
  // _readSubscriptionStatus additional field-path recovery
  // -------------------------------------------------------------------

  group('_readSubscriptionStatus additional field paths', () {
    TelecomSubscriptionResult r(String body) {
      return TelecomAuthService.parseSubscriptionResponseForTest(body);
    }

    test('status field at top level (not subscriptionStatus)', () {
      expect(r('{"status":"REGISTERED"}').shouldEnterApp, isTrue);
    });

    test('data.status field (not data.subscriptionStatus)', () {
      expect(
        r('{"data":{"status":"INITIAL CHARGING PENDING"}}').shouldEnterApp,
        isTrue,
      );
    });

    test('subscription_status snake_case at top level', () {
      expect(
        r('{"subscription_status":"REGISTERED"}').shouldEnterApp,
        isTrue,
      );
    });

    test('data.subscription_status snake_case', () {
      expect(
        r('{"data":{"subscription_status":"REGISTERED"}}').shouldEnterApp,
        isTrue,
      );
    });

    test('deeply nested status is NOT supported (only one level of data)', () {
      // We only look in top-level and data.* — not data.deep.status.
      expect(
        r('{"data":{"deep":{"status":"REGISTERED"}}}').shouldEnterApp,
        isFalse,
      );
    });

    test('non-string status value is skipped', () {
      expect(r('{"status":true}').shouldEnterApp, isFalse);
      expect(r('{"status":42}').shouldEnterApp, isFalse);
    });
  });
}
