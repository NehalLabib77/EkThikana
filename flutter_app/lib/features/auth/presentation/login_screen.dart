// Sign in.
//
// The first screen a student sees, so it stays to the point: the brand mark,
// two fields, one primary action, and the two escape hatches (forgot
// password, create account).

import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/auth_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() {
        _error = GochanoLanguage.text(
          'Enter your email and password.',
          'আপনার ইমেইল ও পাসওয়ার্ড লিখুন।',
        );
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.login(_email.text, _password.text);
      // On success the AuthGate stream swaps this screen out; there is
      // nothing to navigate to from here.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _authMessage(error);
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() {
        _error = GochanoLanguage.text(
          'Enter your email first, then tap reset.',
          'আগে আপনার ইমেইল লিখুন, তারপর রিসেট চাপুন।',
        );
      });
      return;
    }
    try {
      await AuthService.sendPasswordReset(_email.text);
      if (!mounted) return;
      showGochanoMessage(
        context,
        GochanoLanguage.text(
          'Password reset email sent. Check your inbox.',
          'পাসওয়ার্ড রিসেট ইমেইল পাঠানো হয়েছে। ইনবক্স দেখুন।',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _authMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: '',
        automaticallyImplyLeading: false,
        actions: const [LanguageToggle(), SizedBox(width: GochanoSpacing.xs)],
      ),
      body: ListView(
        children: [
          const SizedBox(height: GochanoSpacing.lg),
          const Center(child: _BrandMark()),
          const SizedBox(height: GochanoSpacing.lg),
          Text(
            GochanoLanguage.text('Welcome back', 'আবার স্বাগতম'),
            style: type.pageTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            GochanoLanguage.text(
              'Sign in to ${AppConfig.appName} to continue.',
              'চালিয়ে যেতে ${AppConfig.appName} এ সাইন ইন করুন।',
            ),
            style: type.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.xl),

          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Email', 'ইমেইল'),
              prefixIcon: const Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Password', 'পাসওয়ার্ড'),
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconActionButton(
                icon: _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                label: _showPassword
                    ? GochanoLanguage.text('Hide password', 'পাসওয়ার্ড লুকান')
                    : GochanoLanguage.text('Show password', 'পাসওয়ার্ড দেখান'),
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),

          if (_error != null) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: GochanoSizes.iconSm,
                    color: colors.error,
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      _error!,
                      style: type.bodySecondary.copyWith(color: colors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: GochanoSpacing.lg),
          PrimaryButton(
            label: GochanoLanguage.text('Sign in', 'সাইন ইন'),
            busy: _busy,
            busyLabel: GochanoLanguage.text('Signing in…', 'সাইন ইন হচ্ছে…'),
            onPressed: _login,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          TextButton(
            onPressed: _busy ? null : _resetPassword,
            child: Text(
              GochanoLanguage.text('Forgot password?', 'পাসওয়ার্ড ভুলে গেছেন?'),
            ),
          ),
          const SizedBox(height: GochanoSpacing.md),
          SecondaryButton(
            label: GochanoLanguage.text('Create an account', 'অ্যাকাউন্ট তৈরি করুন'),
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      GochanoRoute.to(builder: (_) => const RegisterScreen()),
                    ),
          ),
        ],
      ),
    );
  }
}

/// The Gochano logo on a plain plate.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 88,
      height: 88,
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.xlAll,
        border: Border.all(color: colors.border),
      ),
      child: Image.asset(
        'assets/branding/Gochano.png',
        fit: BoxFit.contain,
        gaplessPlayback: true,
        // Drawn at ~64 logical px. The master artwork is 1254 square, which
        // would decode to roughly 6 MB of RAM; 512 is still far above the
        // physical size on a 4x display, so nothing looks different.
        cacheWidth: 512,
        semanticLabel: '${AppConfig.appName} logo',
      ),
    );
  }
}

/// Maps Firebase Auth failures onto sentences a student can act on.
///
/// Firebase returns codes like `invalid-credential` inside a long exception
/// string; showing that verbatim is exactly the leak spec §76 forbids.
String _authMessage(Object error) {
  final raw = error.toString().toLowerCase();

  if (raw.contains('invalid-credential') ||
      raw.contains('wrong-password') ||
      raw.contains('user-not-found') ||
      raw.contains('invalid-login-credentials')) {
    return GochanoLanguage.text(
      'That email and password do not match an account.',
      'এই ইমেইল ও পাসওয়ার্ড কোনো অ্যাকাউন্টের সাথে মেলে না।',
    );
  }
  if (raw.contains('invalid-email')) {
    return GochanoLanguage.text(
      'That does not look like a valid email address.',
      'এটি একটি সঠিক ইমেইল ঠিকানা বলে মনে হচ্ছে না।',
    );
  }
  if (raw.contains('user-disabled')) {
    return GochanoLanguage.text(
      'This account has been disabled.',
      'এই অ্যাকাউন্টটি নিষ্ক্রিয় করা হয়েছে।',
    );
  }
  if (raw.contains('too-many-requests')) {
    return GochanoLanguage.text(
      'Too many attempts. Wait a few minutes and try again.',
      'অনেকবার চেষ্টা হয়েছে। কয়েক মিনিট পরে আবার চেষ্টা করুন।',
    );
  }
  if (raw.contains('email-already-in-use')) {
    return GochanoLanguage.text(
      'An account already exists with this email. Sign in instead.',
      'এই ইমেইলে ইতিমধ্যে একটি অ্যাকাউন্ট আছে। সাইন ইন করুন।',
    );
  }
  if (raw.contains('weak-password')) {
    return GochanoLanguage.text(
      'Choose a longer password — at least 6 characters.',
      'আরও বড় পাসওয়ার্ড দিন — অন্তত ৬ অক্ষর।',
    );
  }
  return friendlyErrorMessage(error);
}

/// Exposed so the register screen maps the same failures the same way.
String authErrorMessage(Object error) => _authMessage(error);
