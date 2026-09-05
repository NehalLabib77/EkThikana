// Robi / Cirkle phone + OTP login.
//
// Replaces the previous Firebase email/password login screen. The flow is:
//
//   1. The student types their Bangladeshi mobile number.
//   2. We validate it against `^01(?:6|8)\d{8}$` — only 016 (Robi) and 018
//      (Cirkle) prefixes are accepted (spec §3). Any other prefix fails
//      validation immediately; we never call the network.
//   3. We call `TelecomAuthService.checkSubscription(phone)` and branch on
//      the response:
//          - REGISTERED              -> home (no OTP)
//          - INITIAL CHARGING PENDING -> home (no OTP)
//          - anything else           -> OTP verification screen
//   4. The student never sees email/password/registration fields.

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
import 'otp_verify_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.resumeMessage});

  /// When AuthGate bounces a stale session back here, this message is
  /// rendered at the top of the form so the user understands why they
  /// were sent back to the login screen. NULL on the normal first-time
  /// entry path.
  final String? resumeMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _busy = false;
  String? _busyMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final phone = _phoneController.text.trim();

    setState(() {
      _busy = true;
      _busyMessage = GochanoLanguage.text(
        'Checking your subscription…',
        'সাবস্ক্রিপশন যাচাই হচ্ছে…',
      );
    });

    final TelecomSubscriptionResult result;
    try {
      result = await TelecomAuthService.checkSubscription(phone);
    } on TelecomAuthException catch (e) {
      _showError(e.message);
      return;
    } catch (_) {
      _showError(GochanoLanguage.text(
        'Network error. Please check your connection and try again.',
        'নেটওয়ার্ক ত্রুটি। সংযোগ যাচাই করে আবার চেষ্টা করুন।',
      ));
      return;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }

    if (!mounted) return;

    if (result.shouldEnterApp) {
      // PART 16.1: even for the "no OTP" branches
      // (REGISTERED / INITIAL CHARGING PENDING) we still need to mint
      // a Firebase custom token via the backend before the AuthGate
      // will let us into GochanoShell. The backend verifies the
      // subscription server-side and mints the token.
      final TelecomFirebaseExchange exchange;
      try {
        exchange =
            await TelecomAuthService.exchangeSubscriptionForFirebaseSession(
          phone: phone,
          subscriptionStatus: result.rawStatus,
        );
      } on TelecomAuthException catch (e) {
        _showError(e.message);
        return;
      } catch (_) {
        _showError(GochanoLanguage.text(
          'Could not link your number to Gochano. Please try again later.',
          'আপনার নম্বর Gochano-তে সংযুক্ত করা যায়নি। কিছুক্ষণ পর আবার চেষ্টা করুন।',
        ));
        return;
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _busyMessage = null;
          });
        }
      }
      if (!mounted) return;
      try {
        await TelecomAuthService.enterSession(
          phone: phone,
          exchange: exchange,
        );
      } on TelecomAuthException catch (e) {
        _showError(e.message);
        return;
      } catch (_) {
        _showError(GochanoLanguage.text(
          'Could not sign you in. Please try again.',
          'সাইন ইন করা যায়নি। আবার চেষ্টা করুন।',
        ));
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => GochanoShell(
            role: 'student',
            displayName: phone,
          ),
        ),
        (_) => false,
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerifyScreen(phone: phone),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _validatePhone(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return GochanoLanguage.text(
        'Enter your mobile number',
        'মোবাইল নম্বর লিখুন',
      );
    }
    if (!TelecomAuthService.isSupportedPhone(raw)) {
      return GochanoLanguage.text(
        'Only Robi (016) and Cirkle (018) numbers are supported',
        'শুধুমাত্র Robi (০১৬) ও Cirkle (০১৮) নম্বর সমর্থিত',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Sign in', 'সাইন ইন'),
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
              if (widget.resumeMessage != null) ...[
                AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: colors.brand,
                      ),
                      const SizedBox(width: GochanoSpacing.sm),
                      Expanded(
                        child: Text(
                          widget.resumeMessage!,
                          style: type.body.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GochanoSpacing.md),
              ],
              SectionHeader(
                title: GochanoLanguage.text(
                  'Continue with your mobile number',
                  'মোবাইল নম্বর দিয়ে চালিয়ে যান',
                ),
                subtitle: GochanoLanguage.text(
                  'Gochano works with Robi (016) and Cirkle (018) '
                  'subscriptions.',
                  'Gochano Robi (০১৬) এবং Cirkle (০১৮) সাবস্ক্রিপশনের '
                  'সাথে কাজ করে।',
                ),
              ),
              const SizedBox(height: GochanoSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      GochanoLanguage.text(
                        'Mobile number',
                        'মোবাইল নম্বর',
                      ),
                      style: type.cardHeading.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: GochanoSpacing.xs),
                    TextFormField(
                      controller: _phoneController,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: InputDecoration(
                        hintText: '01XXXXXXXXX',
                        prefixIcon: Icon(
                          Icons.phone_outlined,
                          color: colors.textSecondary,
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: GochanoRadius.smAll,
                        ),
                      ),
                      validator: _validatePhone,
                      onFieldSubmitted: (_) => _continue(),
                    ),
                    const SizedBox(height: GochanoSpacing.sm),
                    Text(
                      GochanoLanguage.text(
                        'Example: 01612345678 or 01812345678',
                        'উদাহরণ: ০১৬১২৩৪৫৬৭৮ অথবা ০১৮১২৩৪৫৬৭৮',
                      ),
                      style: type.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GochanoSpacing.lg),
              PrimaryButton(
                label: _busy
                    ? (_busyMessage ??
                        GochanoLanguage.text(
                            'Please wait…', 'অপেক্ষা করুন…'))
                    : GochanoLanguage.text('Continue', 'চালিয়ে যান'),
                onPressed: _busy ? null : _continue,
                icon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(height: GochanoSpacing.md),
              Text(
                GochanoLanguage.text(
                  'By continuing you confirm you are the owner of this '
                  'Robi or Cirkle subscription.',
                  'চালিয়ে যাওয়ার মাধ্যমে আপনি নিশ্চিত করছেন যে এই Robi '
                  'বা Cirkle সাবস্ক্রিপশনের মালিক আপনি।',
                ),
                style: type.caption.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
