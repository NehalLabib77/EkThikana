// OTP verification for the Robi / Cirkle telecom login.
//
// Behavior contract (spec §6 + PART 30 — corrected):
//   * The user came here from `LoginScreen` because their subscription
//     was not yet REGISTERED. They must enter the code that was sent to
//     the phone they just typed.
//   * The page is full-screen with a back arrow in the app bar so the
//     user can go back to the phone screen with one tap.
//   * A 240s countdown tells them when they can resend the code.
//   * The user can tap "Wrong number? Change number" to go back without
//     re-typing the phone number.
//   * Shortcut: if /send_otp.php returns "already registered" AND a
//     follow-up /check_subscription.php confirms the number is in a
//     subscribed state (REGISTERED or INITIAL CHARGING PENDING), we
//     set the recentlyVerified marker and return to LoginScreen so the
//     normal subscription flow handles entry — see
//     [TelecomAuthService.kAlreadySubscribedSentinel].
//   * On success (PART 30 — corrected): the OTP is permanently consumed.
//     We immediately attempt the normal authenticated entry flow:
//       1. check_subscription → REGISTERED/INITIAL CHARGING PENDING
//       2. exchangeSubscriptionForFirebaseSession
//       3. signInToFirebaseWithCustomToken + getIdToken(true)
//       4. profile check → Home/ProfileSetup
//     If ALL post-OTP steps succeed, enter the app directly.
//     If ANY post-OTP step fails (network, Firebase, backend, profile):
//       - NEVER retry the consumed OTP
//       - Store recentlyVerified routing marker
//       - Clear OTP UI state
//       - Navigate to clean LoginScreen with message:
//         EN: "Number verified. Please sign in again."
//         BN: "নম্বর যাচাই হয়েছে। আবার সাইন ইন করুন।"
//   * On failure we keep them on this screen with an inline error.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/services/telecom_auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import '../../shell/presentation/gochano_shell.dart';
import 'login_screen.dart';
import 'profile_setup_screen.dart';

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key, required this.phone});

  final String phone;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  static const Duration _otpTimer = Duration(seconds: 240);

  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String? _referenceNo;
  String? _errorText;
  bool _sending = false;
  bool _verifying = false;
  Timer? _ticker;
  Duration _remaining = _otpTimer;

  @override
  void initState() {
    super.initState();
    _requestOtp();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _errorText = null;
    });
    try {
      final ref = await TelecomAuthService.sendOtp(widget.phone);
        if (ref == TelecomAuthService.kAlreadySubscribedSentinel) {
        // PART 30: The carrier reports the number as already subscribed.
        // Instead of entering the shell directly, set the recentlyVerified
        // marker and navigate back to LoginScreen so the normal
        // subscription check flow handles it.
        if (!mounted) return;
        await TelecomAuthService.setRecentlyVerified(phone: widget.phone);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              GochanoLanguage.text(
                'Number verified. Sign in with your number.',
                'নম্বর যাচাই হয়েছে। আপনার নম্বর দিয়ে সাইন ইন করুন।',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }
      _referenceNo = ref;
      _startTimer();
      _otpFocus.requestFocus();
    } on TelecomAuthException catch (e) {
      _errorText = e.message;
    } catch (_) {
      _errorText = GochanoLanguage.text(
        'Could not send the verification code. Please try again.',
        'ভেরিফিকেশন কোড পাঠানো যায়নি। আবার চেষ্টা করুন।',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startTimer() {
    _ticker?.cancel();
    setState(() => _remaining = _otpTimer);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _remaining = Duration.zero;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verify() async {
    if (_verifying) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_referenceNo == null) {
      setState(() {
        _errorText = GochanoLanguage.text(
          'Verification session expired. Please request a new code.',
          'ভেরিফিকেশন সেশন শেষ হয়ে গেছে। নতুন কোড নিন।',
        );
      });
      return;
    }

    setState(() {
      _verifying = true;
      _errorText = null;
    });

    try {
      final ok = await TelecomAuthService.verifyOtp(
        referenceNo: _referenceNo!,
        otp: _otpController.text,
        phone: widget.phone,
      );
      if (!mounted) return;
      if (ok) {
        // PART 30 — corrected: OTP verified by carrier. The OTP is now
        // permanently consumed — treat as one-shot. Immediately attempt
        // the normal authenticated entry flow.

        // 1. Check subscription status
        final TelecomSubscriptionResult subResult;
        try {
          subResult = await TelecomAuthService.checkSubscription(widget.phone);
        } catch (e) {
          // Post-OTP failure: OTP consumed, cannot retry
          await _handlePostOtpFailure('Subscription check failed');
          return;
        }
        if (!mounted) return;

        // 2. If NOT SUBSCRIBED after OTP verification — propagation delay
        //    Return to LoginScreen with marker; user can retry later
        if (!subResult.isAlreadySubscribed) {
          await _handlePostOtpFailure('Subscription not yet active');
          return;
        }

        // 3. Exchange subscription for Firebase session
        final TelecomFirebaseExchange exchange;
        try {
          exchange = await TelecomAuthService.exchangeSubscriptionForFirebaseSession(
            phone: widget.phone,
            subscriptionStatus: subResult.rawStatus,
          );
        } catch (e) {
          await _handlePostOtpFailure('Firebase exchange failed');
          return;
        }
        if (!mounted) return;

        // 4. Sign in to Firebase + refresh token
        try {
          debugPrint('[AuthFlow] firebase signIn started');
          await TelecomAuthService.enterSession(
            phone: widget.phone,
            exchange: exchange,
          );
          debugPrint('[AuthFlow] firebase user=${FirebaseAuth.instance.currentUser != null ? "non-null" : "null"}');
        } catch (e) {
          debugPrint('[AuthFlow] FAIL: firebase sign-in exception: ${e.runtimeType}');
          await _handlePostOtpFailure('Firebase sign-in failed');
          return;
        }
        if (!mounted) return;

        // SAFETY: Verify Firebase user actually exists before profile lookup.
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          debugPrint('[AuthFlow] FAIL: currentUser is null after enterSession');
          await _handlePostOtpFailure('Firebase user null after sign-in');
          return;
        }

        // 5. Profile check → resolve destination BEFORE "Taking you in".
        debugPrint('[AuthFlow] token refresh started');
        try {
          await currentUser.getIdToken(true);
          debugPrint('[AuthFlow] token refresh success=true');
        } catch (_) {
          debugPrint('[AuthFlow] token refresh success=false');
        }
        debugPrint('[AuthFlow] profile check started');
        final profileState = await FirestoreService.checkProfileState();
        debugPrint('[AuthFlow] destination=${profileState.name}');
        if (!mounted) return;

        // 6. Destination is resolved — show "Taking you in" for ~1.2s
        //    ONLY after all auth + profile work is complete.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              GochanoLanguage.text(
                'Taking you in…',
                'আপনাকে প্রবেশ করানো হচ্ছে…',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1200),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;

        switch (profileState) {
          case ProfileCheckResult.exists:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => GochanoShell(
                  role: 'student',
                  displayName: widget.phone,
                ),
              ),
              (_) => false,
            );
          case ProfileCheckResult.missing:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ProfileSetupScreen(phone: widget.phone),
              ),
              (_) => false,
            );
          case ProfileCheckResult.error:
            // Profile lookup failed — OTP is consumed; route to
            // LoginScreen recovery.
            await _handlePostOtpFailure('Profile lookup failed');
        }
        return;
      }
      setState(() {
        _errorText = GochanoLanguage.text(
          'That code did not match. Please check and try again.',
          'কোডটি সঠিক নয়। যাচাই করে আবার চেষ্টা করুন।',
        );
      });
    } on TelecomAuthException catch (e) {
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() {
        _errorText = GochanoLanguage.text(
          'Network error. Please check your connection and try again.',
          'নেটওয়ার্ক ত্রুটি। সংযোগ যাচাই করে আবার চেষ্টা করুন।',
        );
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Handle post-OTP failure: OTP is consumed, cannot retry.
  /// Roll back any partially-created auth/session state, store routing
  /// marker, clear OTP state, navigate to LoginScreen.
  Future<void> _handlePostOtpFailure(String reason) async {
    debugPrint('[OtpVerify] post-OTP failure: $reason');
    if (!mounted) return;

    // Roll back any partially-created auth session. enterSession()
    // may have already set isLoggedIn + userPhone in SharedPreferences
    // and signed in to Firebase. clearSession() signs out of Firebase
    // first, then clears SharedPreferences, so AuthGate never sees a
    // stale currentUser.
    await TelecomAuthService.clearSession();

    // Store routing marker (NOT auth proof) for propagation detection.
    // Must happen AFTER clearSession() (which calls clearRecentlyVerified)
    // but BEFORE clearing OTP UI state.
    await TelecomAuthService.setRecentlyVerified(phone: widget.phone);

    // Clear OTP UI state
    _otpController.clear();
    _referenceNo = null;
    _ticker?.cancel();

    if (!mounted) return;

    // Show recovery message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          GochanoLanguage.text(
            'Number verified. Please sign in again.',
            'নম্বর যাচাই হয়েছে। আবার সাইন ইন করুন।',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );

    // Navigate to clean LoginScreen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String? _validateOtp(String? value) {
    final raw = (value ?? '').trim();
    if (raw.length < 4) {
      return GochanoLanguage.text(
        'Enter the verification code',
        'ভেরিফিকেশন কোড লিখুন',
      );
    }
    return null;
  }

  String _maskedPhone() {
    final p = widget.phone;
    if (p.length < 6) return p;
    return '${p.substring(0, 4)} ${p.substring(4, p.length - 2)} ${p.substring(p.length - 2)}';
  }

  String _remainingLabel() {
    final s = _remaining.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final canResend = _remaining <= Duration.zero && !_sending;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          'Verify your number',
          'নম্বর যাচাই করুন',
        ),
        actions: const [
          LanguageToggle(),
          SizedBox(width: GochanoSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.md,
              vertical: GochanoSpacing.lg,
            ),
            children: [
              SectionHeader(
                title: GochanoLanguage.text(
                  'Enter the verification code',
                  'ভেরিফিকেশন কোড লিখুন',
                ),
                subtitle: GochanoLanguage.text(
                  'We sent a code to ${_maskedPhone()}. It may take a moment to arrive.',
                  'আমরা ${_maskedPhone()} নম্বরে একটি কোড পাঠিয়েছি। '
                  'কিছুক্ষণ সময় লাগতে পারে।',
                ),
              ),
              const SizedBox(height: GochanoSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      GochanoLanguage.text(
                        'Verification code',
                        'ভেরিফিকেশন কোড',
                      ),
                      style: type.cardHeading.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: GochanoSpacing.xs),
                    TextFormField(
                      controller: _otpController,
                      focusNode: _otpFocus,
                      enabled: !_verifying && !_sending,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: InputDecoration(
                        hintText: GochanoLanguage.text(
                          'Enter code',
                          'কোড লিখুন',
                        ),
                        prefixIcon: Icon(
                          Icons.sms_outlined,
                          color: colors.textSecondary,
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: GochanoRadius.smAll,
                        ),
                        errorText: _errorText,
                      ),
                      validator: _validateOtp,
                      onFieldSubmitted: (_) => _verify(),
                    ),
                    const SizedBox(height: GochanoSpacing.sm),
                    if (_sending)
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: GochanoSpacing.xs),
                          Text(
                            GochanoLanguage.text(
                              'Sending code…',
                              'কোড পাঠানো হচ্ছে…',
                            ),
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 16,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: GochanoSpacing.xs),
                          Expanded(
                            child: Text(
                              canResend
                                  ? GochanoLanguage.text(
                                      'You can resend the code now.',
                                      'আপনি এখন নতুন কোড চাইতে পারেন।',
                                    )
                                  : GochanoLanguage.text(
                                      'Resend code in ${_remainingLabel()}',
                                      '${_remainingLabel()} পর আবার কোড নিন',
                                    ),
                              style: type.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: GochanoSpacing.lg),
              PrimaryButton(
                label: _verifying
                    ? GochanoLanguage.text(
                        'Verifying…', 'যাচাই হচ্ছে…')
                    : GochanoLanguage.text(
                        'Verify', 'যাচাই করুন'),
                onPressed: (_verifying || _sending)
                    ? null
                    : _verify,
                icon: Icons.check_circle_outline_rounded,
              ),
              const SizedBox(height: GochanoSpacing.md),
              Row(
                children: [
                  Flexible(
                    child: TextButton.icon(
                      onPressed:
                          (_sending || _verifying)
                              ? null
                              : _requestOtp,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        GochanoLanguage.text(
                          'Resend code',
                          'আবার কোড পাঠান',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Flexible(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        GochanoLanguage.text(
                          'Wrong number? Change number',
                          'ভুল নম্বর? নম্বর পরিবর্তন করুন',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
