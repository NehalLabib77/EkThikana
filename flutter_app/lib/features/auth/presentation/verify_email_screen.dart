// Email verification gate.
//
// The backend rejects an unverified Firebase token outright
// (`get_verified_identity` returns 403 when `email_verified` is false), so
// this is not a nag screen — nothing in the app would work past it. It says
// so plainly and gives the two actions that resolve it.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/auth_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _checking = false;
  bool _sending = false;
  String? _message;
  bool _messageIsError = false;

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      await AuthService.reloadUser();
      if (!mounted) return;
      // If verification succeeded, the AuthGate's auth stream replaces this
      // screen. Reaching here means it is still unverified.
      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      setState(() {
        _checking = false;
        if (!verified) {
          _messageIsError = true;
          _message = GochanoLanguage.text(
            'Not verified yet. Open the link in your email, then check again.',
            'এখনো যাচাই হয়নি। ইমেইলের লিংকটি খুলে আবার দেখুন।',
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _messageIsError = true;
        _message = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messageIsError = false;
        _message = GochanoLanguage.text(
          'Verification email sent again.',
          'যাচাই ইমেইল আবার পাঠানো হয়েছে।',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messageIsError = true;
        _message = friendlyErrorMessage(
          error,
          fallback: GochanoLanguage.text(
            'Could not send the email right now. Wait a minute and try again.',
            'এখন ইমেইল পাঠানো যায়নি। এক মিনিট পরে আবার চেষ্টা করুন।',
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Verify your email', 'ইমেইল যাচাই করুন'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        children: [
          const SizedBox(height: GochanoSpacing.xl),
          Center(
            child: GochanoIllustration(
              GochanoArt.featurePrescription,
              size: GochanoSizes.illustrationEmpty,
              accent: colors.brand,
            ),
          ),
          const SizedBox(height: GochanoSpacing.lg),
          Text(
            GochanoLanguage.text(
              'Check your email',
              'আপনার ইমেইল দেখুন',
            ),
            style: type.pageTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              'We sent a verification link to $_email. Open it, then come '
              'back and check again.',
              '$_email এ একটি যাচাই লিংক পাঠানো হয়েছে। সেটি খুলে ফিরে এসে আবার দেখুন।',
            ),
            style: type.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            GochanoLanguage.text(
              'Gochano cannot load your materials until the email is '
              'verified.',
              'ইমেইল যাচাই না হওয়া পর্যন্ত গোছানো আপনার উপকরণ লোড করতে পারবে না।',
            ),
            style: type.caption,
            textAlign: TextAlign.center,
          ),

          if (_message != null) ...[
            const SizedBox(height: GochanoSpacing.md),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: _messageIsError ? colors.errorSoft : colors.successSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Text(
                _message!,
                style: type.bodySecondary.copyWith(
                  color: _messageIsError ? colors.error : colors.success,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: GochanoSpacing.xl),
          PrimaryButton(
            label: GochanoLanguage.text("I've verified — check again", 'যাচাই করেছি — দেখুন'),
            busy: _checking,
            busyLabel: GochanoLanguage.text('Checking…', 'দেখা হচ্ছে…'),
            onPressed: _check,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          SecondaryButton(
            label: GochanoLanguage.text('Send the email again', 'ইমেইল আবার পাঠান'),
            onPressed: _sending ? null : _resend,
          ),
          const SizedBox(height: GochanoSpacing.md),
          TextButton(
            onPressed: AuthService.logout,
            child: Text(
              GochanoLanguage.text('Use a different account', 'অন্য অ্যাকাউন্ট'),
            ),
          ),
        ],
      ),
    );
  }
}
