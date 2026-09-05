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
//   * On success we persist the session and pop the entire auth stack so
//     the user lands on the home shell (and so the Back button does not
//     return them to OTP).
//   * On failure we keep them on this screen with an inline error.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/services/telecom_auth_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../shell/presentation/gochano_shell.dart';

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
          exchange =
              await TelecomAuthService.exchangeOtpForFirebaseSession(
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
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => GochanoShell(
              role: 'student',
              displayName: widget.phone,
            ),
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

    final canResend = _remaining <= Duration.zero && !_sending;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          'Verify your number',
          'নম্বর যাচাই করুন',
        ),
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
                    : GochanoLanguage.text('Verify', 'যাচাই করুন'),
                onPressed: (_verifying || _sending) ? null : _verify,
                icon: Icons.check_circle_outline_rounded,
              ),
              const SizedBox(height: GochanoSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed:
                        _sending || _verifying ? null : _requestOtp,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      GochanoLanguage.text(
                        'Resend code',
                        'আবার কোড পাঠান',
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      GochanoLanguage.text(
                        'Wrong number? Change number',
                        'ভুল নম্বর? নম্বর পরিবর্তন করুন',
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
