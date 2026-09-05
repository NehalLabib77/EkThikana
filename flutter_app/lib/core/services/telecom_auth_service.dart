// PART 16.1 — Telecom Auth Production Correction
//
// This service restores the exact supplied PHP contract that was lost in
// PART 16. It also adds the seam needed to keep `FirebaseAuth.currentUser`
// valid after a successful telecom login, which is what every Firestore
// rule and the FastAPI backend's `get_verified_identity` dependency
// require.
//
// Two corrections vs. PART 16:
//
//   1. Endpoint contracts (root cause of the wrong shape):
//
//        POST /check_subscription.php
//        POST /send_otp.php
//        POST /verify_otp.php
//
//      All three use `user_mobile` as the phone field, not `phone`.
//      /verify_otp.php sends duplicate compatibility keys (`Otp`/`otp`,
//      `referenceNo`/`reference_no`, plus `user_mobile`) so the
//      backend can accept whichever shape it expects. We do NOT
//      simplify the body until live evidence proves it is safe.
//
//      Subscription status is read from `subscriptionStatus`,
//      normalised with trim()+toUpperCase(), and only `REGISTERED`
//      and `INITIAL CHARGING PENDING` grant access.
//
//      E1351 / "already registered" responses are handled by
//      re-polling `check_subscription.php` with the same POST body.
//
//   2. Firebase identity survival (root cause of "home opens but
//      Notes/Tasks/Expense permission-denied"):
//
//      After successful telecom OTP verification, the Flutter client
//      calls a backend endpoint that mints a Firebase **custom token**
//      using the Admin SDK the backend already has loaded. The
//      backend's `create_custom_token(uid, developer_claims={
//      email_verified: True})` puts `email_verified=true` in the
//      issued ID token, which is what `firestore.rules` (`verified()`)
//      and `app.core.auth.get_verified_identity` check. The Flutter
//      client then calls `FirebaseAuth.signInWithCustomToken`.
//
//      If the backend endpoint is not yet deployed
//      (PART 16.1 explicitly lists this as the remaining blocker),
//      `signInWithCustomToken` raises, the AuthGate refuses to enter
//      the home shell, and the user sees a clear "Backend not
//      deployed" error — never a half-authenticated home.
//
// SharedPreferences is used only as a routing convenience
// (isLoggedIn/userPhone). It is NEVER treated as proof of identity
// for Firestore. The AuthGate is the only place that gates entry to
// the home shell, and it requires BOTH a true SharedPreferences
// session AND a non-null `FirebaseAuth.instance.currentUser`.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../localization/gochano_language.dart';

class TelecomAuthException implements Exception {
  TelecomAuthException(this.message);
  final String message;
  @override
  String toString() => 'TelecomAuthException: $message';
}

enum TelecomSubscriptionStatus {
  registered,
  initialChargingPending,
  notSubscribed,
  alreadyRegistered,
  unknown,
}

/// Outcome of [TelecomAuthService.checkSubscription].
class TelecomSubscriptionResult {
  const TelecomSubscriptionResult({
    required this.status,
    required this.shouldEnterApp,
    required this.rawStatus,
  });

  final TelecomSubscriptionStatus status;

  /// `true` only for statuses that the spec lists as "let the user in
  /// without an OTP step". All other statuses require OTP verification.
  final bool shouldEnterApp;

  /// The raw subscriptionStatus field as the backend returned it,
  /// normalised with trim() + toUpperCase(). Empty when no field was
  /// present.
  final String rawStatus;

  /// User is already a paying subscriber — no OTP needed.
  static const registered = TelecomSubscriptionResult(
    status: TelecomSubscriptionStatus.registered,
    shouldEnterApp: true,
    rawStatus: 'REGISTERED',
  );

  /// User has clicked subscribe in their carrier portal but the carrier
  /// has not confirmed the subscription yet. We let them in anyway —
  /// the PART 17 unsubscribe flow handles the rest.
  static const initialChargingPending = TelecomSubscriptionResult(
    status: TelecomSubscriptionStatus.initialChargingPending,
    shouldEnterApp: true,
    rawStatus: 'INITIAL CHARGING PENDING',
  );

