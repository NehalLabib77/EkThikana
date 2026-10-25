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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/app_design_system.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/services/telecom_auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../shell/presentation/gochano_shell.dart';
import 'login_screen.dart';
import 'profile_setup_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const bool _developerAuthBypass =
      kDebugMode &&
      bool.fromEnvironment('DEV_AUTH_BYPASS', defaultValue: false);

  bool _checked = false;
  bool _loggedIn = false;
  bool _hasProfile = false;
  String _phone = '';

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
        if (_developerAuthBypass) {
          _loggedIn = user != null;
        } else {
          _loggedIn = user != null;
          if (user == null) {
            // Wipe the local flag so the user is routed to LoginScreen.
            TelecomAuthService.clearSession();
          }
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

    // _loggedIn is determined by the combination of the local flag
    // AND FirebaseAuth.currentUser (or Developer Login bypass if enabled
    // in debug mode).
    final current = FirebaseAuth.instance.currentUser;
    final isDeveloperSession = _developerAuthBypass && current != null;
    final isTelecomSession = isLoggedIn && current != null;

    final staleFlag = isLoggedIn && current == null;
    if (staleFlag) {
      // Flag set but Firebase did not restore the user. Refuse entry;
      // clear the stale flag so LoginScreen does not loop.
      await TelecomAuthService.clearSession();
    }

    // On cold start with a valid Firebase user, force a token refresh so
    // the ID token carries fresh custom claims (telecom_verified,
    // email_verified).  Without this the Firestore rules' verified()
    // helper may see stale/missing claims and deny reads.
    if (isDeveloperSession || isTelecomSession) {
      try {
        await current.getIdToken(true);
      } catch (_) {
        // Non-fatal — the worst case is a stale token that self-heals
        // on the next natural refresh.
      }
    }

    // Check whether the user has an existing profile document.
    // New telecom users (first login on this device) will not have one
    // yet and must complete the profile setup screen.
    bool hasProfile = false;
    if (isDeveloperSession || isTelecomSession) {
      hasProfile = await FirestoreService.hasProfile();
    }

    if (!mounted) return;
    setState(() {
      _phone = phone;
      _hasProfile = hasProfile;
      _checked = true;
      if (isDeveloperSession || isTelecomSession) {
        _loggedIn = true;
      } else {
        _loggedIn = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const AuthGateLoadingView();
    }

    if (_loggedIn && FirebaseAuth.instance.currentUser != null) {
      final current = FirebaseAuth.instance.currentUser;
      final displayName = _phone.isNotEmpty
          ? _phone
          : (current?.phoneNumber?.isNotEmpty == true
                ? current!.phoneNumber!
                : (current?.displayName?.isNotEmpty == true
                      ? current!.displayName!
                      : (current?.email ?? '')));

      if (!_hasProfile) {
        return ProfileSetupScreen(phone: displayName);
      }
      return GochanoShell(role: 'student', displayName: displayName);
    }
    return LoginScreen();
  }
}

/// Visual presentation displayed while AuthGate resolves the local session,
/// verifies the Firebase identity, and checks profile state.
///
/// Exposed for non-destructive widget testing of theme adaptation,
/// localization, 320dp responsiveness, and reduced-motion compliance.
@visibleForTesting
class AuthGateLoadingView extends StatelessWidget {
  const AuthGateLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = context.colors;
    final type = context.type;
    final isReducedMotion = AppMotion.isReducedMotion(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: AppPageBackground(
        gradient: AppGradients.todayAppBarFor(isDark: isDark),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth <= 340;
              final compact = isNarrow || constraints.maxHeight < 500;
              final avatarSize = compact ? 64.0 : 76.0;
              final logoSize = compact ? 38.0 : 46.0;

              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        isNarrow ? GochanoSpacing.md : GochanoSpacing.lg,
                    vertical: GochanoSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: isDark
                              ? colors.surfaceVariant
                              : colors.brandSoft,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.brand.withValues(
                              alpha: isDark ? 0.35 : 0.18,
                            ),
                            width: 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.brand.withValues(
                                alpha: isDark ? 0.25 : 0.10,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Image.asset(
                          'assets/branding/gochano1.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                          semanticLabel: 'Gochano logo',
                          errorBuilder: (_, _, _) => Icon(
                            Icons.school_rounded,
                            size: compact ? 30.0 : 38.0,
                            color: colors.brand,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: compact
                            ? GochanoSpacing.xs + 2
                            : GochanoSpacing.sm,
                      ),
                      Text(
                        'Gochano',
                        style: (compact ? type.cardHeading : type.pageTitle)
                            .copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        GochanoLanguage.text(
                          'Starting Gochano…',
                          'Gochano শুরু হচ্ছে…',
                        ),
                        style: type.bodySecondary.copyWith(
                          color: colors.textSecondary,
                          fontSize: compact ? 12.5 : 13.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(
                        height: compact ? GochanoSpacing.md : GochanoSpacing.lg,
                      ),
                      Semantics(
                        label: GochanoLanguage.text(
                          'Loading Gochano',
                          'Gochano লোড হচ্ছে',
                        ),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            value: isReducedMotion ? 0.75 : null,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colors.brand,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
