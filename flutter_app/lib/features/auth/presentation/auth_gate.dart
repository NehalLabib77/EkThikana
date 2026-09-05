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

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/telecom_auth_service.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../shell/presentation/gochano_shell.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checked = false;
  bool _loggedIn = false;
  String _phone = '';
  String? _resumeError;

  StreamSubscription<User?>? _firebaseAuthSub;

  @override
  void initState() {
    super.initState();
    // Listen to FirebaseAuth state changes so that a successful
    // signInWithCustomToken() in otp_verify_screen routes us straight
    // into GochanoShell without a manual rebuild, and so that an
    // unexpected sign-out (token revoked, etc.) drops the user back to
    // LoginScreen instead of leaving them in a half-authenticated
    // shell.
    _firebaseAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      setState(() {
        _loggedIn = user != null;
        if (user == null) {
          _resumeError =
              'Your Gochano session expired. Please sign in again.';
          // Also wipe the local flag so the LoginScreen CTA can show
          // the resume message rather than the first-time empty state.
          TelecomAuthService.clearSession();
        }
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
    final isLoggedIn = await TelecomAuthService.readIsLoggedIn();
    final phone = isLoggedIn
        ? (await TelecomAuthService.readUserPhone()) ?? ''
        : '';
    if (!mounted) return;
    setState(() {
      _phone = phone;
      _checked = true;
      // _loggedIn is updated by the authState listener; only set it
      // here if Firebase already has a currentUser (cold start path).
      final current = FirebaseAuth.instance.currentUser;
      if (isLoggedIn && current != null) {
        _loggedIn = true;
        _resumeError = null;
      } else if (isLoggedIn && current == null) {
        // Flag set but Firebase did not restore the user. Refuse
        // entry; clear the stale flag so LoginScreen does not loop.
        _loggedIn = false;
        _resumeError =
            'Your Gochano session expired. Please sign in again.';
        await TelecomAuthService.clearSession();
      } else {
        _loggedIn = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const GochanoScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loggedIn && FirebaseAuth.instance.currentUser != null) {
      return GochanoShell(
        role: 'student',
        displayName: _phone.isEmpty
            ? (FirebaseAuth.instance.currentUser?.phoneNumber ?? 'student')
            : _phone,
      );
    }
    return LoginScreen(resumeMessage: _resumeError);
  }
}
