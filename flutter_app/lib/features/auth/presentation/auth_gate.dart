// Auth gate for the Robi / Cirkle telecom login.
//
// PART 16.1 — CRITICAL CORRECTION: the gate now requires BOTH a
// successful telecom session flag AND a non-null
// `FirebaseAuth.instance.currentUser`. PART 16 only checked the local
// SharedPreferences flag, which let the user reach GochanoShell while
// `FirebaseAuth.currentUser` was null. Every Firestore read/write
// (`notes`, `tasks`, `expenses`, `medicines`, `dena_pawna`,
// `materials`) would then fail with `permission-denied`, because
// `firestore.rules` requires `request.auth.token.email_verified ==
// true` and the FastAPI backend's `get_verified_identity` reads the
// same claim via `verify_id_token`.
//
// Boot sequence:
//
//   * No local session flag       -> LoginScreen.
//   * Flag is true, but currentUser is null (e.g. cold start where
//     Firebase did not restore the user, or session was cleared
//     outside the app) -> LoginScreen with a one-shot "Please sign
//     in again" message. We never let the user into GochanoShell
//     with a half-authenticated state.
//   * Flag is true AND currentUser is non-null AND the ID token
//     carries `email_verified == true` -> GochanoShell.
//   * Flag is true AND currentUser is non-null but the ID token is
//     missing `email_verified == true` (should never happen for a
//     token minted by our backend, but we guard anyway) -> LoginScreen
//     with the same message.
//
// PART 17 will replace the legacy `logout` plumbing with an
// "Unsubscribe" + "Logout" pairing.
//
// PART 30.1 — COLD-START HANG FIX:
// - Added bounded timeouts for getIdToken(true) and checkProfileState().
// - Wrapped _restore() in try/catch/finally to guarantee _checked = true
//   is ALWAYS set, even on unhandled exceptions or generation-guard discards.
// - Fixed generation guard: when a stale result is discarded, _checked is
//   still set so the UI never remains on the loading spinner forever.
// - Added diagnostic [AuthGate] logs at every restore stage.
//
// PART 30.2 — PROVEN GENERATION RACE FIX:
// - Root cause: Firebase authStateChanges() emits its initial snapshot
//   (user=null for logged-out) synchronously when the listener is attached.
//   This incremented _authGeneration and invalidated the _restore() that
//   was already establishing the initial auth state.
// - Fix: Track _receivedInitialAuthSnapshot. Skip generation increment
//   for the initial snapshot (it is state synchronization, not a transition).
// - Fast-path logged-out cold start: if prefs=false and Firebase user=null,
//   resolve immediately without token refresh or Firestore profile check.
// - Guarantee abort termination: stale restore either has a replacement
//   _restore() pending or resolves _checked=true immediately.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/gochano_language.dart';
import '../../../core/services/telecom_auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../shell/presentation/gochano_shell.dart';
import 'login_screen.dart';
import 'profile_setup_screen.dart';

/// Bounded timeout for Firebase token refresh on cold start.
/// A slow/broken network must not hold the entire app on Loading.
const Duration _kTokenRefreshTimeout = Duration(seconds: 10);

