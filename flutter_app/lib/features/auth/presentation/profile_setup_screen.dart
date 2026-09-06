import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/firestore_service.dart';
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
      setState(() => _errorText = GochanoLanguage.text(
            'Session expired. Please sign in again.',
            'সেশন শেষ হয়ে গেছে। আবার সাইন ইন করুন।',
          ));
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final name = _nameController.text.trim();

      // Idempotent write using merge: never overwrites existing non-empty
      // fields. Matches the canonical users/{uid} schema used by
      // AuthService.register() and FirestoreService.updateProfile().
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'displayName': name,
          'phone': widget.phone,
          'role': 'student',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Refresh profile state so the rest of the app picks up the new doc.
      await FirestoreService.profile();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => GochanoShell(
            role: 'student',
            displayName: name,
          ),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = GochanoLanguage.text(
          'Could not save your profile. Please try again.',
          'আপনার প্রোফাইল সেভ করা যায়নি। আবার চেষ্টা করুন।',
        );
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
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
                            padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
                            child: LanguageToggle(),
                          ),
                        ),
                        const SizedBox(height: GochanoSpacing.xl),
                        Text(
                          GochanoLanguage.text(
                            'Complete your profile',
                            'আপনার প্রোফাইল সম্পূর্ণ করুন',
                          ),
                          style: type.pageTitle.copyWith(
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: GochanoSpacing.sm),
                        Text(
                          GochanoLanguage.text(
                            'Just one quick step to get started.',
                            'শুরু করতে শুধু একটি ছোট ধাপ।',
                          ),
                          style: type.body.copyWith(
                            color: colors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: GochanoSpacing.xl),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                GochanoLanguage.text(
                                  'Full name',
                                  'পুরো নাম',
                                ),
                                style: type.cardHeading.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: GochanoSpacing.sm),
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _save(),
                                decoration: InputDecoration(
                                  hintText: GochanoLanguage.text(
                                    'e.g. Rahat Hossain',
                                    'যেমন রাহাত হোসেন',
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
                                  'Phone number',
                                  'ফোন নম্বর',
                                ),
                                style: type.cardHeading.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: GochanoSpacing.sm),
                              TextFormField(
                                initialValue: widget.phone,
                                readOnly: true,
                                style: const TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontFamilyFallback: ['Roboto', 'sans-serif'],
                                  letterSpacing: 1.2,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.phone_outlined,
                                    color: colors.textSecondary,
                                    size: GochanoSizes.iconSm,
                                  ),
                                ),
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
                                  'Role',
                                  'ভূমিকা',
                                ),
                                style: type.cardHeading.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: GochanoSpacing.sm),
                              TextFormField(
                                initialValue: GochanoLanguage.text(
                                  'Student',
                                  'ছাত্র',
                                ),
                                readOnly: true,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.school_outlined,
                                    color: colors.textSecondary,
                                    size: GochanoSizes.iconSm,
                                  ),
                                ),
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
                                ),
                                const SizedBox(width: GochanoSpacing.sm),
                                Expanded(
                                  child: Text(
                                    _errorText!,
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
                        PrimaryButton(
                          label: GochanoLanguage.text(
                            'Continue',
                            'চালিয়ে যান',
                          ),
                          icon: Icons.arrow_forward_rounded,
                          busy: _saving,
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
    );
  }
}
