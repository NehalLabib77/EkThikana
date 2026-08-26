import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final university = TextEditingController();
  final department = TextEditingController();
  final semester = TextEditingController();

  // PART 3: every new Gochano account is a Student by policy. The role
  // selector was removed; backend rules already enforce role immutability.
  final String role = 'student';
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    university.dispose();
    department.dispose();
    semester.dispose();
    super.dispose();
  }

  Future<void> register() async {
    if (name.text.trim().isEmpty || email.text.trim().isEmpty || password.text.length < 6) {
      showError(context, Exception('Name, valid email and a 6+ character password are required.'));
      return;
    }

    setState(() => busy = true);
    try {
      await AuthService.register(
        name: name.text,
        email: email.text,
        password: password.text,
        role: role,
        university: university.text,
        department: department.text,
        semester: semester.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Gochano account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password (6+ characters)'),
              ),
              const SizedBox(height: 10),
              TextField(controller: university, decoration: const InputDecoration(labelText: 'University')),
              const SizedBox(height: 10),
              TextField(controller: department, decoration: const InputDecoration(labelText: 'Department')),
              const SizedBox(height: 10),
              TextField(controller: semester, decoration: const InputDecoration(labelText: 'Current semester')),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy ? null : register,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(busy ? 'Creating…' : 'Create account'),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'A verification email will be sent before the account can access Gochano data.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
