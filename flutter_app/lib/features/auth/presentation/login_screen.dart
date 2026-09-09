// Robi / Cirkle phone + OTP login.
//
// Single login surface for the whole app. The user only ever sees this
// screen + OtpVerifyScreen; Firebase is wired in under the hood so the
// existing Firestore rules/UID architecture keeps working without any
// changes.
//
// Flow (spec §3):
//   1. Student types a Bangladeshi mobile number.
//   2. We validate against ^01(?:6|8)\d{8}$ — Robi (018) and Cirkle
//      (016) only. Any other prefix fails immediately, no network.
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
import 'otp_verify_screen.dart';
import 'profile_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

      // PART 30: Clear the recentlyVerified marker on successful
      // REGISTERED login since we're now signing in.
      await TelecomAuthService.clearRecentlyVerified();

      final TelecomFirebaseExchange exchange;
      try {
        debugPrint('[AuthFlow] subscriptionStatus=REGISTERED');
        debugPrint('[AuthFlow] exchange started');
        exchange =
            await TelecomAuthService.exchangeSubscriptionForFirebaseSession(
          phone: phone,
          subscriptionStatus: result.rawStatus,
        );
        debugPrint('[AuthFlow] exchange status=200');
        debugPrint('[AuthFlow] customTokenPresent=${exchange.customToken.isNotEmpty}');
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
        debugPrint('[AuthFlow] firebase signIn started');
        await TelecomAuthService.enterSession(
          phone: phone,
          exchange: exchange,
        );
        debugPrint('[AuthFlow] firebase user=${FirebaseAuth.instance.currentUser?.uid ?? 'null'}');
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

      // SAFETY: Verify Firebase user actually exists before profile lookup.
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('[AuthFlow] FAIL: currentUser is null after enterSession');
        _showError(GochanoLanguage.text(
          'Sign-in incomplete. Please try again.',
          'সাইন-ইন সম্পন্ন হয়নি। আবার চেষ্টা করুন।',
        ));
        if (mounted) setState(() => _busy = false);
        return;
      }
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

      if (profileState == ProfileCheckResult.error) {
        _showError(GochanoLanguage.text(
          'Could not load your profile. Please try again.',
          'আপনার প্রোফাইল লোড করা যায়নি। আবার চেষ্টা করুন।',
        ));
        if (mounted) setState(() => _busy = false);
        return;
      }

      // Destination is resolved — show "Taking you in" for ~1.2s
      // ONLY after all auth + profile work is complete.
      if (mounted) {
        setState(() {
          _acknowledgementMessage = GochanoLanguage.text(
            'We see you\'re already subscribed — taking you in.',
            'আপনার সাবস্ক্রিপশন ইতোমধ্যে চালু আছে — সরাসরি ভেতরে নিয়ে যাচ্ছি।',
          );
          _busyMessage = GochanoLanguage.text(
            'Taking you in…',
            'আপনাকে প্রবেশ করানো হচ্ছে…',
          );
        });
      }
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
                displayName: phone,
              ),
            ),
            (_) => false,
          );
        case ProfileCheckResult.missing:
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => ProfileSetupScreen(phone: phone),
            ),
            (_) => false,
          );
        case ProfileCheckResult.error:
          // Already handled above — unreachable.
          break;
      }
      return;
    }

    // PART 30: Propagation guard — if the same phone was recently
    // OTP-verified and subscription is still NOT SUBSCRIBED, the
    // carrier may be propagating. Show a message instead of resending OTP.
    if (!result.isAlreadySubscribed) {
      final recentPhone = await TelecomAuthService.readRecentlyVerifiedPhone();
      final normalizedInput = TelecomAuthService.normalize(phone);
      if (recentPhone != null && recentPhone == normalizedInput) {
        // Same phone was recently verified — carrier propagation delay
        debugPrint('[LoginScreen] branch: PROPAGATION_GUARD → subscription activating');
        if (mounted) {
          setState(() {
            _busy = false;
            _acknowledgementMessage = GochanoLanguage.text(
              'Subscription is activating. Please try again in a moment.',
              'সাবস্ক্রিপশন সক্রিয় হচ্ছে। একটু পরে আবার চেষ্টা করুন।',
            );
          });
        }
        return;
      }
    }

    // Not subscribed yet — drop into the OTP screen.
    debugPrint('[LoginScreen] branch: SEND_OTP → navigate to OTP screen');
    if (!mounted) return;
    setState(() => _busy = false);
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
        'Only Robi (018) and Cirkle (016) numbers are supported',
        'শুধুমাত্র Robi (০১৮) ও Cirkle (০১৬) নম্বর সমর্থিত',
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
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: GochanoSpacing.xs),
                            child: LanguageToggle(),
                          ),
                        ),
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
                                style: const TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontFamilyFallback: ['Roboto', 'sans-serif'],
                                  letterSpacing: 1.2,
                                  fontSize: 16,
                                ),
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
                            'Robi (018) and Cirkle (016) only.',
                            'প্রতিদিন ২.৭৮ টাকা (VAT, SD ও SC সহ)। '
                            'শুধু Robi (০১৮) ও Cirkle (০১৬)।',
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
            semanticLabel: GochanoLanguage.text(
              'Gochano logo',
              'গোচানো লোগো',
            ),
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
            'Your student life, organized.',
            'আপনার ছাত্রজীবন, সুশৃঙ্খল।',
          ),
          style: type.bodySecondary.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
