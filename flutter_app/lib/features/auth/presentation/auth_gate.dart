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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/gochano_language.dart';
import '../../../services/auth_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../shell/presentation/gochano_shell.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
        if (user == null) return const LoginScreen();
        if (!user.emailVerified) return const VerifyEmailScreen();

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
              return _Gate(
                child: ErrorState(
                  title: GochanoLanguage.text(
                    'Your profile is missing',
                    'আপনার প্রোফাইল পাওয়া যাচ্ছে না',
                  ),
                  message: GochanoLanguage.text(
                    'Sign out and register again, or contact support if this '
                    'keeps happening.',
                    'সাইন আউট করে আবার রেজিস্টার করুন, অথবা বারবার হলে সহায়তা নিন।',
                  ),
                  onRetry: AuthService.reloadUser,
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
