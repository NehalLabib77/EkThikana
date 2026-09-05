// Create an account.
//
// Every new Gochano account is a Student by policy — the role selector was
// removed deliberately and the backend enforces role immutability, so this
// screen does not offer a choice it cannot honour.
//
// University / department / semester are optional. They are stamped onto
// uploaded materials as metadata; making them mandatory would block sign-up
// on information a first-time user may not want to give yet.

import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/auth_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
// Note: this screen is legacy Firebase-email registration code left in
// place from before PART 16. PART 17 (Unsubscribe) is expected to retire
// it. Until then, we no longer reach across to `login_screen.dart` for
// the `authErrorMessage` helper that screen used to expose — we extract
// the message inline so this file still compiles.

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _university = TextEditingController();
  final _department = TextEditingController();
  final _semester = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _university.dispose();
    _department.dispose();
    _semester.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    String? problem;
    if (_name.text.trim().isEmpty) {
      problem = GochanoLanguage.text('Enter your name.', 'আপনার নাম লিখুন।');
    } else if (!_email.text.contains('@')) {
      problem = GochanoLanguage.text(
        'Enter a valid email address.',
        'একটি সঠিক ইমেইল ঠিকানা লিখুন।',
      );
    } else if (_password.text.length < 6) {
      problem = GochanoLanguage.text(
        'Password must be at least 6 characters.',
        'পাসওয়ার্ড অন্তত ৬ অক্ষরের হতে হবে।',
      );
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthService.register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        role: 'student',
        university: _university.text,
        department: _department.text,
        semester: _semester.text,
      );
      // Registration sends a verification email; the AuthGate takes over and
      // shows the verify screen.
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _extractAuthError(error);
      });
    }
  }

  // Legacy Firebase error stringification kept so this pre-PART-16 screen
  // still compiles. PART 17 is expected to delete this whole file.
  String _extractAuthError(Object error) {
    final raw = error.toString();
    final firebaseMatch = RegExp(r'\[([^]]+)\]').firstMatch(raw);
    if (firebaseMatch != null) return firebaseMatch.group(1) ?? raw;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Create account', 'অ্যাকাউন্ট তৈরি'),
      ),
      bottomBar: PrimaryButton(
        label: GochanoLanguage.text('Create account', 'অ্যাকাউন্ট তৈরি করুন'),
        busy: _busy,
        busyLabel: GochanoLanguage.text('Creating…', 'তৈরি হচ্ছে…'),
        onPressed: _register,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Text(
            GochanoLanguage.text(
              'Join ${AppConfig.appName}',
              '${AppConfig.appName} এ যোগ দিন',
            ),
            style: type.pageTitle,
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            GochanoLanguage.text(
              'One account for your study materials, tasks, money, medicine '
              'and commute.',
              'পড়ার উপকরণ, কাজ, টাকা, ওষুধ ও যাতায়াতের জন্য একটি অ্যাকাউন্ট।',
            ),
            style: type.bodySecondary,
          ),
          const SizedBox(height: GochanoSpacing.lg),

          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Your name', 'আপনার নাম'),
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Email', 'ইমেইল'),
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              helperText: GochanoLanguage.text(
                'We send a verification link here.',
                'এখানে একটি যাচাই লিংক পাঠানো হবে।',
              ),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Password', 'পাসওয়ার্ড'),
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              helperText: GochanoLanguage.text(
                'At least 6 characters.',
                'অন্তত ৬ অক্ষর।',
              ),
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
          ),

          SectionHeader(
            title: GochanoLanguage.text('Your studies', 'আপনার পড়াশোনা'),
            subtitle: GochanoLanguage.text(
              'Optional. You can fill this in later.',
              'ঐচ্ছিক। পরে পূরণ করতে পারবেন।',
            ),
          ),
          TextField(
            controller: _university,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('University', 'বিশ্ববিদ্যালয়'),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _department,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Department', 'বিভাগ'),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _semester,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Semester', 'সেমিস্টার'),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: GochanoSpacing.md),
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
        ],
      ),
    );
  }
}
