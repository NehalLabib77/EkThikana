// AuthService — the only place that talks to FirebaseAuth + Firestore's
// `users/` collection. Everything Firebase-related (sign-in, register,
// reload, logout, password reset) and every Firebase user-metadata read
// the UI cares about (the authoritative `emailVerified`) routes through
// here, so the screens can stay declarative.
//
// Four invariants the rest of the app depends on:
//
//   1. After `reloadUser()`, callers must read `FirebaseAuth
//      .instance.currentUser` **again** rather than trust the `User`
//      object they had before the reload. The pre-reload object keeps
//      the old `emailVerified` value even after a successful verification
//      link click — the bug that used to leave the verify screen stuck.
//
//   2. `reloadUser()` (and any login/register path) emits a tick on the
//      refresh notifier. `AuthGate` listens to that notifier
//      *together with* `authStateChanges()` because Firebase does not
//      emit an `authStateChanges` event when `emailVerified` flips on
//      its own. Without the notifier the gate cannot tell that the user
//      just became verified.
//
//   3. Authentication is always governed by `FirebaseAuth.currentUser
//      .emailVerified`, never by a Firestore flag. A missing or
//      incomplete Firestore profile is a separate, explainable error —
//      not a stand-in for "email not verified".
//
//   4. The cached Firebase ID token must be invalidated once `emailVerified`
//      flips true. `firebase_auth`'s `getIdToken()` returns a token whose
//      `email_verified` claim reflects the server's view at sign-in time,
//      and that token is cached for up to an hour. After the user clicks
//      the verification link, every cached token still carries
//      `email_verified: false`, so both `firestore.rules` and the FastAPI
//      `get_verified_identity` dependency reject requests with 403 — even
//      though Firebase's *current* user says `emailVerified = true`. The
//      fix is `getIdToken(forceRefresh: true)` once verification flips,
//      and `ensureProfile()` to repair any half-built `users/{uid}` doc
//      that would also trigger a 403 on `get_current_user`.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  AuthService._();

  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore db = FirebaseFirestore.instance;

  /// Emits every time something auth-relevant happened that the gate
  /// should re-evaluate. See invariant 2 above for why this exists.
  ///
  /// `AuthService.refreshes()` is merged with `authStateChanges()`
  /// inside `AuthGate`. Anything that calls `reloadUser()` (login,
  /// register, manual check, lifecycle resume) also pings it.
  ///
  /// `late` so tests can replace it with a fresh controller between
  /// cases via [debugResetRefreshes].
  // ignore: unnecessary_late
  static late StreamController<void> _refreshesController =
      StreamController<void>.broadcast();

  /// Whether the cached email is verified. Refreshes the underlying
  /// Firebase user before answering.
  ///
  /// Returns false if no user is signed in, if the reload failed, or if
  /// the freshly-read user is still unverified. Never throws.
  static Future<bool> isEmailVerified({bool reload = true}) async {
    final current = auth.currentUser;
    if (current == null) return false;
    try {
      if (reload) await current.reload();
    } catch (_) {
      return false;
    }
    return auth.currentUser?.emailVerified ?? false;
  }

  /// Latest known `User` (refreshed). Returns null when signed out or
  /// when a reload fails. Never throws.
  static Future<User?> refreshedUser() async {
    final current = auth.currentUser;
    if (current == null) return null;
    try {
      await current.reload();
    } catch (_) {
      return current;
    }
    return auth.currentUser;
  }

  /// Stream of `User?` whose every event comes from one of:
  ///   * `auth.authStateChanges()` (sign-in / sign-out / token refresh), or
  ///   * the internal refresh notifier (a manual `reloadUser()`).
  ///
  /// Both paths funnel through this generator so `AuthGate` can listen
  /// to a single stream without re-implementing the merge. The event
  /// value is **the freshly-read `FirebaseAuth.instance.currentUser`**,
  /// never the value captured before the trigger.
  static Stream<User?> authState() async* {
    final refreshStream = _refreshesController.stream;
    final authStream = debugAuthStream ?? auth.authStateChanges();
    final bridge = StreamController<User?>();

    // Wire each upstream into the same bridge.
    final refreshSub = refreshStream.listen((_) {
      bridge.add(auth.currentUser);
    });
    final authSub = authStream.listen(
      bridge.add,
      onError: (Object e, StackTrace s) => bridge.addError(e, s),
    );

    try {
      yield* bridge.stream;
    } finally {
      await refreshSub.cancel();
      await authSub.cancel();
      await bridge.close();
    }
  }

  /// Emits one event on the refresh notifier. Internal callers
  /// (`reloadUser`, `register`, `login`) do this automatically.
  static void _ping() {
    if (!_refreshesController.isClosed) _refreshesController.add(null);
  }

  static Future<void> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String university = '',
    String department = '',
    String semester = '',
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw Exception('Account creation failed.');
    }

    await user.updateDisplayName(name.trim());
    // Merge so re-registration (or any pre-existing partial profile) does
    // not blank out valid fields, and so the write is idempotent on retry.
    await db.collection('users').doc(user.uid).set(
      {
        'displayName': name.trim(),
        'email': email.trim().toLowerCase(),
        'role': role,
        'university': role == 'student' ? university.trim() : '',
        'department': role == 'student' ? department.trim() : '',
        'semester': role == 'student' ? semester.trim() : '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await user.sendEmailVerification();
    _ping();
  }

  /// Signs the user in and returns a [LoginResult] carrying the
  /// *fresh* verification status, not the snapshot baked into the
  /// credential.
  ///
  /// Why the indirection: `credential.user.emailVerified` reads from the
  /// `UserInfo` baked into the sign-in response, which predates any
  /// verification link click that may have just happened on the device.
  /// The flow that used to fail — "I verified, then signed back in, and
  /// the gate still says unverified" — was driven by trusting that
  /// field. We reload and re-read.
  static Future<LoginResult> login(String email, String password) async {
    final credential = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      try {
        await user.reload();
      } catch (_) {
        // Treat a failed reload as "still unverified" so the gate does
        // the safe thing; the verify screen can retry the reload.
      }
    }

    final fresh = auth.currentUser;
    final verified = fresh?.emailVerified ?? false;
    if (fresh != null && !verified) {
      try {
        await fresh.sendEmailVerification();
      } catch (_) {/* the verify screen resends on demand */}
    }

    // Repair a missing or partial `users/{uid}` profile so the next backend
    // call (which goes through `get_current_user`) does not 403 with
    // "User profile is missing". No-op when the doc is already complete.
    if (fresh != null) {
      await ensureProfile();
    }

    _ping();
    return LoginResult(user: fresh, isVerified: verified);
  }

  static Future<void> reloadUser() async {
    final before = auth.currentUser;
    final wasVerified = before?.emailVerified ?? false;
    await before?.reload();
    final after = auth.currentUser;
    final nowVerified = after?.emailVerified ?? false;
    // If verification just flipped on, force-refresh the cached ID token so
    // the very next request — and any Firestore rule check — sees
    // `email_verified: true`. A non-fatal failure here is fine: the gate
    // still re-evaluates and the next API call / `forceRefreshIdToken()`
    // retry will swap the token.
    if (!wasVerified && nowVerified) {
      try {
        await after!.getIdToken(true);
      } catch (e) {
        _debugLog('reloadUser: token force-refresh failed (non-fatal): $e');
      }
    }
    _ping();
  }

  /// Force-refresh the cached Firebase ID token so its claims match the
  /// server's current view of `email_verified`.
  ///
  /// Returns the fresh token string, or null when:
  ///   * no user is signed in,
  ///   * the fresh `currentUser.emailVerified` is still false (so a
  ///     forced refresh would just mint the same stale claim),
  ///   * Firebase rejected the call.
  ///
  /// Callers that consume the token directly (`ApiService._token()`'s
  /// one-shot retry path) get the string back; the verify-screen and
  /// AuthGate only need the side effect of Firebase's internal cache
  /// being updated, which `getIdToken(true)` performs either way.
  static Future<String?> forceRefreshIdToken() async {
    final current = auth.currentUser;
    if (current == null) return null;
    try {
      await current.reload();
    } catch (e) {
      _debugLog('forceRefreshIdToken: reload failed: $e');
      return null;
    }
    final fresh = auth.currentUser;
    if (fresh == null || !fresh.emailVerified) return null;
    try {
      final token = await fresh.getIdToken(true);
      _debugLog('forceRefreshIdToken: token refreshed '
          '(uid=${fresh.uid}, verified=${fresh.emailVerified})');
      _ping();
      return token;
    } catch (e) {
      _debugLog('forceRefreshIdToken: getIdToken(true) failed: $e');
      return null;
    }
  }

  /// Repairs a half-built or missing `users/{uid}` profile.
  ///
  /// `register()` creates the doc, but if the Firestore write fails after
  /// `createUserWithEmailAndPassword` succeeds — flaky network, denied
  /// rules, partial deploy — the user ends up signed in with no profile.
  /// Backend `get_current_user` then 403s with "User profile is missing".
  /// This method reads the doc, fills in only the missing fields from the
  /// authoritative Firebase user metadata, and never overwrites an
  /// existing non-empty value. Idempotent; safe to call from `login()`.
  static Future<bool> ensureProfile({
    String role = 'general',
    String displayName = '',
  }) async {
    final fresh = auth.currentUser;
    if (fresh == null) return false;
    try {
      final ref = db.collection('users').doc(fresh.uid);
      final snap = await ref.get();
      final existing = snap.data() ?? <String, dynamic>{};
      final patch = <String, dynamic>{
        'email': (existing['email'] as String?) ??
            (fresh.email ?? '').toLowerCase(),
        'displayName': _firstNonEmpty(
          existing['displayName']?.toString(),
          fresh.displayName,
          displayName,
        ),
        'role': _firstNonEmpty(existing['role']?.toString(), role),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existing.containsKey('createdAt')) {
        patch['createdAt'] = FieldValue.serverTimestamp();
      }
      await ref.set(patch, SetOptions(merge: true));
      _ping();
      return true;
    } catch (e) {
      _debugLog('ensureProfile: failed (uid=${fresh.uid}): $e');
      return false;
    }
  }

  static String _firstNonEmpty(String? a, String? b, [String? c]) {
    for (final v in [a, b, c]) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  static void _debugLog(String message) {
    if (kReleaseMode) return;
    // Never log token, password, or full user objects. Free-form strings only.
    debugPrint('[AuthService] $message');
  }

  /// Resends the verification email with a built-in cooldown so the
  /// "Send again" button cannot be hammered.
  ///
  /// Returns 0 when the send happened, or the seconds remaining on the
  /// cooldown when it did not. Default cooldown: 45 seconds — short
  /// enough that an impatient user is not blocked, long enough that a
  /// misbehaving loop cannot spam Firebase.
  static Future<int> resendVerification({
    Duration cooldown = const Duration(seconds: 45),
  }) async {
    final user = auth.currentUser;
    if (user == null) return cooldown.inSeconds;
    final last = _lastResendAt[user.uid];
    final now = DateTime.now();
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < cooldown) {
        return (cooldown - elapsed).inSeconds.clamp(0, cooldown.inSeconds);
      }
    }
    await user.sendEmailVerification();
    _lastResendAt[user.uid] = now;
    _ping();
    return 0;
  }

  static Future<void> logout() async {
    _lastResendAt.clear();
    await auth.signOut();
    _ping();
  }

  static Future<void> sendPasswordReset(String email) {
    return auth.sendPasswordResetEmail(email: email.trim());
  }

  // Per-uid cooldown bookkeeping. Cleared on logout.
  static final Map<String, DateTime> _lastResendAt = <String, DateTime>{};

  // -- Debug seams --------------------------------------------------------
  //
  // These let tests drive AuthGate without booting a real Firebase SDK.
  // They are intentionally static and debug-only — production callers
  // must not touch them.

  /// Optional override for `auth.authStateChanges()`. When null, the
  /// real Firebase stream is used; when set, tests can drive `AuthGate`
  /// by pushing `User?` values into the supplied stream.
  static Stream<User?>? debugAuthStream;

  /// Resets the refresh notifier. Tests call this between cases so each
  /// case gets a freshly-listened controller.
  static void debugResetRefreshes() {
    if (!_refreshesController.isClosed) _refreshesController.close();
    _refreshesController = StreamController<void>.broadcast();
    _lastResendAt.clear();
  }

  /// Emits a tick on the refresh notifier from outside the service.
  /// Used by tests that want to simulate a Firebase reload.
  static void debugPingRefresh() => _ping();
}

/// Outcome of [AuthService.login]. Returned instead of being encoded in
/// an exception so callers can branch cleanly.
class LoginResult {
  const LoginResult({required this.user, required this.isVerified});

  /// The fresh `User` (post-reload), or null when sign-in failed.
  final User? user;

  /// `user.emailVerified` read after `currentUser.reload()`.
  final bool isVerified;
}
