import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool busy = false;

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      await AuthService.reloadUser();
      final user = FirebaseAuth.instance.currentUser;
      if (user?.emailVerified != true) {
        throw Exception('Email is not verified yet.');
      }
      setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 72),
                  const SizedBox(height: 16),
                  const Text(
                    'Verify your email',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We sent a verification link to ${FirebaseAuth.instance.currentUser?.email ?? ''}.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : refresh,
                    child: Text(busy ? 'Checking…' : 'I verified my email'),
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.currentUser?.sendEmailVerification(),
                    child: const Text('Resend verification email'),
                  ),
                  TextButton(
                    onPressed: AuthService.logout,
                    child: const Text('Sign out'),
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
