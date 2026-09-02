// Email verification gate.
//
// The backend rejects an unverified Firebase token outright
// (`get_verified_identity` returns 403 when `email_verified` is false), so
// this is not a nag screen — nothing in the app would work past it. It says
// so plainly and gives the actions that resolve it.
//
// Verification is auto-detected from three independent triggers so the
// user does not have to know what is happening under the hood:
//
//   * periodic polling every ~2.5 seconds while the screen is mounted,
//   * `AppLifecycleState.resumed` (user opens the email app, taps the
//     link, then comes back to Gochano),
//   * manual "I have verified" button as a fallback.
//
// All three go through `AuthService.reloadUser()`, which calls
// `FirebaseAuth.instance.currentUser.reload()` and pings the refresh
// notifier that `AuthGate` listens to. When `emailVerified` flips true,
// the gate swaps this screen out for the app — there is no manual
// Navigator push from here.

import 'dart:async';

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

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  /// Background polling cadence. Long enough that a verification link
  /// tap on the same device reliably beats it (Firebase typically
  /// reflects the change within a second or two), short enough that
  /// the user does not stare at "not yet" for long.
  static const Duration _pollInterval = Duration(milliseconds: 2500);

  /// Per-uid resend cooldown, mirrored in `AuthService.resendVerification`.
  /// Kept in lockstep here so the button can show a live countdown.
  static const Duration _resendCooldown = Duration(seconds: 45);

  Timer? _pollTimer;
  bool _checking = false;

  bool _resending = false;
  int _cooldownRemaining = 0;
  Timer? _cooldownTimer;

  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kick off an immediate check so a user who already verified in
    // another tab does not have to wait one full interval.
    _schedulePoll(immediate: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pollTimer = null;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The user came back from the mail app — check now, and restart
      // the poll so the next fallback is fresh from this resume.
      _schedulePoll(immediate: true);
    }
  }

  String get _email => FirebaseAuth.instance.currentUser?.email ?? '';

  /// Restarts (or starts) the polling loop. Guarantees we never run
  /// two timers in parallel — the previous handle is always cancelled
  /// before a new one is created, and the `_checking` guard inside
  /// `_runCheck` prevents overlapping Firebase reload requests.
  void _schedulePoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (immediate) {
      _runCheck();
    }
    _pollTimer = Timer.periodic(_pollInterval, (_) => _runCheck());
  }

  Future<void> _runCheck() async {
    if (!mounted) return;
    if (_checking) return; // already in flight; skip overlapping reloads
    setState(() {
      _checking = true;
    });
    try {
      await AuthService.reloadUser();
      if (!mounted) return;
      // `AuthService.reloadUser` already pings the gate's refresh
      // notifier, so if `emailVerified` flipped true the gate will
      // swap this screen out before this setState lands. The branches
      // below only matter when we are still unverified.
      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      setState(() {
        _checking = false;
        _messageIsError = true;
        _message = verified
            ? null
            : GochanoLanguage.text(
                'Not verified yet. Open the link in your email, then check '
                'again.',
                'এখনো যাচাই হয়নি। ইমেইলের লিংকটি খুলে আবার দেখুন।',
              );
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
    if (_resending || _cooldownRemaining > 0) return;
    setState(() {
      _resending = true;
      _message = null;
    });
    try {
      final blocked = await AuthService.resendVerification(
        cooldown: _resendCooldown,
      );
      if (!mounted) return;
      if (blocked > 0) {
        _startCooldown(blocked);
        setState(() {
          _resending = false;
          _messageIsError = true;
          _message = GochanoLanguage.text(
            'Please wait a moment before sending again.',
            'আবার পাঠানোর আগে একটু অপেক্ষা করুন।',
          );
        });
        return;
      }
      setState(() {
        _resending = false;
        _cooldownRemaining = _resendCooldown.inSeconds;
        _messageIsError = false;
        _message = GochanoLanguage.text(
          'Verification email sent again.',
          'যাচাই ইমেইল আবার পাঠানো হয়েছে।',
        );
      });
      _startCooldown(_resendCooldown.inSeconds);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _messageIsError = true;
        _message = friendlyErrorMessage(
          error,
          fallback: GochanoLanguage.text(
            'Could not send the email right now. Wait a minute and try '
            'again.',
            'এখন ইমেইল পাঠানো যায়নি। এক মিনিট পরে আবার চেষ্টা করুন।',
          ),
        );
      });
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownRemaining = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownRemaining <= 1) {
          _cooldownRemaining = 0;
          timer.cancel();
        } else {
          _cooldownRemaining -= 1;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final canResend = !_resending && _cooldownRemaining == 0;
    final resendBusy = _resending;
    final resendLabel = _cooldownRemaining > 0
        ? GochanoLanguage.text(
            'Send again in ${_cooldownRemaining}s',
            'আবার পাঠান ($_cooldownRemaining সেকেন্ডে)',
          )
        : GochanoLanguage.text('Send the email again', 'ইমেইল আবার পাঠান');

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
            label: GochanoLanguage.text("I've verified — check again",
                'যাচাই করেছি — দেখুন'),
            busy: _checking,
            busyLabel: GochanoLanguage.text('Checking…', 'দেখা হচ্ছে…'),
            onPressed: () => _schedulePoll(immediate: true),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          SecondaryButton(
            label: resendBusy
                ? GochanoLanguage.text(
                    'Sending…',
                    'পাঠানো হচ্ছে…',
                  )
                : resendLabel,
            onPressed: canResend ? _resend : null,
          ),
          const SizedBox(height: GochanoSpacing.md),
          TextButton(
            onPressed: AuthService.logout,
            child: Text(
              GochanoLanguage.text(
                'Use a different account',
                'অন্য অ্যাকাউন্ট',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
