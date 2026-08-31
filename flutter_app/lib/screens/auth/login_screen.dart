import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';

import '../../core/page_route.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() => busy = true);
    try {
      await AuthService.login(email.text, password.text);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reset() async {
    if (email.text.trim().isEmpty) {
      showError(
        context,
        Exception(
          EkLanguage.text('Enter your email first.', 'আগে আপনার ইমেইল লিখুন।'),
        ),
      );
      return;
    }
    try {
      await AuthService.sendPasswordReset(email.text);
      if (mounted) {
        showSuccess(
          context,
          EkLanguage.text(
            'Password reset email sent.',
            'পাসওয়ার্ড রিসেট ইমেইল পাঠানো হয়েছে।',
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: const LanguageToggle(),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: EkShadows.hero,
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        'assets/branding/Gochano.png',
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        semanticLabel: 'Gochano logo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 35,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                  Text(
                    EkLanguage.text(
                      'Everything in One Place',
                      'আপনার সবকিছুর এক ঠিকানা',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    EkLanguage.text(
                      'Your study. Your life. Organized beautifully.',
                      'পড়াশোনা আর দৈনন্দিন জীবন—একসাথে গুছানো।',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: EkColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: EkLanguage.text('Email', 'ইমেইল'),
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 11),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: EkLanguage.text('Password', 'পাসওয়ার্ড'),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : reset,
                      child: Text(
                        EkLanguage.text(
                          'Forgot password?',
                          'পাসওয়ার্ড ভুলে গেছেন?',
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: busy ? null : login,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        EkLanguage.text(
                          busy ? 'Signing in…' : 'Sign in',
                          busy ? 'সাইন ইন হচ্ছে…' : 'সাইন ইন',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            GochanoRoute.to(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                    child: Text(
                      EkLanguage.text('Create account', 'অ্যাকাউন্ট তৈরি করুন'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
