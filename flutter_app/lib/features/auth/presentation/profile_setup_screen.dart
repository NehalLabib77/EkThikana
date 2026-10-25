import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/app_design_system.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import '../../shell/presentation/gochano_shell.dart';

/// One-time profile completion screen shown after telecom authentication
/// when the current Firebase UID has no existing `users/{uid}` document
/// (or the document has no `displayName`).
///
/// This covers two scenarios:
///   A. Already REGISTERED users logging in for the first time on this device.
///   B. Newly OTP-verified users who just completed carrier verification.
///
/// The screen is idempotent — if a profile already exists, it should
/// never be shown (the caller is responsible for that check).
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.phone});

  /// The verified telecom phone number, read-only on this screen.
  final String phone;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(
        () => _errorText = GochanoLanguage.text(
          'Session expired. Please sign in again.',
          'সেশন শেষ হয়ে গেছে। আবার সাইন ইন করুন।',
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      // In DEBUG only, check and log token claims safely
      if (kDebugMode) {
        try {
          final idTokenResult = await user.getIdTokenResult(true);
          final claims = idTokenResult.claims ?? {};
          final emailVerified =
              claims['email_verified'] == true || user.emailVerified;
          final telecomVerified = claims['telecom_verified'] == true;
          debugPrint(
            '[ProfileSetup] token claims: '
            'uid=${user.uid} '
            'email_verified=$emailVerified '
            'telecom_verified=$telecomVerified',
          );
        } catch (claimErr) {
          debugPrint('[ProfileSetup] claim check failed: $claimErr');
        }
      }

      final name = _nameController.text.trim();

      // Idempotent write using merge: never overwrites existing non-empty
      // fields. Matches the canonical users/{uid} schema used by
      // AuthService.register() and FirestoreService.updateProfile().
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': name,
        'phone': widget.phone,
        'role': 'student',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Refresh profile state so the rest of the app picks up the new doc.
      await FirestoreService.profile();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => GochanoShell(role: 'student', displayName: name),
        ),
        (_) => false,
      );
    } catch (e) {
      if (kDebugMode) {
        if (e is FirebaseException) {
          debugPrint(
            '[ProfileSetup] save failed: '
            'plugin=${e.plugin} '
            'code=${e.code} '
            'message=${e.message} '
            'target=users/${user.uid}',
          );
        } else {
          debugPrint('[ProfileSetup] save failed: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _errorText = friendlyErrorMessage(
          e,
          fallback: GochanoLanguage.text(
            'Could not save your profile. Please try again.',
            'আপনার প্রোফাইল সেভ করা যায়নি। আবার চেষ্টা করুন।',
          ),
        );
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GochanoScaffold(
      padBody: false,
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
                          Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: isNarrow ? 0 : GochanoSpacing.xs,
                                bottom: GochanoSpacing.xs,
                              ),
                              child: const LanguageToggle(),
                            ),
                          ),
                          SizedBox(
                            height: isNarrow
                                ? GochanoSpacing.sm
                                : GochanoSpacing.md,
                          ),
                          _ProfileHero(
                            colors: colors,
                            type: type,
                            isDark: isDark,
                            compact: isNarrow,
                          ),
                          const Spacer(),
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  GochanoLanguage.text('Full name', 'পূর্ণ নাম'),
                                  style: type.cardHeading.copyWith(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: GochanoSpacing.sm),
                                TextFormField(
                                  controller: _nameController,
                                  enabled: !_saving,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _save(),
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: GochanoLanguage.text(
                                      'e.g. Rahat Hossain',
                                      'যেমন রাহাত হোসেন',
                                    ),
                                    hintStyle: TextStyle(
                                      color: colors.textSecondary.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 15,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Icon(
                                        Icons.person_rounded,
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
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return GochanoLanguage.text(
                                        'Please enter your name',
                                        'আপনার নাম লিখুন',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: GochanoSpacing.md),
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  GochanoLanguage.text(
                                    'Account type',
                                    'অ্যাকাউন্টের ধরন',
                                  ),
                                  style: type.cardHeading.copyWith(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: GochanoSpacing.sm),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? colors.surfaceVariant
                                            : colors.brandSoft,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.school_outlined,
                                        color: colors.brand,
                                        size: GochanoSizes.iconSm,
                                      ),
                                    ),
                                    const SizedBox(width: GochanoSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        GochanoLanguage.text(
                                          'Student',
                                          'শিক্ষার্থী',
                                        ),
                                        style: type.body.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? colors.surfaceVariant
                                            : colors.brandSoft,
                                        borderRadius: GochanoRadius.smAll,
                                        border: Border.all(
                                          color: colors.brand.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        GochanoLanguage.text('Default', 'ডিফল্ট'),
                                        style: type.caption.copyWith(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: colors.brand,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (_errorText != null) ...[
                            AppCard(
                              accent: colors.error,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: colors.error,
                                    size: 20,
                                  ),
                                  const SizedBox(width: GochanoSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      _errorText!,
                                      style: type.body.copyWith(
                                        color: colors.textPrimary,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: GochanoSpacing.md),
                          ],
                          PrimaryButton(
                            label: GochanoLanguage.text(
                              'Continue',
                              'চালিয়ে যান',
                            ),
                            icon: Icons.arrow_forward_rounded,
                            busy: _saving,
                            busyLabel: GochanoLanguage.text(
                              'Saving profile…',
                              'প্রোফাইল সেভ হচ্ছে…',
                            ),
                            onPressed: _save,
                          ),
                          const SizedBox(height: GochanoSpacing.lg),
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

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.colors,
    required this.type,
    required this.isDark,
    this.compact = false,
  });

  final GochanoColors colors;
  final GochanoTypography type;
  final bool isDark;
  final bool compact;

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
              Icons.person_rounded,
              size: iconSize,
              color: colors.brand,
            ),
          ),
        ),
        SizedBox(height: compact ? GochanoSpacing.sm : GochanoSpacing.md),
        Text(
          GochanoLanguage.text(
            'Complete your profile',
            'আপনার প্রোফাইল সম্পূর্ণ করুন',
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
            'Just one quick step to get started.',
            'শুরু করতে শুধু একটি ছোট ধাপ।',
          ),
          style: type.body.copyWith(
            color: colors.textSecondary,
            fontSize: compact ? 13.0 : 14.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
