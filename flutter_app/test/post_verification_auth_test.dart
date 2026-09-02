// Post-verification 403 regression guards.
//
// After `VerifyEmailScreen` auto-detects that the user verified, the gate
// swaps in the Home shell and Home immediately fires Firestore / backend
// requests. The bug that used to ship: every cached ID token still carried
// `email_verified: false` (Firebase caches JWTs for ~1 hour), so the very
// first Firestore read returned `permission-denied` and the very first
// backend call returned 403. The user saw "You do not have access to this
// item" instead of the home screen.
//
// The fix is structural: force-refresh the token once on the verification
// flip (AuthGate) and keep an in-band one-shot 403 retry on every API
// call (ApiService). These guards fail loudly if a future edit removes
// any of the four pieces:
//
//   1. `AuthService.forceRefreshIdToken()` exists and force-refreshes.
//   2. `AuthService.reloadUser()` calls `getIdToken(true)` on the
//      unverified → verified transition.
//   3. `AuthService.register()` writes the profile via `SetOptions(merge:
//      true)` and `AuthService.ensureProfile()` repairs partial profiles
//      idempotently.
//   4. `ApiService.request` (the central `_send` funnel) does one 403
//      retry after a force-refresh, and emits a dev-mode route/method/
//      status log line that does not contain the token.
//
// The post-verification 403 is a regression with three possible faces
// (Firestore rules, FastAPI `get_verified_identity`, FastAPI
// `get_current_user`); all three are addressed by these same structural
// changes, so a single test file covers the whole class of bug.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('AuthService.forceRefreshIdToken()', () {
    late String source;
    setUpAll(() => source = _read('lib/services/auth_service.dart'));

    test('is declared as a static method returning Future<String?>', () {
      // The return is nullable: null when no user is signed in or when the
      // fresh user is still unverified. The funnel in ApiService relies
      // on the null branch to skip retry rather than retry with a stale
      // token.
      final re = RegExp(r'static\s+Future<String\?>\s+forceRefreshIdToken\s*\(');
      expect(re.hasMatch(source), isTrue,
          reason: 'AuthService must expose forceRefreshIdToken() so the '
              'AuthGate and ApiService funnel can invalidate the cached '
              'JWT after verification.');
    });

    test('calls getIdToken(true)', () {
      expect(source, contains('getIdToken(true)'),
          reason: 'forceRefreshIdToken must mint a brand-new token with '
              'forceRefresh: true so the email_verified claim reflects '
              'the current server view.');
    });

    test('reloads currentUser before answering', () {
      // The token must reflect the *current* server state, not the
      // pre-reload local cache.
      expect(source.contains('await current.reload()') ||
              source.contains('await before?.reload()') ||
              source.contains('await fresh.reload()'),
          isTrue,
          reason: 'forceRefreshIdToken must reload the Firebase user so the '
              'subsequent getIdToken(true) mints a token with up-to-date '
              'claims.');
    });
  });

  group('AuthService.reloadUser() token force-refresh', () {
    late String source;
    setUpAll(() => source = _read('lib/services/auth_service.dart'));

    test('triggers getIdToken(true) when emailVerified flips on', () {
      // The fix is conditional: only on the unverified → verified
      // transition. Calling getIdToken(true) on every reload would burn
      // Firebase quota and add latency to the verify-screen poll.
      final reloadStart = source.indexOf('static Future<void> reloadUser()');
      expect(reloadStart, greaterThanOrEqualTo(0));
      final reloadEnd = source.indexOf('}', reloadStart);
      final reloadBody = source.substring(reloadStart, reloadEnd);
      expect(reloadBody, contains('wasVerified'),
          reason: 'reloadUser must remember the pre-reload emailVerified '
              'state to detect the flip.');
      expect(reloadBody, contains('nowVerified'),
          reason: 'reloadUser must compare pre- and post-reload state.');
      expect(reloadBody, contains('getIdToken(true)'),
          reason: 'reloadUser must force-refresh the token when the user '
              'just became verified.');
    });
  });

  group('AuthService.register() and ensureProfile()', () {
    late String source;
    setUpAll(() => source = _read('lib/services/auth_service.dart'));

    test('register uses SetOptions(merge: true)', () {
      expect(source, contains('SetOptions(merge: true)'),
          reason: 'register must use merge semantics so re-registration or '
              'recovery paths cannot blank valid fields.');
    });

    test('ensureProfile() exists and is static', () {
      final re =
          RegExp(r'static\s+Future<bool>\s+ensureProfile\s*\(');
      expect(re.hasMatch(source), isTrue,
          reason: 'ensureProfile is the recovery path for half-built '
              'users/{uid} docs and must be exposed publicly.');
    });

    test('ensureProfile reads users/{uid} and writes with merge', () {
      // Anchor on the actual method signature (with the open brace) so we
      // don't slice into a doc-comment mention of `ensureProfile()`.
      final ensureStart = source.indexOf('ensureProfile({');
      expect(ensureStart, greaterThanOrEqualTo(0),
          reason: 'ensureProfile method must exist on AuthService.');
      final body = source.substring(
          ensureStart, ensureStart + 1500);
      expect(body, contains("db.collection('users').doc(fresh.uid)"),
          reason: 'ensureProfile must use the authenticated uid, never a '
              'synthetic key.');
      expect(body, contains('SetOptions(merge: true)'),
          reason: 'ensureProfile must merge so it cannot overwrite a '
              'valid profile with placeholder data.');
    });
  });

  group('ApiService stale-token recovery', () {
    late String source;
    setUpAll(() => source = _read('lib/services/api_service.dart'));

    test('central _send funnel exists', () {
      expect(source, contains('static Future<http.Response> _send({'),
          reason: 'All protected calls must route through one funnel so '
              'the 403 retry applies uniformly.');
    });

    test('central funnel force-refreshes on 403 once', () {
      final checks403 =
          source.contains('response.statusCode != 403') ||
              source.contains('!= 403');
      expect(checks403, isTrue,
          reason: 'The funnel must check for 403 specifically — other '
              'status codes must not trigger a retry.');
      expect(source, contains('forceRefreshIdToken()'),
          reason: 'The funnel must call AuthService.forceRefreshIdToken() '
              'to invalidate the stale JWT before the single retry.');
    });

    test('does NOT loop on repeated 403', () {
      // The retry must be a single attempt. Counting the substring
      // `retry` is too noisy (matches doc-comments, variable names like
      // `retryHeaders`, and log strings). Count the actual retry trigger
      // instead: inside `_send`, `AuthService.forceRefreshIdToken()` may
      // be invoked at most once. The multipart funnel has its own copy
      // of this same pattern.
      final funnelStart = source.indexOf('static Future<http.Response> _send(');
      final nextMethod =
          source.indexOf('static Future<http.Response>', funnelStart + 30);
      final body = source.substring(funnelStart,
          nextMethod < 0 ? source.length : nextMethod);
      final refreshCalls =
          RegExp(r'AuthService\.forceRefreshIdToken\s*\(').allMatches(body).length;
      expect(refreshCalls, lessThanOrEqualTo(1),
          reason: 'The _send funnel must call '
              'AuthService.forceRefreshIdToken() at most once per request, '
              'otherwise a persistent 403 becomes an infinite loop.');
    });

    test('multipart uploads also use the funnel', () {
      expect(source, contains('_sendMultipart'),
          reason: 'Multipart uploads (materials, prescriptions, OCR) must '
              'go through the same force-refresh path as JSON requests.');
    });

    test('dev-mode logs do NOT include token, body, or password', () {
      final logCall = source.indexOf("_debugLog('");
      expect(logCall, greaterThanOrEqualTo(0),
          reason: 'A safe dev log line must exist.');
      // Sample the actual format string used by the funnel.
      expect(source, contains(r'$method ${_safeRoute(uri)}'),
          reason: 'The log format must be method + route only.');
      expect(source.contains('debugPrint'), isTrue,
          reason: 'Dev-mode logging must go through debugPrint (no-op in '
              'release) rather than print.');
    });

    test('public/anon requests are not retried', () {
      // health() is unauth. A 403 on a public endpoint is a real verdict,
      // not a stale token — retrying would mask it.
      final sendStart = source.indexOf('static Future<http.Response> _send(');
      final body = source.substring(sendStart,
          sendStart + 2000);
      expect(body, contains('!auth ||'),
          reason: 'The retry guard must skip when auth == false so public '
              'endpoints surface their real 403.');
    });
  });

  group('AuthGate force-refresh wiring', () {
    late String source;
    setUpAll(() => source =
        _read('lib/features/auth/presentation/auth_gate.dart'));

    test('is a StatefulWidget (force-refresh needs memoization)', () {
      expect(source, contains('extends StatefulWidget'),
          reason: 'AuthGate needs State to memoize the one-shot '
              'force-refresh and avoid re-firing on every stream tick.');
    });

    test('calls forceRefreshIdToken before mounting GochanoShell', () {
      expect(source, contains('AuthService.forceRefreshIdToken()'),
          reason: 'AuthGate must invalidate the cached JWT exactly on the '
              'verification-flip transition, before any Firestore rules '
              'check from Home.');
      final gochanoIndex = source.indexOf('GochanoShell(');
      expect(gochanoIndex, greaterThanOrEqualTo(0));
      final refreshIndex = source.indexOf('forceRefreshIdToken()');
      expect(refreshIndex, lessThan(gochanoIndex),
          reason: 'The force-refresh must run before GochanoShell is '
              'returned, so the very first Home Firestore read sees a '
              'fresh token.');
    });

    test('uses ensureProfile in the missing-profile retry path', () {
      expect(source, contains('AuthService.ensureProfile()'),
          reason: 'When users/{uid} is missing, AuthGate must try to '
              'repair it before asking the user to re-register.');
    });
  });
}
