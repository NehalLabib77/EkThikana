// Decides what a launch shows: sign-in, email verification, or the app.
//
// Three gates in order, each with a real state rather than a spinner that
// might never resolve:
//
//   1. Firebase auth state — signed in at all?
//   2. Email verified? The backend rejects an unverified token, so showing
//      the app would produce 403s on every request.
//   3. Firestore profile — the role the shell needs. `get_current_user`
//      requires this document to exist, so a missing profile is a real,
//      explainable failure, not a blank screen.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/gochano_language.dart';
import '../../../services/auth_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../shell/presentation/gochano_shell.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

/// `StatefulWidget` so the post-verification preparation
/// (token force-refresh + profile repair) can be memoized by uid +
/// verified state. Doing this from a `StatelessWidget`'s `build` would
/// re-fire on every `authState()` tick.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Memoizes the one-shot post-verification preparation.
  ///
  /// Keyed by `${uid}|verified` so a rebuild for the same user does not
  /// re-fire `forceRefreshIdToken()` (which would burn Firebase quota),
  /// and so signing out and back in as a different user does not skip
  /// the preparation.
  final Set<String> _preparedKeys = <String>{};

  /// uids that have already had `ensureProfile()` run successfully.
  /// The method is itself idempotent, but we still gate it to avoid the
  /// extra Firestore round trip on every rebuild.
  final Set<String> _profileRepaired = <String>{};

  /// In-flight profile-repair future, used by the missing-profile branch
  /// to coalesce parallel rebuilds.
  Future<bool>? _profileRepair;

  void _debugLog(String message) {
    if (kReleaseMode) return;
    // Never log token, password, or full user objects.
    debugPrint('[AuthGate] $message');
  }

  /// Run the post-verification preparation exactly once per
  /// (uid, verified) pair. Must run before any Firestore rule check
  /// from Home, hence the `await` before any `GochanoShell` is returned.
  Future<void> _runPrepare(User user) async {
    try {
      // 1. Invalidate the cached JWT so the next request sees
      //    `email_verified: true`.
      await AuthService.forceRefreshIdToken();
      // 2. Repair the users/{uid} doc so the next backend call does
      //    not 403 with "User profile is missing".
      if (!_profileRepaired.contains(user.uid)) {
        final ok = await AuthService.ensureProfile();
        if (ok) _profileRepaired.add(user.uid);
      }
    } catch (e) {
      _debugLog('AuthGate: prepare failed (uid=${user.uid}): $e');
      // Non-fatal: the gate will continue and the user can manually
      // trigger reload from the error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authState(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _Gate(
            child: StaticLoadingState(
              message: GochanoLanguage.text(
                'Signing you in…',
                'সাইন ইন করা হচ্ছে…',
              ),
            ),
          );
        }
        if (authSnapshot.hasError) {
          return _Gate(
            child: ErrorState(
              title: GochanoLanguage.text(
                'Could not reach your account',
                'আপনার অ্যাকাউন্টে পৌঁছানো যায়নি',
              ),
              message: friendlyErrorMessage(authSnapshot.error),
              onRetry: AuthService.reloadUser,
            ),
          );
        }

        final user = authSnapshot.data;
        if (user == null) {
          // Clear memo on sign-out so a different user signing in does
          // not inherit the previous user's "prepared" marker.
          _preparedKeys.clear();
          _profileRepaired.clear();
          _profileRepair = null;
          return const LoginScreen();
        }
        if (!user.emailVerified) return const VerifyEmailScreen();

        // Memoization key for the post-verification preparation.
        final prepKey = '${user.uid}|verified';
        final needsPrepare = !_preparedKeys.contains(prepKey);

        if (needsPrepare) {
          // Mark immediately so any in-flight rebuild that re-enters this
          // branch does not schedule a second preparation.
          _preparedKeys.add(prepKey);
          // Schedule after the current frame so we do not call
          // setState / show a duplicate spinner from inside build().
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await _runPrepare(user);
          });
          return _Gate(
            child: StaticLoadingState(
              message: GochanoLanguage.text(
                'Preparing your session…',
                'আপনার সেশন প্রস্তুত হচ্ছে…',
              ),
            ),
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return _Gate(
                child: StaticLoadingState(
                  message: GochanoLanguage.text(
                    'Loading your profile…',
                    'আপনার প্রোফাইল লোড হচ্ছে…',
                  ),
                ),
              );
            }
            if (profileSnapshot.hasError) {
              return _Gate(
                child: ErrorState(
                  message: friendlyErrorMessage(profileSnapshot.error),
                  onRetry: AuthService.reloadUser,
                ),
              );
            }

            final data = profileSnapshot.data?.data();
            if (data == null) {
              // Half-built / missing profile. Repair through
              // AuthService.ensureProfile() — it is idempotent
              // (`SetOptions(merge: true)`), so a second call is safe
              // but a no-op in practice.
              final inFlight = _profileRepair;
              if (inFlight != null) {
                return FutureBuilder<bool>(
                  future: inFlight,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return _Gate(
                        child: StaticLoadingState(
                          message: GochanoLanguage.text(
                            'Repairing your profile…',
                            'আপনার প্রোফাইল ঠিক করা হচ্ছে…',
                          ),
                        ),
                      );
                    }
                    if (snap.hasError || snap.data != true) {
                      return _Gate(
                        child: ErrorState(
                          title: GochanoLanguage.text(
                            'Your profile is missing',
                            'আপনার প্রোফাইল পাওয়া যাচ্ছে না',
                          ),
                          message: GochanoLanguage.text(
                            'We could not repair your profile. Try again — '
                            'if it keeps happening, sign out and register '
                            'again.',
                            'আপনার প্রোফাইল ঠিক করা যায়নি। আবার চেষ্টা করুন — '
                            'বারবার হলে সাইন আউট করে আবার রেজিস্টার করুন।',
                          ),
                          onRetry: () {
                            final future = AuthService.ensureProfile();
                            _profileRepair = future;
                            future.then((ok) {
                              if (ok) _profileRepaired.add(user.uid);
                            }).catchError((Object e, StackTrace _) {
                              _debugLog(
                                'AuthGate: profile repair retry failed: $e',
                              );
                            });
                          },
                        ),
                      );
                    }
                    if (snap.data == true) {
                      _profileRepaired.add(user.uid);
                    }
                    // The Firestore snapshot will re-emit shortly now
                    // that the doc exists; show a transient loading
                    // state instead of flashing an error.
                    return _Gate(
                      child: StaticLoadingState(
                        message: GochanoLanguage.text(
                          'Loading your profile…',
                          'আপনার প্রোফাইল লোড হচ্ছে…',
                        ),
                      ),
                    );
                  },
                );
              }
              // No in-flight repair yet — kick one off and re-render.
              final future = AuthService.ensureProfile();
              _profileRepair = future;
              future.then((ok) {
                if (ok) _profileRepaired.add(user.uid);
              }).catchError((Object e, StackTrace _) {
                _debugLog('AuthGate: profile repair failed: $e');
              });
              return _Gate(
                child: StaticLoadingState(
                  message: GochanoLanguage.text(
                    'Repairing your profile…',
                    'আপনার প্রোফাইল ঠিক করা হচ্ছে…',
                  ),
                ),
              );
            }

            return GochanoShell(
              role: data['role']?.toString() ?? 'general',
              displayName: data['displayName']?.toString() ?? '',
            );
          },
        );
      },
    );
  }
}

/// A bare scaffold for the pre-app states, so loading and error screens sit
/// on the Gochano background rather than on raw white.
class _Gate extends StatelessWidget {
  const _Gate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GochanoScaffold(body: child);
}