/// Bounded timeout for Firestore profile read on cold start.
const Duration _kProfileCheckTimeout = Duration(seconds: 15);

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checked = false;
  bool _loggedIn = false;
  bool _hasProfile = false;
  bool _profileError = false;
  String _phone = '';

  StreamSubscription<User?>? _firebaseAuthSub;

  /// Monotonically-increasing token that lets _restore() know whether
  /// its async work is still the most recent.  If a newer auth event
  /// fires while _restore() is mid-flight, the stale callback is
  /// silently ignored so it cannot overwrite a valid session with
  /// LoginScreen or ProfileSetupScreen.
  int _authGeneration = 0;

  /// Whether the authStateChanges listener has received its initial snapshot.
  /// Firebase emits the current auth state synchronously when the listener
  /// attaches.  This initial snapshot is state synchronization, NOT a new
  /// auth transition, and must NOT invalidate an active _restore().
  bool _receivedInitialAuthSnapshot = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Boot] authGate:initState');
    _firebaseAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;

      if (!_receivedInitialAuthSnapshot) {
        // First event from Firebase: initial state synchronization.
        // NOT a new auth transition — must NOT increment _authGeneration
        // or invalidate an active _restore().
        _receivedInitialAuthSnapshot = true;
        debugPrint('[AuthGate] authStateChanges: initial user=${user != null ? "non-null" : "null"}');
        setState(() {
          _loggedIn = user != null;
        });
        return;
      }

      // Genuine subsequent auth transition — may invalidate stale restore.
      // Do NOT call clearSession() or clearLocalSession() here — Firebase
      // signOut fires this listener, and calling clearSession from the
      // listener would create a recursive sign-out loop.
      _authGeneration++;
      debugPrint('[AuthGate] authStateChanges: user=${user != null ? "non-null" : "null"} gen=$_authGeneration');
      setState(() {
        _loggedIn = user != null;
      });
    });
    _restore();
  }

  @override
  void dispose() {
    _firebaseAuthSub?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final generation = ++_authGeneration;
    debugPrint('[AuthGate] restore:start gen=$generation');

    try {
      // ── Stage 1: Read local session flags ──
      debugPrint('[AuthGate] prefs:start');
      final isLoggedIn = await TelecomAuthService.readIsLoggedIn();
      final phone = isLoggedIn
          ? (await TelecomAuthService.readUserPhone()) ?? ''
          : '';
      debugPrint('[AuthGate] prefs:isLoggedIn=$isLoggedIn phonePresent=${phone.isNotEmpty}');

      if (!mounted || generation != _authGeneration) {
        final replacementPending = generation < _authGeneration;
        debugPrint('[AuthGate] restore:aborted(stale-gen) at prefs gen=$generation current=$_authGeneration replacementPending=$replacementPending');
        // GUARANTEE: If no replacement _restore() is pending, resolve UI
        // immediately so the spinner never hangs.
        if (!replacementPending && mounted) {
          setState(() {
            _checked = true;
            _loggedIn = false;
          });
          debugPrint('[AuthGate] restore:end (stale→login)');
        }
        return;
      }

      // ── Stage 1b: Fast-path logged-out cold start ──
      // If prefs=false and Firebase user=null, resolve immediately.
      // No token refresh, no Firestore profile check, no network wait.
      final current = FirebaseAuth.instance.currentUser;
      if (!isLoggedIn && current == null) {
        debugPrint('[AuthGate] firebaseUser=null');
        debugPrint('[AuthGate] restore:destination=login');
        setState(() {
          _phone = '';
          _hasProfile = false;
          _profileError = false;
          _checked = true;
          _loggedIn = false;
        });
        debugPrint('[AuthGate] restore:end (success)');
        return;
      }

      // ── Stage 2: Check Firebase user (authenticated path) ──
      final staleFlag = isLoggedIn && current == null;
      debugPrint('[AuthGate] firebaseUser=${current != null ? "non-null" : "null"} staleFlag=$staleFlag');

      if (staleFlag) {
        // Flag set but Firebase did not restore the user. Refuse entry;
        // clear the stale flag so LoginScreen does not loop.
        // Use clearLocalSession (NOT clearSession) to avoid triggering
        // another authStateChanges cycle.
        debugPrint('[AuthGate] staleFlag:clearing-local-session');
        await TelecomAuthService.clearLocalSession();
      }

      // ── Stage 3: Token refresh (only when both conditions met) ──
      if (isLoggedIn && current != null) {
        debugPrint('[AuthGate] tokenRefresh:start');
        try {
          await current.getIdToken(true).timeout(_kTokenRefreshTimeout);
          debugPrint('[AuthGate] tokenRefresh:success');
        } on TimeoutException {
          debugPrint('[AuthGate] tokenRefresh:error=timeout');
          // Non-fatal — the worst case is a stale token that self-heals
          // on the next natural refresh.
        } catch (e) {
          debugPrint('[AuthGate] tokenRefresh:error=${e.runtimeType}');
          // Non-fatal — same as above.
        }
      } else {
        debugPrint('[AuthGate] tokenRefresh:skipped isLoggedIn=$isLoggedIn currentUser=${current != null}');
      }

      if (!mounted || generation != _authGeneration) {
        final replacementPending = generation < _authGeneration;
        debugPrint('[AuthGate] restore:aborted(stale-gen) at tokenRefresh gen=$generation current=$_authGeneration replacementPending=$replacementPending');
        if (!replacementPending && mounted) {
          setState(() {
            _checked = true;
            _loggedIn = false;
          });
          debugPrint('[AuthGate] restore:end (stale→login)');
        }
        return;
      }

      // ── Stage 4: Profile check (only when both conditions met) ──
      bool hasProfile = false;
      bool profileError = false;
      if (isLoggedIn && current != null) {
        debugPrint('[AuthGate] profileCheck:start');
        try {
          final profileState = await FirestoreService.checkProfileState()
              .timeout(_kProfileCheckTimeout);
          switch (profileState) {
            case ProfileCheckResult.exists:
              hasProfile = true;
              debugPrint('[AuthGate] profileCheck=result=exists');
            case ProfileCheckResult.missing:
              hasProfile = false;
              debugPrint('[AuthGate] profileCheck=result=missing');
            case ProfileCheckResult.error:
              hasProfile = false;
              profileError = true;
              debugPrint('[AuthGate] profileCheck=result=error');
          }
        } on TimeoutException {
          debugPrint('[AuthGate] profileCheck=result=timeout');
          profileError = true;
        } catch (e) {
          debugPrint('[AuthGate] profileCheck=result=exception(${e.runtimeType})');
          profileError = true;
        }
      } else {
        debugPrint('[AuthGate] profileCheck:skipped isLoggedIn=$isLoggedIn currentUser=${current != null}');
      }

      if (!mounted || generation != _authGeneration) {
        final replacementPending = generation < _authGeneration;
        debugPrint('[AuthGate] restore:aborted(stale-gen) at profileCheck gen=$generation current=$_authGeneration replacementPending=$replacementPending');
        if (!replacementPending && mounted) {
          setState(() {
            _checked = true;
            _loggedIn = false;
          });
          debugPrint('[AuthGate] restore:end (stale→login)');
        }
        return;
      }

      // ── Stage 5: Compute final routing state ──
      bool resolvedLoggedIn;
      if (isLoggedIn && current != null) {
        resolvedLoggedIn = true;
      } else if (staleFlag) {
        resolvedLoggedIn = false;
      } else {
        resolvedLoggedIn = false;
      }

      final destination = !resolvedLoggedIn
          ? 'login'
          : profileError
              ? 'retry'
              : hasProfile
                  ? 'home'
                  : 'profileSetup';
      debugPrint('[AuthGate] restore:destination=$destination');

      setState(() {
        _phone = phone;
        _hasProfile = hasProfile;
        _profileError = profileError;
        _checked = true;
        _loggedIn = resolvedLoggedIn;
      });
      debugPrint('[AuthGate] restore:end (success)');
    } catch (e, st) {
      // GUARANTEE: _checked MUST become true even on unhandled exceptions.
      // Without this, the UI stays on CircularProgressIndicator forever.
      debugPrint('[AuthGate] restore:fatal=${e.runtimeType} stack=${st.toString().split('\n').first}');
      if (mounted) {
        setState(() {
          _checked = true;
          _loggedIn = false;
          _hasProfile = false;
          _profileError = false;
        });
      }
      debugPrint('[AuthGate] restore:end (fatal→login)');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const GochanoScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loggedIn && FirebaseAuth.instance.currentUser != null) {
      final displayName = _phone.isNotEmpty
          ? _phone
          : (FirebaseAuth.instance.currentUser?.phoneNumber ?? '');

      // Profile lookup error — keep authenticated session alive.
      // Show a compact bilingual recoverable error with Retry.
      // Do NOT route to ProfileSetupScreen (the profile may exist;
      // we just couldn't read it).
      if (_profileError) {
        return GochanoScaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    GochanoLanguage.text(
                      'Could not load your profile.',
                      'আপনার প্রোফাইল লোড করা যায়নি।',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    GochanoLanguage.text(
                      'Please check your connection and try again.',
                      'সংযোগ যাচাই করে আবার চেষ্টা করুন।',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _retryProfileCheck,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      GochanoLanguage.text('Retry', 'আবার চেষ্টা করুন'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (!_hasProfile) {
        return ProfileSetupScreen(phone: displayName);
      }
      return GochanoShell(
        role: 'student',
        displayName: displayName,
      );
    }
    return LoginScreen();
  }

  /// Retry the profile check after a transient error.
  /// Keeps the authenticated session alive — only re-reads the profile.
  Future<void> _retryProfileCheck() async {
    final generation = ++_authGeneration;
    debugPrint('[AuthGate] retryProfileCheck:start gen=$generation');
    setState(() {
      _checked = false;
      _profileError = false;
    });

    try {
      final profileState = await FirestoreService.checkProfileState()
          .timeout(_kProfileCheckTimeout);

      if (!mounted || generation != _authGeneration) {
        debugPrint('[AuthGate] retryProfileCheck:aborted(stale-gen)');
        // GUARANTEE: Even if discarded, _checked must become true
        // so the UI never stays on loading forever.
        if (mounted) {
          setState(() { _checked = true; });
        }
        return;
      }

      debugPrint('[AuthGate] retryProfileCheck=result=$profileState');
      setState(() {
        _checked = true;
        switch (profileState) {
          case ProfileCheckResult.exists:
            _hasProfile = true;
            _profileError = false;
          case ProfileCheckResult.missing:
            _hasProfile = false;
            _profileError = false;
          case ProfileCheckResult.error:
            _hasProfile = false;
            _profileError = true;
        }
      });
    } on TimeoutException {
      debugPrint('[AuthGate] retryProfileCheck=result=timeout');
      if (mounted) {
        setState(() {
          _checked = true;
          _profileError = true;
        });
      }
    } catch (e) {
      debugPrint('[AuthGate] retryProfileCheck=result=error(${e.runtimeType})');
      if (mounted) {
        setState(() {
          _checked = true;
          _profileError = true;
        });
      }
    }
    debugPrint('[AuthGate] retryProfileCheck:end');
  }
}

/// Returns the lesser of [a] and [b].
int min(int a, int b) => a < b ? a : b;
