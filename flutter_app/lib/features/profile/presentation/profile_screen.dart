// Profile (spec §72).
//
// Grouped into the sections the spec names: Account, Money, Statistics,
// Language, Appearance, Notifications, Privacy, Data, About.
//
// Developer configuration is deliberately absent — spec §72 says "Do not
// expose developer configuration to normal users", so the API base URL, the
// Firebase project id and the build flags are not surfaced here.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/settings/gochano_appearance.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/notification_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../life/presentation/expense/monthly_budget_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Profile', 'প্রোফাইল'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _AccountCard(role: role),

          if (role == 'student') ...[
            SectionHeader(title: GochanoLanguage.text('Study', 'পড়াশোনা')),
            const _StudyStatsCard(),
            SectionHeader(title: GochanoLanguage.text('Money', 'টাকা')),
            const _MoneySection(),
          ],

          SectionHeader(
            title: GochanoLanguage.text('Language', 'ভাষা'),
          ),
          const _LanguageSection(),

          SectionHeader(
            title: GochanoLanguage.text('Appearance', 'চেহারা'),
          ),
          const _AppearanceSection(),

          SectionHeader(
            title: GochanoLanguage.text('Notifications', 'নোটিফিকেশন'),
          ),
          const _NotificationsSection(),

          SectionHeader(
            title: GochanoLanguage.text('Privacy and data', 'গোপনীয়তা ও ডেটা'),
          ),
          const _PrivacySection(),

          SectionHeader(title: GochanoLanguage.text('About', 'সম্পর্কে')),
          const _AboutSection(),

          const SizedBox(height: GochanoSpacing.md),
          SecondaryButton(
            label: GochanoLanguage.text('Sign out', 'সাইন আউট'),
            icon: Icons.logout_rounded,
            onPressed: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.profileStream(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name = data['displayName']?.toString() ?? '';
        final email = data['email']?.toString() ?? '';
        final university = data['university']?.toString() ?? '';
        final department = data['department']?.toString() ?? '';

        return AppCard(
          child: Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureProfile,
                accent: colors.brand,
                plateSize: 56,
              ),
              const SizedBox(width: GochanoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty
                          ? GochanoLanguage.text('Your account', 'আপনার অ্যাকাউন্ট')
                          : name,
                      style: context.type.sectionHeading,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: context.type.bodySecondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (university.isNotEmpty || department.isNotEmpty)
                      Text(
                        [university, department]
                            .where((e) => e.isNotEmpty)
                            .join(' · '),
                        style: context.type.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: GochanoSpacing.xs),
                    GochanoBadge(
                      label: role == 'student'
                          ? GochanoLanguage.text('Student account', 'শিক্ষার্থী অ্যাকাউন্ট')
                          : GochanoLanguage.text('General account', 'সাধারণ অ্যাকাউন্ট'),
                      tone: GochanoBadgeTone.brand,
                      icon: Icons.verified_user_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Study statistics
// ---------------------------------------------------------------------------

class _StudyStatsCard extends StatefulWidget {
  const _StudyStatsCard();

  @override
  State<_StudyStatsCard> createState() => _StudyStatsCardState();
}

class _StudyStatsCardState extends State<_StudyStatsCard> {
  Map<String, dynamic>? _stats;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await ApiService.getStudyStats();
      if (mounted) setState(() => _stats = stats);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) {
      return ErrorState(compact: true, message: _error, onRetry: _load);
    }
    if (_stats == null) {
      return StaticLoadingState(
        compact: true,
        message: GochanoLanguage.text(
          'Loading your study stats…',
          'আপনার পড়ার পরিসংখ্যান লোড হচ্ছে…',
        ),
      );
    }

    int read(String camel, String snake) {
      final raw = _stats![camel] ?? _stats![snake];
      return raw is num ? raw.toInt() : 0;
    }

    final todayMinutes = (read('todaySeconds', 'today_seconds') / 60).round();
    final monthMinutes = (read('monthSeconds', 'month_seconds') / 60).round();
    final streak = read('streakDays', 'streak_days');

    return Row(
      children: [
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Focus today', 'আজ ফোকাস'),
            value: GochanoLanguage.text('$todayMinutes min', '$todayMinutes মি'),
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('This month', 'এই মাস'),
            value: GochanoLanguage.text('$monthMinutes min', '$monthMinutes মি'),
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Streak', 'ধারাবাহিকতা'),
            value: GochanoLanguage.text('$streak d', '$streak দি'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

class _MoneySection extends StatelessWidget {
  const _MoneySection();

  @override
  Widget build(BuildContext context) {
    return CardGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(GochanoLanguage.text('Monthly money', 'মাসিক টাকা')),
          subtitle: Text(
            GochanoLanguage.text(
              'How much you have to spend this month.',
              'এই মাসে আপনার কাছে কত টাকা আছে।',
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showMonthlyBudgetSheet(context),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Language
// ---------------------------------------------------------------------------

class _LanguageSection extends StatelessWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context) {
    return RadioGroup<GochanoLocale>(
      groupValue: GochanoLanguage.current.value,
      onChanged: (value) {
        if (value != null) GochanoLanguage.select(value);
      },
      child: CardGroup(
        children: [
          for (final locale in GochanoLocale.values)
            RadioListTile<GochanoLocale>(
              value: locale,
              // Each language names itself in its own script, so a student
              // who cannot read the other one can still pick correctly.
              title: Text(locale.nativeName),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    return RadioGroup<ThemeMode>(
      groupValue: GochanoAppearance.mode.value,
      onChanged: (value) {
        if (value != null) GochanoAppearance.select(value);
      },
      child: CardGroup(
        children: [
          for (final entry in <(ThemeMode, String, String, IconData)>[
          (
            ThemeMode.system,
            GochanoLanguage.text('Follow system', 'সিস্টেম অনুযায়ী'),
            GochanoLanguage.text(
              'Matches your phone setting.',
              'আপনার ফোনের সেটিং অনুসরণ করে।',
            ),
            Icons.brightness_auto_outlined,
          ),
          (
            ThemeMode.light,
            GochanoLanguage.text('Light', 'উজ্জ্বল'),
            '',
            Icons.light_mode_outlined,
          ),
          (
            ThemeMode.dark,
            GochanoLanguage.text('Dark', 'অন্ধকার'),
            '',
            Icons.dark_mode_outlined,
          ),
        ])
            RadioListTile<ThemeMode>(
              value: entry.$1,
              secondary: Icon(entry.$4),
              title: Text(entry.$2),
              subtitle: entry.$3.isEmpty ? null : Text(entry.$3),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection();

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final enabled = await NotificationService.areNotificationsEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = _enabled;

    return CardGroup(
      children: [
        ListTile(
          leading: Icon(
            enabled == false
                ? Icons.notifications_off_outlined
                : Icons.notifications_active_outlined,
            color: enabled == false ? colors.warning : null,
          ),
          title: Text(
            GochanoLanguage.text('Reminders', 'রিমাইন্ডার'),
          ),
          subtitle: Text(
            switch (enabled) {
              // Says plainly that reminders will not fire, rather than
              // leaving a student to discover it when a dose is missed.
              false => GochanoLanguage.text(
                  'Turned off in system settings. Medicine and task reminders '
                  'will not appear.',
                  'সিস্টেম সেটিংসে বন্ধ। ওষুধ ও কাজের রিমাইন্ডার দেখা যাবে না।',
                ),
              true => GochanoLanguage.text(
                  'Medicine and task reminders are on.',
                  'ওষুধ ও কাজের রিমাইন্ডার চালু আছে।',
                ),
              null => GochanoLanguage.text('Checking…', 'দেখা হচ্ছে…'),
            },
          ),
          trailing: enabled == false
              ? TextButton(
                  onPressed: () async {
                    await NotificationService.openNotificationSettings();
                    await _check();
                  },
                  child: Text(GochanoLanguage.text('Enable', 'চালু করুন')),
                )
              : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy and data
// ---------------------------------------------------------------------------

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    return CardGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(GochanoLanguage.text('Export my data', 'আমার ডেটা এক্সপোর্ট')),
          subtitle: Text(
            GochanoLanguage.text(
              'A copy of what Gochano stores about you.',
              'গোছানো আপনার সম্পর্কে যা সংরক্ষণ করে তার একটি কপি।',
            ),
          ),
          onTap: () => _export(context),
        ),
        ListTile(
          leading: Icon(
            Icons.delete_forever_outlined,
            color: context.colors.error,
          ),
          title: Text(
            GochanoLanguage.text('Delete my account', 'আমার অ্যাকাউন্ট মুছুন'),
            style: TextStyle(color: context.colors.error),
          ),
          subtitle: Text(
            GochanoLanguage.text(
              'Permanently removes your account, files and records.',
              'আপনার অ্যাকাউন্ট, ফাইল ও রেকর্ড স্থায়ীভাবে মুছে ফেলে।',
            ),
          ),
          onTap: () => _deleteAccount(context),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return CardGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: Text(AppConfig.appName),
          subtitle: Text(
            GochanoLanguage.text(
              'Organize study and daily life in one place.',
              'পড়াশোনা ও দৈনন্দিন জীবন এক জায়গায় গুছিয়ে রাখুন।',
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

Future<void> _export(BuildContext context) async {
  try {
    final data = await ApiService.exportAccount();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(GochanoLanguage.text('Your data', 'আপনার ডেটা')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              data.entries.map((e) => '${e.key}: ${e.value}').join('\n\n'),
              style: context.type.bodySecondary,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(GochanoLanguage.text('Close', 'বন্ধ')),
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _deleteAccount(BuildContext context) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text(
      'Delete your account?',
      'আপনার অ্যাকাউন্ট মুছবেন?',
    ),
    message: GochanoLanguage.text(
      'This permanently removes your account, uploaded files, expenses, '
      'medicines and study records. It cannot be undone.',
      'এটি আপনার অ্যাকাউন্ট, আপলোড করা ফাইল, খরচ, ওষুধ ও পড়াশোনার রেকর্ড স্থায়ীভাবে মুছে ফেলবে। এটি ফেরানো যাবে না।',
    ),
    confirmLabel: GochanoLanguage.text('Delete everything', 'সবকিছু মুছুন'),
  );
  if (!confirmed || !context.mounted) return;
  try {
    await ApiService.deleteAccount();
    await AuthService.logout();
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _signOut(BuildContext context) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Sign out?', 'সাইন আউট করবেন?'),
    message: GochanoLanguage.text(
      'Your data stays safe and will be here when you sign back in.',
      'আপনার ডেটা নিরাপদ থাকবে এবং আবার সাইন ইন করলে ফিরে পাবেন।',
    ),
    confirmLabel: GochanoLanguage.text('Sign out', 'সাইন আউট'),
    destructive: false,
  );
  if (!confirmed) return;
  await AuthService.logout();
}
