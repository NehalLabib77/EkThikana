import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/ui.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';

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
      showError(context, Exception('Enter your email first.'));
      return;
    }
    try {
      await AuthService.sendPasswordReset(email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const SizedBox(height: 36),
                const Icon(Icons.home_work_outlined, size: 72),
                const SizedBox(height: 16),
                const Text(
                  AppConfig.appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                ),
                const Text(
                  AppConfig.tagline,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : login,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(busy ? 'Signing in…' : 'Sign in'),
                  ),
                ),
                TextButton(onPressed: busy ? null : reset, child: const Text('Forgot password?')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                          ),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
