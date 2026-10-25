// OTP verification for the Robi / Cirkle telecom login.
//
// Behavior contract (spec §6):
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
//     take the user straight into GochanoShell with no OTP — see
//     [TelecomAuthService.kAlreadySubscribedSentinel] and
//     [_OtpVerifyScreenState._enterShellFromSubscription]. This
//     covers the case where LoginScreen saw "not subscribed" but the
//     carrier has since confirmed the subscription.
//   * On success we persist the session and pop the entire auth stack so
//     the user lands on the home shell (and so the Back button does not
//     return them to OTP).
//   * On failure we keep them on this screen with an inline error.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/app_design_system.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/services/telecom_auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import '../../shell/presentation/gochano_shell.dart';
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
  bool _signingIn = false;
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
        // The carrier reports the number as already subscribed —
        // either REGISTERED (paying) or INITIAL CHARGING PENDING
        // (subscribe-tap accepted, first charge settling). Spec §3
        // lets the user in either way with no OTP step. We keep
        // _sending = true so the form stays disabled while we mint
        // the Firebase session, then flip to _signingIn so the status
        // text reflects what is actually happening.
        //
        // Re-fetch the canonical subscription status so we can pass
        // the right hint to the backend (it routes the request
        // through the subscription verification path and mints the
        // Firebase custom token with the matching claims). If the
        // status has flipped back to not-subscribed in the meantime
        // we surface a clear message instead of looping on /send_otp.
        final result = await TelecomAuthService.checkSubscription(widget.phone);
        if (!mounted) return;
        if (!result.isAlreadySubscribed) {
          throw TelecomAuthException(
            GochanoLanguage.text(
              'Subscription state is changing. Please tap "Resend code".',
              'সাবস্ক্রিপশন অবস্থা বদলে যাচ্ছে। "আবার কোড পাঠান" চাপুন।',
            ),
          );
        }
        setState(() => _signingIn = true);
        await _enterShellFromSubscription(subscriptionStatus: result.rawStatus);
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

  /// Mirrors the `isAlreadySubscribed` branch in `LoginScreen._continue`:
  /// mints a Firebase custom token via the backend, signs in with it,
  /// and pushes the home shell so the user lands inside Gochano without
  /// ever having to type an OTP. Used when the carrier reports the
  /// number as REGISTERED or INITIAL CHARGING PENDING before the
  /// user has finished the OTP flow.
  Future<void> _enterShellFromSubscription({
    required String subscriptionStatus,
  }) async {
    final TelecomFirebaseExchange exchange;
    try {
      exchange =
          await TelecomAuthService.exchangeSubscriptionForFirebaseSession(
            phone: widget.phone,
            subscriptionStatus: subscriptionStatus,
          );
    } on TelecomAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.message;
        _signingIn = false;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = GochanoLanguage.text(
          'Could not link your number to Gochano. Please try again later.',
          'আপনার নম্বর Gochano-তে সংযুক্ত করা যায়নি। কিছুক্ষণ পর আবার চেষ্টা করুন।',
        );
        _signingIn = false;
      });
      return;
    }
    if (!mounted) return;
    try {
      await TelecomAuthService.enterSession(
        phone: widget.phone,
        exchange: exchange,
      );
    } on TelecomAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.message;
        _signingIn = false;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = GochanoLanguage.text(
          'Could not sign you in. Please try again.',
          'সাইন ইন করা যায়নি। আবার চেষ্টা করুন।',
        );
        _signingIn = false;
      });
      return;
    }
    if (!mounted) return;
    final hasProfile = await FirestoreService.hasProfile();
    if (!mounted) return;
    String shellDisplayName = widget.phone;
    if (hasProfile) {
      final profile = await FirestoreService.profile();
      final name = profile['displayName']?.toString().trim();
      if (name != null && name.isNotEmpty) shellDisplayName = name;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => hasProfile
            ? GochanoShell(role: 'student', displayName: shellDisplayName)
            : ProfileSetupScreen(phone: widget.phone),
      ),
      (_) => false,
    );
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
        // PART 16.1: after a successful OTP we MUST establish a real
        // Firebase identity before persisting the local session and
        // entering GochanoShell. AuthGate refuses to enter the shell
        // unless FirebaseAuth.instance.currentUser is non-null, so the
        // custom-token exchange + signInWithCustomToken is what keeps
        // every Firestore read/write alive (Notes/Tasks/Expense/
        // Medicine/Dena-Pawna/Materials all require
        // request.auth.token.email_verified == true).
        final TelecomFirebaseExchange exchange;
        try {
          exchange = await TelecomAuthService.exchangeOtpForFirebaseSession(
            phone: widget.phone,
            referenceNo: _referenceNo!,
          );
        } on TelecomAuthException catch (e) {
          setState(() {
            _errorText = e.message;
            _verifying = false;
          });
          return;
        }
        if (!mounted) return;
        try {
          await TelecomAuthService.enterSession(
            phone: widget.phone,
            exchange: exchange,
          );
        } on TelecomAuthException catch (e) {
          setState(() {
            _errorText = e.message;
            _verifying = false;
          });
          return;
        }
        if (!mounted) return;
        final hasProfile = await FirestoreService.hasProfile();
        if (!mounted) return;
        String shellDisplayName = widget.phone;
        if (hasProfile) {
          final profile = await FirestoreService.profile();
          final name = profile['displayName']?.toString().trim();
          if (name != null && name.isNotEmpty) shellDisplayName = name;
        }
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => hasProfile
                ? GochanoShell(role: 'student', displayName: shellDisplayName)
                : ProfileSetupScreen(phone: widget.phone),
          ),
          (_) => false,
        );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final canResend = _remaining <= Duration.zero && !_sending;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Verify your number', 'নম্বর যাচাই করুন'),
        actions: const [
          LanguageToggle(),
          SizedBox(width: GochanoSpacing.xs),
        ],
      ),
      body: AppPageBackground(
        gradient: AppGradients.todayAppBarFor(isDark: isDark),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth <= 340;
                final horizontalPadding =
                    isNarrow ? GochanoSpacing.md : GochanoSpacing.lg;
                final verticalPadding =
                    isNarrow ? GochanoSpacing.sm : GochanoSpacing.md;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    verticalPadding,
                    horizontalPadding,
                    GochanoSpacing.lg,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight -
                              verticalPadding -
                              GochanoSpacing.lg)
                          .clamp(0.0, double.infinity),
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _OtpHero(
                            colors: colors,
                            type: type,
                            isDark: isDark,
                            compact: isNarrow,
                            maskedPhone: _maskedPhone(),
                          ),
                          SizedBox(
                            height: isNarrow
                                ? GochanoSpacing.md
                                : GochanoSpacing.lg,
                          ),
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        GochanoLanguage.text(
                                          'Verification code',
                                          'ভেরিফিকেশন কোড',
                                        ),
                                        style: type.cardHeading.copyWith(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: GochanoSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? colors.surfaceVariant
                                            : colors.brandSoft,
                                        borderRadius: GochanoRadius.smAll,
                                      ),
                                      child: Text(
                                        GochanoLanguage.text(
                                          '4-8 digits',
                                          '৪-৮ সংখ্যা',
                                        ),
                                        style: type.caption.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colors.brand,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: GochanoSpacing.xs),
                                TextFormField(
                                  controller: _otpController,
                                  focusNode: _otpFocus,
                                  enabled:
                                      !_verifying && !_sending && !_signingIn,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    fontFamily: '.SF Pro Text',
                                    fontFamilyFallback: const [
                                      'Roboto',
                                      'sans-serif',
                                    ],
                                    letterSpacing: 4.0,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(8),
                                  ],
                                  decoration: InputDecoration(
                                    hintText: GochanoLanguage.text(
                                      'Enter code',
                                      'কোড লিখুন',
                                    ),
                                    hintStyle: TextStyle(
                                      color: colors.textSecondary.withValues(
                                        alpha: 0.5,
                                      ),
                                      letterSpacing: 1.5,
                                      fontSize: 15,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Icon(
                                        Icons.sms_outlined,
                                        color: colors.brand,
                                        size: 20,
                                      ),
                                    ),
                                    prefixIconConstraints:
                                        const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    filled: true,
                                    fillColor: isDark
                                        ? colors.surfaceVariant
                                        : colors.background,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: GochanoSpacing.md,
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: GochanoRadius.mdAll,
                                      borderSide: BorderSide(
                                        color: colors.border,
                                        width: 1.0,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: GochanoRadius.mdAll,
                                      borderSide: BorderSide(
                                        color: colors.border,
                                        width: 1.0,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: GochanoRadius.mdAll,
                                      borderSide: BorderSide(
                                        color: colors.brand,
                                        width: 1.8,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: GochanoRadius.mdAll,
                                      borderSide: BorderSide(
                                        color: colors.error,
                                        width: 1.4,
                                      ),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: GochanoRadius.mdAll,
                                      borderSide: BorderSide(
                                        color: colors.error,
                                        width: 1.8,
                                      ),
                                    ),
                                    errorText: _errorText,
                                    errorMaxLines: 3,
                                  ),
                                  validator: _validateOtp,
                                  onFieldSubmitted: (_) => _verify(),
                                ),
                                const SizedBox(height: GochanoSpacing.sm),
                                AnimatedSwitcher(
                                  duration: AppMotion.duration(
                                    context,
                                    AppMotion.contentReveal,
                                  ),
                                  child: _signingIn
                                      ? Row(
                                          key: const ValueKey('signingIn'),
                                          children: [
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: GochanoSpacing.xs,
                                            ),
                                            Expanded(
                                              child: Text(
                                                GochanoLanguage.text(
                                                  'Your subscription is being confirmed. '
                                                      'Signing you in…',
                                                  'আপনার সাবস্ক্রিপশন নিশ্চিত হচ্ছে। '
                                                      'সাইন ইন করা হচ্ছে…',
                                                ),
                                                style: type.caption.copyWith(
                                                  color: colors.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : _sending
                                      ? Row(
                                          key: const ValueKey('sending'),
                                          children: [
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: GochanoSpacing.xs,
                                            ),
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
                                      : Row(
                                          key: const ValueKey('countdown'),
                                          children: [
                                            Icon(
                                              canResend
                                                  ? Icons.check_circle_outline_rounded
                                                  : Icons.timer_outlined,
                                              size: 16,
                                              color: canResend
                                                  ? colors.brand
                                                  : colors.textSecondary,
                                            ),
                                            const SizedBox(
                                              width: GochanoSpacing.xs,
                                            ),
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
                                                  color: canResend
                                                      ? colors.brand
                                                      : colors.textSecondary,
                                                  fontWeight: canResend
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          PrimaryButton(
                            label: _signingIn
                                ? GochanoLanguage.text(
                                    'Signing you in…',
                                    'সাইন ইন করা হচ্ছে…',
                                  )
                                : _verifying
                                ? GochanoLanguage.text('Verifying…', 'যাচাই হচ্ছে…')
                                : GochanoLanguage.text('Verify', 'যাচাই করুন'),
                            icon: Icons.check_circle_outline_rounded,
                            busy: _verifying || _signingIn,
                            busyLabel: _signingIn
                                ? GochanoLanguage.text(
                                    'Signing you in…',
                                    'সাইন ইন করা হচ্ছে…',
                                  )
                                : GochanoLanguage.text(
                                    'Verifying…',
                                    'যাচাই হচ্ছে…',
                                  ),
                            onPressed: (_verifying || _sending || _signingIn)
                                ? null
                                : _verify,
                          ),
                          const SizedBox(height: GochanoSpacing.sm),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            runSpacing: GochanoSpacing.xs,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                ),
                                onPressed: canResend ? _requestOtp : null,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  GochanoLanguage.text(
                                    'Resend code',
                                    'আবার কোড পাঠান',
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  GochanoLanguage.text(
                                    'Wrong number? Change number',
                                    'ভুল নম্বর? নম্বর পরিবর্তন করুন',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: GochanoSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpHero extends StatelessWidget {
  const _OtpHero({
    required this.colors,
    required this.type,
    required this.isDark,
    required this.compact,
    required this.maskedPhone,
  });

  final GochanoColors colors;
  final GochanoTypography type;
  final bool isDark;
  final bool compact;
  final String maskedPhone;

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 64.0 : 76.0;
    final iconSize = compact ? 32.0 : 40.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            color: isDark ? colors.surfaceVariant : colors.brandSoft,
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.brand.withValues(alpha: isDark ? 0.35 : 0.18),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.brand.withValues(alpha: isDark ? 0.25 : 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.mark_email_read_outlined,
              size: iconSize,
              color: colors.brand,
            ),
          ),
        ),
        SizedBox(height: compact ? GochanoSpacing.sm : GochanoSpacing.md),
        Text(
          GochanoLanguage.text(
            'Enter the verification code',
            'ভেরিফিকেশন কোড লিখুন',
          ),
          style: (compact ? type.cardHeading : type.pageTitle).copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Text(
          GochanoLanguage.text(
            'We sent a code to $maskedPhone. It may take a moment to arrive.',
            'আমরা $maskedPhone নম্বরে একটি কোড পাঠিয়েছি। '
                'কিছুক্ষণ সময় লাগতে পারে।',
          ),
          style: type.body.copyWith(
            color: colors.textSecondary,
            fontSize: compact ? 13.0 : 14.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: isDark ? colors.surfaceVariant : colors.brandSoft,
            borderRadius: GochanoRadius.smAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.phone_iphone_rounded,
                size: 14,
                color: colors.brand,
              ),
              const SizedBox(width: 4),
              Text(
                maskedPhone,
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontFamilyFallback: const ['Roboto', 'sans-serif'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.brand,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
