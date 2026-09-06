// Robi / Cirkle phone + OTP login.
//
// Single login surface for the whole app. The user only ever sees this
// screen + OtpVerifyScreen; Firebase is wired in under the hood so the
// existing Firestore rules/UID architecture keeps working without any
// changes.
//
// Flow (spec §3):
//   1. Student types a Bangladeshi mobile number.
//   2. We validate against ^01(?:6|8)\d{8}$ — Robi (016) and Cirkle
//      (018) only. Any other prefix fails immediately, no network.
//   3. We call TelecomAuthService.checkSubscription(phone):
//        - REGISTERED               -> home shell (no OTP)
//        - INITIAL CHARGING PENDING -> home shell (no OTP)
//        - anything else            -> OtpVerifyScreen
//   4. The home path goes through
//      exchangeSubscriptionForFirebaseSession + enterSession so
//      FirebaseAuth.currentUser is real and verified() in
//      firestore.rules passes. AuthGate refuses entry otherwise.
//
// The carrier endpoints (check_subscription.php / send_otp.php /
// verify_otp.php / unsubscribe.php) are hard-coded to the
// bdapps digital-apps base URL inside TelecomAuthService. The
// Firebase custom-token exchange goes to the FastAPI backend whose
// URL is provided by --dart-define=API_BASE_URL.

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
import '../../shell/presentation/gochano_shell.dart';
import 'otp_verify_screen.dart';
import 'profile_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.resumeMessage});

  /// When AuthGate bounces a stale session back here, this message is
  /// rendered above the form so the user understands why they were
  /// sent back. NULL on the normal first-time entry path.
  final String? resumeMessage;

  /// Path to the brand-master artwork shown at the top of the form.
  /// Kept here (and not as a magic string inside `_LoginHero`) so the
  /// widget stays easy to find when the branding team ships a new
  /// version of the artwork.
  static const String _kBrandAsset = 'assets/branding/gochano1.png';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _busy = false;
  String? _busyMessage;

  /// Transient acknowledgement banner shown above the hero as soon as
  /// the carrier reports the number as REGISTERED or
  /// INITIAL CHARGING PENDING. It is set during the
  /// `isAlreadySubscribed` branch of [_continue] and cleared again
  /// once the user leaves the screen, so it only flashes during the
  /// brief window between "we know you're already in" and "navigating
  /// to the shell".
  String? _acknowledgementMessage;

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
      if (mounted) setState(() => _busy = false);
      return;
    } catch (_) {
      _showError(GochanoLanguage.text(
        'Network error. Please check your connection and try again.',
        'নেটওয়ার্ক ত্রুটি। সংযোগ যাচাই করে আবার চেষ্টা করুন।',
      ));
      if (mounted) setState(() => _busy = false);
      return;
    }

    if (!mounted) return;

    if (result.isAlreadySubscribed) {
      // The carrier reports the number as already in a subscribed
      // state: REGISTERED (paying subscriber) or
      // INITIAL CHARGING PENDING (user tapped Subscribe, first charge
      // still settling). Spec §3 takes them straight into the home
      // shell with no OTP step.
      debugPrint('[LoginScreen] branch: REGISTERED_SHORTCUT → enter app');
      //
      // PART 16.1: we still have to mint a Firebase custom token via
      // the backend before the AuthGate will let us into GochanoShell.
      // The backend verifies the subscription server-side and mints
      // the token — it must NOT trust the client to claim it.
      if (mounted) {
        setState(() {
          _acknowledgementMessage = GochanoLanguage.text(
            'We see you\'re already subscribed — taking you in.',
            'আপনার সাবস্ক্রিপশন ইতোমধ্যে চালু আছে — সরাসরি ভেতরে নিয়ে যাচ্ছি।',
          );
          _busyMessage = GochanoLanguage.text(
            'Taking you in…',
            'ভেতরে নিয়ে যাচ্ছি…',
          );
        });
      }
      final TelecomFirebaseExchange exchange;
      try {
        exchange =
            await TelecomAuthService.exchangeSubscriptionForFirebaseSession(
          phone: phone,
          subscriptionStatus: result.rawStatus,
        );
      } on TelecomAuthException catch (e) {
        _showError(e.message);
        if (mounted) setState(() => _busy = false);
        return;
      } catch (_) {
        _showError(GochanoLanguage.text(
          'Could not link your number to Gochano. Please try again later.',
          'আপনার নম্বর Gochano-তে সংযুক্ত করা যায়নি। কিছুক্ষণ পর আবার চেষ্টা করুন।',
        ));
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      try {
        await TelecomAuthService.enterSession(
          phone: phone,
          exchange: exchange,
        );
      } on TelecomAuthException catch (e) {
        _showError(e.message);
        if (mounted) setState(() => _busy = false);
        return;
      } catch (_) {
        _showError(GochanoLanguage.text(
          'Could not sign you in. Please try again.',
          'সাইন ইন করা যায়নি। আবার চেষ্টা করুন।',
        ));
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      final hasProfile = await FirestoreService.hasProfile();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => hasProfile
              ? GochanoShell(
                  role: 'student',
                  displayName: phone,
                )
              : ProfileSetupScreen(phone: phone),
        ),
        (_) => false,
      );
      return;
    }

    // Not subscribed yet — drop into the OTP screen.
    debugPrint('[LoginScreen] branch: SEND_OTP → navigate to OTP screen');
    if (mounted) setState(() => _busy = false);
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
      // No app bar — this is the first impression of the product; the
      // brand plate IS the header.
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  GochanoSpacing.lg,
                  GochanoSpacing.md,
                  GochanoSpacing.lg,
                  GochanoSpacing.lg,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight -
                        GochanoSpacing.md -
                        GochanoSpacing.lg,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: GochanoSpacing.lg),
                        if (_acknowledgementMessage != null) ...[
                          AppCard(
                            accent: colors.brand,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  color: colors.brand,
                                ),
                                const SizedBox(width: GochanoSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _acknowledgementMessage!,
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
                        // Brand plate + title sit a little above the
                        // vertical centre: the Spacer pushes the form
                        // down so the eye lands on the logo first,
                        // then falls naturally into the phone field.
                        _LoginHero(colors: colors, type: type),
                        const Spacer(),
                        if (widget.resumeMessage != null) ...[
                          AppCard(
                            accent: colors.brand,
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
                                    color: colors.brand,
                                  ),
                                  filled: true,
                                  fillColor: colors.surfaceVariant,
                                  border: const OutlineInputBorder(
                                    borderRadius: GochanoRadius.mdAll,
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: GochanoRadius.mdAll,
                                    borderSide: BorderSide(
                                      color: colors.brand,
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                                validator: _validatePhone,
                                onFieldSubmitted: (_) => _continue(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: GochanoSpacing.md),
                        Text(
                          GochanoLanguage.text(
                            'Daily charge 2.78 BDT (incl. VAT, SD & SC). '
                            'Robi (016) and Cirkle (018) only.',
                            'প্রতিদিন ২.৭৮ টাকা (VAT, SD ও SC সহ)। '
                            'শুধু Robi (০১৬) ও Cirkle (০১৮)।',
                          ),
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: GochanoSpacing.lg),
                        PrimaryButton(
                          label: _busy
                              ? (_busyMessage ??
                                  GochanoLanguage.text(
                                      'Please wait…', 'অপেক্ষা করুন…'))
                              : GochanoLanguage.text(
                                  'Continue', 'চালিয়ে যান'),
                          onPressed: _busy ? null : _continue,
                          icon: Icons.arrow_forward_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Brand plate at the top of the sign-in form: rounded-square badge
/// holding the product artwork, the product name, and a tagline. Kept
/// as its own widget so this header can be reused by any "first-run"
/// or "logged-out" experience that wants the same hero block.
class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.colors, required this.type});

  final GochanoColors colors;
  final GochanoTypography type;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: colors.brandSoft,
            borderRadius: GochanoRadius.xlAll,
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Image.asset(
            LoginScreen._kBrandAsset,
            width: 72,
            height: 72,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Icon(
              Icons.apps_rounded,
              size: 48,
              color: colors.brand,
            ),
          ),
        ),
        const SizedBox(height: GochanoSpacing.md),
        Text(
          'Gochano',
          style: type.pageTitle.copyWith(color: colors.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Text(
          GochanoLanguage.text(
            'One place for everything',
            'এক জায়গায় সব কিছু',
          ),
          style: type.bodySecondary.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
