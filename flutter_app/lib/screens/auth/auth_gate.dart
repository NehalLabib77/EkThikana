import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "../../services/auth_service.dart";
import "../../widgets/gochano_loading.dart";
import "../home/home_shell.dart";
import "login_screen.dart";
import "verify_email_screen.dart";

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authState(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _GateLoading(key: ValueKey<String>("auth-state-loading"));
        }
        if (authSnap.hasError) {
          return _GateError(
            error: authSnap.error!,
            onRetry: AuthService.reloadUser,
          );
        }
        final user = authSnap.data;
        if (user == null) return const LoginScreen();
        if (!user.emailVerified) return const VerifyEmailScreen();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(user.uid)
              .snapshots(),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const _GateLoading(key: ValueKey<String>("profile-loading"));
            }
            if (profileSnap.hasError) {
              return _GateError(
                error: profileSnap.error!,
                onRetry: AuthService.reloadUser,
              );
            }
            final data = profileSnap.data?.data();
            if (data == null) {
              return _GateError(
                error: Exception("Your Gochano profile is missing from Firestore."),
                onRetry: AuthService.reloadUser,
              );
            }
            final role = data["role"]?.toString() ?? "general";
            return HomeShell(
              role: role,
              displayName: data["displayName"]?.toString() ?? "",
            );
          },
        );
      },
    );
  }
}

class _GateLoading extends StatefulWidget {
  const _GateLoading({super.key});
  @override
  State<_GateLoading> createState() => _GateLoadingState();
}

class _GateLoadingState extends State<_GateLoading> {
  late final ValueNotifier<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = ValueNotifier<int>(0);
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (!mounted) return;
      _ticker.value++;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: _ticker,
        builder: (context, value, _) {
          return GochanoLoading(
            onRetry: value > 0 ? () => AuthService.reloadUser() : null,
            showRetryAfter: const Duration(milliseconds: 200),
          );
        },
      ),
    );
  }
}

class _GateError extends StatelessWidget {
  const _GateError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48, color: scheme.error),
                const SizedBox(height: 12),
                Text(
                  "Could not reach your account",
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    onRetry();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