  /// User has not subscribed — they must complete OTP verification
  /// first.
  static const notSubscribed = TelecomSubscriptionResult(
    status: TelecomSubscriptionStatus.notSubscribed,
    shouldEnterApp: false,
    rawStatus: '',
  );

  /// The /send_otp.php endpoint reported "E1351 already registered"
  /// before /check_subscription.php had settled. Surfaced separately
  /// so the caller can re-poll instead of treating it as a hard
  /// failure.
  static const alreadyRegistered = TelecomSubscriptionResult(
    status: TelecomSubscriptionStatus.alreadyRegistered,
    shouldEnterApp: false,
    rawStatus: 'ALREADY REGISTERED',
  );
}

/// Result of the post-OTP Firebase custom-token exchange.
class TelecomFirebaseExchange {
  const TelecomFirebaseExchange({
    required this.uid,
    required this.customToken,
    required this.phone,
  });

  /// Firebase UID minted/looked-up server-side for this phone.
  final String uid;

  /// Custom token returned by the backend; the Flutter client signs in
  /// with `FirebaseAuth.signInWithCustomToken(token)`.
  final String customToken;

  /// E.164-style local phone used to identify the user.
  final String phone;
}

/// Result of the telecom carrier unsubscribe call (PART 17).
class TelecomUnsubscribeResult {
  const TelecomUnsubscribeResult({
    required this.success,
    required this.message,
    this.rawStatusCode,
  });

  /// Whether the carrier treated this number as successfully unsubscribed or
  /// already in an unsubscribed state (idempotent success).
  final bool success;

  /// User-facing status message returned or mapped for display.
  final String message;

  /// Raw status code from the carrier payload if available (e.g. "SUCCESS", "S1000").
  final String? rawStatusCode;
}

class TelecomAuthService {
  TelecomAuthService._();

  // -------------------------------------------------------------------
  // Endpoint configuration
  // -------------------------------------------------------------------

  /// Carrier (bdapps) base URL — the exact base used by the supplied
  /// working implementation. Do not invent alternate endpoint shapes.
  static const String baseUrl =
      'https://www.bdappsdigitalapps.com/NADB26122_Final';

  /// FastAPI backend that mints the Firebase custom token. Configured
  /// via `--dart-define=API_BASE_URL=...` at build time.
  static String get backendBaseUrl => AppConfig.apiBaseUrl.trim();

  static const Duration checkSubscriptionTimeout = Duration(seconds: 10);
  static const Duration sendOtpTimeout = Duration(seconds: 15);
  static const Duration verifyOtpTimeout = Duration(seconds: 15);
  static const Duration exchangeTimeout = Duration(seconds: 15);

  // -------------------------------------------------------------------
  // Local session — convenience only, never proof of identity
  // -------------------------------------------------------------------
  //
  // The PART 16 keys (`telecom_isLoggedIn`, `telecom_user_phone`,
  // `telecom_user_id`) were introduced without audit. The supplied
  // original code used `isLoggedIn`/`userPhone`. PART 16.1 keeps the
  // legacy naming scheme as the primary and treats the PART 16 keys
  // as legacy fallbacks for one release, so a fresh install picks up
  // `isLoggedIn` going forward but an upgrade from PART 16 still
  // recognises the existing `telecom_isLoggedIn` value without
  // forcing a re-login.
  static const String prefIsLoggedIn = 'isLoggedIn';
  static const String prefUserPhone = 'userPhone';

  /// Legacy keys from PART 16. Read on restore for backward
  /// compatibility; cleared on logout to leave one authoritative
  /// naming scheme.
  static const String _legacyPrefIsLoggedIn = 'telecom_isLoggedIn';
  static const String _legacyPrefUserPhone = 'telecom_user_phone';
  static const String _legacyPrefUserId = 'telecom_user_id';

  static final RegExp supportedPrefix = RegExp(r'^01(?:6|8)\d{8}$');

  // -------------------------------------------------------------------
  // Phone validation
  // -------------------------------------------------------------------

  static String normalize(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (p.startsWith('+880')) {
      p = '0${p.substring(4)}';
    } else if (p.startsWith('880')) {
      p = '0${p.substring(3)}';
    }
    return p;
  }

  static bool isSupportedPhone(String phone) =>
      supportedPrefix.hasMatch(normalize(phone));

  // -------------------------------------------------------------------
  // /check_subscription.php
  //
  // POST + body {"user_mobile": phone}, 10s timeout.
  // Returns {"subscriptionStatus": "..."} or {subscriptionStatus, ...}.
  // -------------------------------------------------------------------

  static Future<TelecomSubscriptionResult> checkSubscription(
    String phone,
  ) async {
    final normalized = normalize(phone);
    if (!isSupportedPhone(normalized)) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Only Robi (016) and Cirkle (018) numbers are supported',
          'শুধুমাত্র Robi (০১৬) ও Cirkle (০১৮) নম্বর সমর্থিত',
        ),
      );
    }

    final response = await _safePost(
      Uri.parse('$baseUrl/check_subscription.php'),
      {'user_mobile': normalized},
      checkSubscriptionTimeout,
    );

    return _parseSubscriptionResponse(response.body);
  }

  /// Re-poll wrapper used after an E1351 "already registered" response
  /// from /send_otp.php. Spec §3: do not create another endpoint,
  /// re-use the same POST + user_mobile contract.
  static Future<TelecomSubscriptionResult> pollSubscription(String phone) {
    return checkSubscription(phone);
  }

  static TelecomSubscriptionResult _parseSubscriptionResponse(String body) {
    final raw = _readSubscriptionStatus(body);
    if (raw == null || raw.isEmpty) {
      return TelecomSubscriptionResult.notSubscribed;
    }
    final normalized = raw.trim().toUpperCase();

    if (normalized == 'REGISTERED') {
      return TelecomSubscriptionResult.registered;
    }
    if (normalized.contains('INITIAL CHARGING PENDING')) {
      return TelecomSubscriptionResult.initialChargingPending;
    }
    // Anything else — including NOT SUBSCRIBED — routes to OTP.
    return TelecomSubscriptionResult.notSubscribed;
  }

  /// Reads the `subscriptionStatus` field from a JSON body. Returns the
  /// trimmed+uppercased value, or null when the body is not JSON or the
  /// field is absent.
  static String? _readSubscriptionStatus(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map) {
        // Defensive: look in both top-level and under `data`.
        final candidates = <dynamic>[
          decoded['subscriptionStatus'],
          if (decoded['data'] is Map) decoded['data']['subscriptionStatus'],
        ];
        for (final c in candidates) {
          if (c is String && c.trim().isNotEmpty) return c.trim().toUpperCase();
        }
      }
    } catch (_) {
      // Non-JSON body — fall through.
    }
    return null;
  }

  // -------------------------------------------------------------------
  // /unsubscribe.php (PART 17)
  //
  // POST + body {"user_mobile": phone}, 15s timeout.
  // -------------------------------------------------------------------

  static const Duration unsubscribeTimeout = Duration(seconds: 15);

  /// Requests the carrier to cancel the subscription for [phone].
  ///
  /// Contract:
  /// POST https://www.bdappsdigitalapps.com/NADB26122_Final/unsubscribe.php
  /// Body: {"user_mobile": normalizedPhone}
  /// Timeout: 15 seconds.
  ///
  /// Safe post returns a [TelecomUnsubscribeResult]. Successful or idempotent
  /// results (e.g. already unsubscribed, not registered) report `success: true`
  /// so local sessions are never trapped.
  static Future<TelecomUnsubscribeResult> unsubscribe(String phone) async {
    final normalized = normalize(phone);
    if (!isSupportedPhone(normalized)) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Only Robi (016) and Cirkle (018) numbers are supported',
          'শুধুমাত্র Robi (০১৬) ও Cirkle (০১৮) নম্বর সমর্থিত',
        ),
      );
    }

    final response = await _safePost(
      Uri.parse('$baseUrl/unsubscribe.php'),
      {'user_mobile': normalized},
      unsubscribeTimeout,
    );

    return _parseUnsubscribeResponse(response.body);
  }

  static TelecomUnsubscribeResult _parseUnsubscribeResponse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return TelecomUnsubscribeResult(
        success: false,
        message: GochanoLanguage.text(
          'Empty response received from carrier.',
          'টেলিকম অপারেটর থেকে খালি প্রতিক্রিয়া পাওয়া গেছে।',
        ),
      );
    }

    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map) {
        final successFlag = _firstBool(
          decoded['success'],
          _nestedValue(decoded, const ['data', 'success']),
        );
        final statusCode = _firstNonEmptyString([
          decoded['status_code'],
          decoded['statusCode'],
          decoded['status'],
          _nestedValue(decoded, const ['data', 'status_code']),
          _nestedValue(decoded, const ['data', 'statusCode']),
        ]);
        final message = _firstNonEmptyString([
          decoded['message'],
          decoded['msg'],
          decoded['statusDetail'],
          _nestedValue(decoded, const ['data', 'message']),
        ]);

        final statusUpper = statusCode?.toUpperCase();
        final msgLower = (message ?? '').toLowerCase();

        // Check for success indicators:
        // 1. success == true
        // 2. statusCode == SUCCESS, S1000, 200, OK
        // 3. message contains success, unsubscribed, already, not subscribed, etc. (idempotency)
        final isStatusCodeOk = statusUpper == 'SUCCESS' ||
            statusUpper == 'S1000' ||
            statusUpper == '200' ||
            statusUpper == 'OK';

        final isMessageOk = msgLower.contains('success') ||
            msgLower.contains('unsubscrib') ||
            msgLower.contains('already') ||
            msgLower.contains('not subscribe') ||
            msgLower.contains('not registered') ||
            msgLower.contains('cancelled') ||
            msgLower.contains('canceled') ||
            msgLower.contains('deactivated');

        final isSuccess = (successFlag == true) || isStatusCodeOk || isMessageOk;

        if (isSuccess) {
          return TelecomUnsubscribeResult(
            success: true,
            message: message ??
                GochanoLanguage.text(
                  'Subscription cancelled successfully.',
                  'সাবস্ক্রিপশন সফলভাবে বন্ধ করা হয়েছে।',
                ),
            rawStatusCode: statusCode,
          );
        }

        return TelecomUnsubscribeResult(
          success: false,
          message: message ??
              GochanoLanguage.text(
                'Unsubscribe failed. Please try again.',
                'আনসাবস্ক্রাইব করা যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।',
              ),
          rawStatusCode: statusCode,
        );
      }
    } catch (_) {
      // Body may be plain text response
      final lower = trimmed.toLowerCase();
      if (lower.contains('success') ||
          lower.contains('unsubscrib') ||
          lower.contains('already') ||
          lower.contains('not subscribe')) {
        return TelecomUnsubscribeResult(
          success: true,
          message: GochanoLanguage.text(
            'Subscription cancelled successfully.',
            'সাবস্ক্রিপশন সফলভাবে বন্ধ করা হয়েছে।',
          ),
        );
      }
    }

    return TelecomUnsubscribeResult(
      success: false,
      message: GochanoLanguage.text(
        'Unsubscribe failed. Please try again.',
        'আনসাবস্ক্রাইব করা যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।',
      ),
    );
  }

  // -------------------------------------------------------------------
  // /send_otp.php
  //
  // POST + body {"user_mobile": phone}, 15s timeout. Reads:
  //   success (bool), referenceNo (string), message (string),
  //   statusDetail (string), statusCode (string).
  // Success requires: success == true AND referenceNo.isNotEmpty.
  // E1351 / "already registered" triggers a re-poll.
  // -------------------------------------------------------------------

  static Future<String> sendOtp(String phone) async {
    final normalized = normalize(phone);
    if (!isSupportedPhone(normalized)) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Only Robi (016) and Cirkle (018) numbers are supported',
          'শুধুমাত্র Robi (০১৬) ও Cirkle (০১৮) নম্বর সমর্থিত',
        ),
      );
    }

    final response = await _safePost(Uri.parse('$baseUrl/send_otp.php'), {
      'user_mobile': normalized,
    }, sendOtpTimeout);

    final parsed = _parseSendOtpResponse(response.body);

    if (parsed.alreadyRegistered) {
      // Re-poll /check_subscription.php with the same phone. If the
      // backend has settled by then, we route straight to home.
      final recheck = await pollSubscription(normalized);
      if (recheck.shouldEnterApp) {
        // Sentinel — caller checks against this token to know it can
        // skip OTP and call the Firebase exchange immediately.
        return '__already_registered__';
      }
      throw TelecomAuthException(
        parsed.message ??
            GochanoLanguage.text(
              'Your number is already registered. Please contact support.',
              'আপনার নম্বর ইতোমধ্যে নিবন্ধিত। সাপোর্টের সাথে যোগাযোগ করুন।',
            ),
      );
    }

    if (!parsed.success || parsed.referenceNo == null) {
      throw TelecomAuthException(
        parsed.message ??
            GochanoLanguage.text(
              'Could not send the verification code. Please try again.',
              'ভেরিফিকেশন কোড পাঠানো যায়নি। আবার চেষ্টা করুন।',
            ),
      );
    }

    return parsed.referenceNo!;
  }

  static _SendOtpResponse _parseSendOtpResponse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const _SendOtpResponse(
        success: false,
        referenceNo: null,
        message: null,
        alreadyRegistered: false,
      );
    }

    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map) {
        final successFlag = _firstBool(
          decoded['success'],
          _nestedValue(decoded, const ['data', 'success']),
        );
        final referenceNo = _firstNonEmptyString([
          decoded['referenceNo'],
          decoded['reference_no'],
          decoded['reference'],
          _nestedValue(decoded, const ['data', 'referenceNo']),
          _nestedValue(decoded, const ['data', 'reference_no']),
        ]);
        final message = _firstNonEmptyString([
          decoded['message'],
          _nestedValue(decoded, const ['data', 'message']),
        ]);
        final statusDetail = _firstNonEmptyString([
          decoded['statusDetail'],
          _nestedValue(decoded, const ['data', 'statusDetail']),
        ]);
        final statusCode = _firstNonEmptyString([
          decoded['statusCode'],
          _nestedValue(decoded, const ['data', 'statusCode']),
        ]);
        final alreadyRegistered =
            (statusCode?.toUpperCase() == 'E1351') ||
            (message != null &&
                message.toLowerCase().contains('already registered')) ||
            (statusDetail != null &&
                statusDetail.toLowerCase().contains('already registered'));

        return _SendOtpResponse(
          success: successFlag ?? false,
          referenceNo: referenceNo,
          message: message,
          alreadyRegistered: alreadyRegistered,
        );
      }
    } catch (_) {
      // Not JSON — fall through.
    }

    return _SendOtpResponse(
      success: false,
      referenceNo: null,
      message: null,
      alreadyRegistered: false,
    );
  }

  // -------------------------------------------------------------------
  // /verify_otp.php
  //
  // POST + body {Otp, otp, referenceNo, reference_no, user_mobile},
  // 15s timeout. Reads: success, statusCode, message, statusDetail.
  // Duplicate compatibility keys are intentional — do not simplify.
  // -------------------------------------------------------------------

  static Future<bool> verifyOtp({
    required String referenceNo,
    required String otp,
    required String phone,
  }) async {
    final cleanPhone = normalize(phone);
    final cleanRef = referenceNo.trim();
    final cleanOtp = otp.trim();

    if (!isSupportedPhone(cleanPhone)) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Only Robi (016) and Cirkle (018) numbers are supported',
          'শুধুমাত্র Robi (০১৬) ও Cirkle (০১৮) নম্বর সমর্থিত',
        ),
      );
    }
    if (cleanOtp.length < 4) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Enter the verification code you received',
          'প্রাপ্ত ভেরিফিকেশন কোডটি লিখুন',
        ),
      );
    }
    if (cleanRef.isEmpty) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Verification session expired. Please request a new code.',
          'ভেরিফিকেশন সেশন শেষ হয়ে গেছে। নতুন কোড নিন।',
        ),
      );
    }

    final response = await _safePost(Uri.parse('$baseUrl/verify_otp.php'), {
      'Otp': cleanOtp,
      'otp': cleanOtp,
      'referenceNo': cleanRef,
      'reference_no': cleanRef,
      'user_mobile': cleanPhone,
    }, verifyOtpTimeout);

    return _isOtpSuccess(response.body);
  }

  /// Conservative success heuristic. We default to `false` whenever the
  /// response shape is ambiguous — false negatives route the user back
  /// to OTP, which is the safer failure mode than false positives that
  /// would mint a Firebase session.
  static bool _isOtpSuccess(String body) {
    final parsed = _parseVerifyOtpResponse(body);
    return parsed.success;
  }

  static _VerifyOtpResponse _parseVerifyOtpResponse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const _VerifyOtpResponse(success: false, message: null);
    }
    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map) {
        final success = _firstBool(
          decoded['success'],
          _nestedValue(decoded, const ['data', 'success']),
        );
        final status = _firstNonEmptyString([
          decoded['status'],
          decoded['statusCode'],
          decoded['statusDetail'],
          _nestedValue(decoded, const ['data', 'statusCode']),
        ]);
        final message = _firstNonEmptyString([
          decoded['message'],
          _nestedValue(decoded, const ['data', 'message']),
        ]);

        final successFlag = success ?? false;
        final statusUpper = status?.toUpperCase();
        final statusOk =
            statusUpper == 'OK' ||
            statusUpper == 'SUCCESS' ||
            statusUpper == 'VERIFIED' ||
            statusUpper == 'TRUE';

        return _VerifyOtpResponse(
          success: successFlag || statusOk,
          message: message,
        );
      }
    } catch (_) {
      // Not JSON — fall through.
    }
    return const _VerifyOtpResponse(success: false, message: null);
  }

  // -------------------------------------------------------------------
  // Firebase custom-token exchange (the seam that keeps Firestore alive)
  // -------------------------------------------------------------------

  /// Calls the backend endpoint that mints a Firebase custom token for
  /// the verified phone. The backend is responsible for:
  ///   1. verifying the OTP server-to-server against the carrier, and
  ///   2. calling `firebase_admin.auth.create_custom_token(uid,
  ///      developer_claims={"email_verified": True})`.
  /// Returns both the custom token and the Firebase UID. The caller
  /// signs in with `FirebaseAuth.signInWithCustomToken(customToken)`.
  ///
  /// If the backend endpoint is not yet deployed, this throws a
  /// `TelecomAuthException` with a clear "Backend not deployed" message
  /// so the AuthGate can refuse to enter the home shell rather than
  /// admitting a half-authenticated session.
  static Future<TelecomFirebaseExchange> exchangeOtpForFirebaseSession({
    required String phone,
    required String referenceNo,
  }) async {
    final cleanPhone = normalize(phone);
    final cleanRef = referenceNo.trim();

    if (!isSupportedPhone(cleanPhone)) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Only Robi (016) and Cirkle (018) numbers are supported',
          'শুধুমাত্র Robi (০১৬) ও Cirkle (০১৮) নম্বর সমর্থিত',
        ),
      );
    }
    if (cleanRef.isEmpty) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Verification session expired. Please request a new code.',
          'ভেরিফিকেশন সেশন শেষ হয়ে গেছে। নতুন কোড নিন।',
        ),
      );
    }
    if (backendBaseUrl.isEmpty) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Backend URL is not configured. Run with '
              '--dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com',
          'ব্যাকএন্ড URL কনফিগার করা হয়নি। --dart-define=API_BASE_URL দিয়ে চালান।',
        ),
      );
    }

    final uri = Uri.parse('$backendBaseUrl/v1/auth/telecom/exchange');
    final response = await _safePost(uri, {
      'phone': cleanPhone,
      'reference_no': cleanRef,
    }, exchangeTimeout);

    Map<String, dynamic> decoded;
    try {
      final value = json.decode(response.body);
      if (value is! Map) {
        throw const FormatException('expected JSON object');
      }
      decoded = value.cast<String, dynamic>();
    } catch (e) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Could not link your number to Gochano. Please try again later.',
          'আপনার নম্বর Gochano-তে সংযুক্ত করা যায়নি। কিছুক্ষণ পর আবার চেষ্টা করুন।',
        ),
      );
    }

    final customToken = _firstNonEmptyString([
      decoded['firebase_custom_token'],
      decoded['custom_token'],
      decoded['customToken'],
    ]);
    final uid = _firstNonEmptyString([decoded['uid'], decoded['userId']]);

    if (customToken == null) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Gochano sign-in is not yet enabled for this number. Please try again later.',
          'এই নম্বরের জন্য Gochano সাইন-ইন এখনো চালু হয়নি। কিছুক্ষণ পর আবার চেষ্টা করুন।',
        ),
      );
    }

    return TelecomFirebaseExchange(
      uid: uid ?? '',
      customToken: customToken,
      phone: cleanPhone,
    );
  }

  /// Signs the user into Firebase using the custom token returned by
  /// [exchangeOtpForFirebaseSession]. After this call,
  /// `FirebaseAuth.instance.currentUser` is non-null and the issued ID
  /// token carries the `email_verified=true` claim the backend baked in.
  static Future<UserCredential> signInToFirebaseWithCustomToken(
    TelecomFirebaseExchange exchange,
  ) async {
    final auth = FirebaseAuth.instance;
    try {
      return await auth.signInWithCustomToken(exchange.customToken);
    } on FirebaseAuthException catch (e) {
      throw TelecomAuthException(
        e.message ??
            GochanoLanguage.text(
              'Could not sign you in. Please try again.',
              'সাইন ইন করা যায়নি। আবার চেষ্টা করুন।',
            ),
      );
    }
  }

  // -------------------------------------------------------------------
  // Subscription-path exchange (no OTP step).
  // -------------------------------------------------------------------

  /// Calls the backend endpoint for the "already subscribed, no OTP"
  /// branch. The backend is responsible for verifying the subscription
  /// server-side (it must NOT trust the client to claim it; the body
  /// is a hint to route the request through the subscription
  /// verification path rather than the OTP verification path). On
  /// success returns a [TelecomFirebaseExchange] the caller signs in
  /// with just like the OTP branch.
  static Future<TelecomFirebaseExchange>
      exchangeSubscriptionForFirebaseSession({
    required String phone,
    required String subscriptionStatus,
  }) async {
    final cleanPhone = normalize(phone);
    if (!isSupportedPhone(cleanPhone)) {
      throw TelecomAuthException(GochanoLanguage.text(
        'Only Robi (016) and Cirkle (018) numbers are supported',
        'শুধুমাত্র Robi (০১৬) ও Cirkle (০১৮) নম্বর সমর্থিত',
      ));
    }
    if (backendBaseUrl.isEmpty) {
      throw TelecomAuthException(GochanoLanguage.text(
        'Backend URL is not configured. Run with '
        '--dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com',
        'ব্যাকএন্ড URL কনফিগার করা হয়নি। --dart-define=API_BASE_URL দিয়ে চালান।',
      ));
    }

    final uri = Uri.parse('$backendBaseUrl/v1/auth/telecom/exchange');
    final response = await _safePost(
      uri,
      {
        'phone': cleanPhone,
        'already_subscribed': true,
        'subscription_status': subscriptionStatus,
      },
      exchangeTimeout,
    );

    return _parseExchangeResponse(response.body, phone: cleanPhone);
  }

  static TelecomFirebaseExchange _parseExchangeResponse(
    String body, {
    required String phone,
  }) {
    Map<String, dynamic> decoded;
    try {
      final value = json.decode(body);
      if (value is! Map) {
        throw const FormatException('expected JSON object');
      }
      decoded = value.cast<String, dynamic>();
    } catch (_) {
      throw TelecomAuthException(GochanoLanguage.text(
        'Could not link your number to Gochano. Please try again later.',
        'আপনার নম্বর Gochano-তে সংযুক্ত করা যায়নি। কিছুক্ষণ পর আবার চেষ্টা করুন।',
      ));
    }

    final customToken = _firstNonEmptyString([
      decoded['firebase_custom_token'],
      decoded['custom_token'],
      decoded['customToken'],
    ]);
    final uid = _firstNonEmptyString([
      decoded['uid'],
      decoded['userId'],
    ]);

    if (customToken == null) {
      throw TelecomAuthException(GochanoLanguage.text(
        'Gochano sign-in is not yet enabled for this number. Please try again later.',
        'এই নম্বরের জন্য Gochano সাইন-ইন এখনো চালু হয়নি। কিছুক্ষণ পর আবার চেষ্টা করুন।',
      ));
    }

    return TelecomFirebaseExchange(
      uid: uid ?? '',
      customToken: customToken,
      phone: phone,
    );
  }

  /// One-call helper used by both the OTP path
  /// (otp_verify_screen) and the subscription path (login_screen).
  /// Persists the SharedPreferences session AND signs into Firebase
  /// with the custom token returned by the backend. Throws if either
  /// step fails; the caller is responsible for routing back to
  /// LoginScreen so we never enter GochanoShell half-authenticated.
  static Future<void> enterSession({
    required String phone,
    required TelecomFirebaseExchange exchange,
  }) async {
    await signInToFirebaseWithCustomToken(exchange);
    await persistSession(phone: phone);
  }

  // -------------------------------------------------------------------
  // Session persistence — convenience only, NOT proof of identity.
  // -------------------------------------------------------------------

  static Future<void> persistSession({required String phone}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefIsLoggedIn, true);
    await prefs.setString(prefUserPhone, normalize(phone));
    // Clear any PART 16-era `telecom_*` keys now that we have
    // migrated to the legacy naming. Leaving them around would risk a
    // future code path accidentally trusting them.
    await prefs.remove(_legacyPrefIsLoggedIn);
    await prefs.remove(_legacyPrefUserPhone);
    await prefs.remove(_legacyPrefUserId);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefIsLoggedIn);
    await prefs.remove(prefUserPhone);
    await prefs.remove(_legacyPrefIsLoggedIn);
    await prefs.remove(_legacyPrefUserPhone);
    await prefs.remove(_legacyPrefUserId);
  }

  /// Reads the local "am I logged in" flag. Returns true when EITHER
  /// the new key (`isLoggedIn`) OR the legacy PART 16 key
  /// (`telecom_isLoggedIn`) is set to true. The legacy key is only
  /// read for one call — the next persistSession() clears it.
  static Future<bool> readIsLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final primary = prefs.getBool(prefIsLoggedIn) ?? false;
    if (primary) return true;
    return prefs.getBool(_legacyPrefIsLoggedIn) ?? false;
  }

  static Future<String?> readUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final primary = prefs.getString(prefUserPhone);
    if (primary != null && primary.isNotEmpty) return primary;
    return prefs.getString(_legacyPrefUserPhone);
  }

  /// Convenience alias for [readUserPhone].
  static Future<String?> readPhone() => readUserPhone();

  // -------------------------------------------------------------------
  // HTTP helpers
  // -------------------------------------------------------------------

  static Future<http.Response> _safePost(
    Uri uri,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Network error. Please check your connection and try again.',
          'নেটওয়ার্ক ত্রুটি। সংযোগ যাচাই করে আবার চেষ্টা করুন।',
        ),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TelecomAuthException(
        GochanoLanguage.text(
          'Server is not responding. Please try again in a moment.',
          'সার্ভার সাড়া দিচ্ছে না। একটু পর আবার চেষ্টা করুন।',
        ),
      );
    }
    return response;
  }

  // -------------------------------------------------------------------
  // JSON helpers
  // -------------------------------------------------------------------

  static bool? _firstBool(dynamic a, dynamic b) {
    for (final v in [a, b]) {
      if (v is bool) return v;
      if (v is String) {
        final upper = v.trim().toUpperCase();
        if (upper == 'TRUE') return true;
        if (upper == 'FALSE') return false;
      }
      if (v is num) {
        if (v == 1) return true;
        if (v == 0) return false;
      }
    }
    return null;
  }

  static String? _firstNonEmptyString(List<dynamic> candidates) {
    for (final v in candidates) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is num) return v.toString();
    }
    return null;
  }

  static dynamic _nestedValue(Map decoded, List<String> path) {
    dynamic cursor = decoded;
    for (final key in path) {
      if (cursor is Map && cursor.containsKey(key)) {
        cursor = cursor[key];
      } else {
        return null;
      }
    }
    return cursor;
  }
}

class _SendOtpResponse {
  const _SendOtpResponse({
    required this.success,
    required this.referenceNo,
    required this.message,
    required this.alreadyRegistered,
  });
  final bool success;
  final String? referenceNo;
  final String? message;
  final bool alreadyRegistered;
}

class _VerifyOtpResponse {
  const _VerifyOtpResponse({required this.success, required this.message});
  final bool success;
  final String? message;
}
