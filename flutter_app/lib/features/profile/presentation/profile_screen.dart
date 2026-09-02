// Profile (spec §72).
//
// One identity header, one statistics row, one settings card, and the two
// things that need standing apart: deleting the account, and signing out.
//
// The screen used to be seven titled sections, each its own card, with
// Language and Appearance expanded as full radio lists. That made a settings
// screen the tallest page in the app, and buried "Monthly money" — the one
// row a student actually opens — under a fold of theme options. Language and
// Appearance now open the selectors they always had; the row shows the
// current choice so nothing is hidden by collapsing it.
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
          const _IdentityHeader(),
          _RoleBadge(role: role),

          if (role == 'student') ...[
            SectionHeader(title: GochanoLanguage.text('Study', 'পড়াশোনা')),
            const _StudyStatsRow(),
          ],

          const SizedBox(height: GochanoSpacing.lg),
          _SettingsCard(isStudent: role == 'student'),

          const SizedBox(height: GochanoSpacing.md),
          const _DangerCard(),

          const SizedBox(height: GochanoSpacing.md),
          const _AboutCard(),

          const SizedBox(height: GochanoSpacing.lg),
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
// Identity
// ---------------------------------------------------------------------------

/// Avatar, name, email and where the student studies.
class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.profileStream(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name = data['displayName']?.toString().trim() ?? '';
        final email = data['email']?.toString().trim() ?? '';
        final university = data['university']?.toString().trim() ?? '';
        final department = data['department']?.toString().trim() ?? '';
        final photo = data['photoUrl']?.toString().trim() ?? '';

        return Column(
          children: [
            const SizedBox(height: GochanoSpacing.md),
            _Avatar(photoUrl: photo, onEdit: () => _editProfile(context, data)),
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              name.isEmpty
                  ? GochanoLanguage.text('Your account', 'আপনার অ্যাকাউন্ট')
                  : name,
              style: context.type.pageTitle,
              textAlign: TextAlign.center,
            ),
            if (email.isNotEmpty)
              Text(
                email,
                style: context.type.bodySecondary,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (university.isNotEmpty || department.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [university, department].where((e) => e.isNotEmpty).join(' · '),
                  style: context.type.caption.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A circular avatar with an edit affordance sitting on its edge.
///
/// Falls back to the project's own profile drawing when no picture is set,
/// which is the normal case — nothing in Gochano uploads one yet, and the
/// field is read defensively so a picture works the day something does.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.onEdit});

  final String photoUrl;
  final VoidCallback onEdit;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.brandSoft,
              border: Border.all(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: photoUrl.isEmpty
                ? Center(
                    child: GochanoIllustration(
                      GochanoArt.featureProfile,
                      size: 48,
                      accent: colors.brand,
                    ),
                  )
                : Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    // Decoded at roughly the size it is drawn, not at whatever
                    // the source happens to be.
                    cacheWidth: 384,
                    semanticLabel: GochanoLanguage.text(
                      'Profile picture',
                      'প্রোফাইল ছবি',
                    ),
                    errorBuilder: (context, _, _) => Center(
                      child: GochanoIllustration(
                        GochanoArt.featureProfile,
                        size: 48,
                        accent: colors.brand,
                      ),
                    ),
                  ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Material(
              color: colors.brand,
              shape: CircleBorder(
                side: BorderSide(color: colors.background, width: 2),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(
                    Icons.edit_outlined,
                    size: GochanoSizes.iconSm,
                    color: colors.onBrand,
                    semanticLabel: GochanoLanguage.text(
                      'Edit profile',
                      'প্রোফাইল সম্পাদনা',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: GochanoSpacing.sm),
      child: Center(
        child: GochanoBadge(
          label: role == 'student'
              ? GochanoLanguage.text('Student account', 'শিক্ষার্থী অ্যাকাউন্ট')
              : GochanoLanguage.text('General account', 'সাধারণ অ্যাকাউন্ট'),
          tone: GochanoBadgeTone.brand,
          icon: Icons.verified_user_outlined,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Study statistics
// ---------------------------------------------------------------------------

class _StudyStatsRow extends StatefulWidget {
  const _StudyStatsRow();

  @override
  State<_StudyStatsRow> createState() => _StudyStatsRowState();
}

class _StudyStatsRowState extends State<_StudyStatsRow> {
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
// Settings
// ---------------------------------------------------------------------------

/// One row inside a grouped settings card.
///
/// Shared rather than repeated four times, because the value line is the part
/// that makes a collapsed row honest: it says what the setting currently is,
/// so nothing was hidden by folding the radio lists away.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? colors.textSecondary),
      title: Text(title, style: context.type.body),
      subtitle: value.isEmpty
          ? null
          : Text(
              value,
              style: context.type.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: colors.textTertiary)),
      onTap: onTap,
    );
  }
}

class _SettingsCard extends StatefulWidget {
  const _SettingsCard({required this.isStudent});

  /// Monthly money is a student-only endpoint (`require_student`), so the row
  /// is hidden rather than shown and then failing with a 403.
  final bool isStudent;

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  bool? _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _checkNotifications();
  }

  Future<void> _checkNotifications() async {
    final enabled = await NotificationService.areNotificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = _notificationsEnabled;

    // Rebuilds when either preference changes, so the value line never shows
    // a stale choice after the selector closes.
    return ValueListenableBuilder<GochanoLocale>(
      valueListenable: GochanoLanguage.current,
      builder: (context, locale, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: GochanoAppearance.mode,
          builder: (context, mode, _) {
            return CardGroup(
              children: [
                if (widget.isStudent)
                  _SettingsRow(
                    icon: Icons.account_balance_wallet_outlined,
                    title: GochanoLanguage.text('Monthly money', 'মাসিক টাকা'),
                    value: GochanoLanguage.text(
                      'How much you have to spend this month.',
                      'এই মাসে আপনার কাছে কত টাকা আছে।',
                    ),
                    onTap: () => showMonthlyBudgetSheet(context),
                  ),
                _SettingsRow(
                  icon: Icons.language_rounded,
                  title: GochanoLanguage.text('Language', 'ভাষা'),
                  // Both names in their own script: a student who cannot read
                  // one can still tell which is selected.
                  value: locale.nativeName,
                  onTap: () => _pickLanguage(context),
                ),
                _SettingsRow(
                  icon: Icons.palette_outlined,
                  title: GochanoLanguage.text('Appearance', 'চেহারা'),
                  value: _appearanceLabel(mode),
                  onTap: () => _pickAppearance(context),
                ),
                _SettingsRow(
                  icon: enabled == false
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  iconColor: enabled == false ? colors.warning : null,
                  title: GochanoLanguage.text('Reminders', 'রিমাইন্ডার'),
                  value: switch (enabled) {
                    // Says plainly that reminders will not fire, rather than
                    // leaving a student to discover it when a dose is missed.
                    false => GochanoLanguage.text(
                        'Turned off in system settings. Medicine and task '
                        'reminders will not appear.',
                        'সিস্টেম সেটিংসে বন্ধ। ওষুধ ও কাজের রিমাইন্ডার দেখা যাবে না।',
                      ),
                    true => GochanoLanguage.text(
                        'Medicine and task reminders are on.',
                        'ওষুধ ও কাজের রিমাইন্ডার চালু আছে।',
                      ),
                    null => GochanoLanguage.text('Checking…', 'দেখা হচ্ছে…'),
                  },
                  onTap: enabled == false
                      ? () async {
                          await NotificationService.openNotificationSettings();
                          await _checkNotifications();
                        }
                      : null,
                  trailing: enabled == false
                      ? TextButton(
                          onPressed: () async {
                            await NotificationService.openNotificationSettings();
                            await _checkNotifications();
                          },
                          child: Text(
                            GochanoLanguage.text('Enable', 'চালু করুন'),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

String _appearanceLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system =>
        GochanoLanguage.text('Follow system', 'সিস্টেম অনুযায়ী'),
      ThemeMode.light => GochanoLanguage.text('Light', 'উজ্জ্বল'),
      ThemeMode.dark => GochanoLanguage.text('Dark', 'অন্ধকার'),
    };

// ---------------------------------------------------------------------------
// Destructive and about
// ---------------------------------------------------------------------------

/// Deleting the account stands alone, away from settings a student changes
/// casually, so it can never be tapped on the way to something else.
class _DangerCard extends StatelessWidget {
  const _DangerCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CardGroup(
      children: [
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: colors.error),
          title: Text(
            GochanoLanguage.text('Delete my account', 'আমার অ্যাকাউন্ট মুছুন'),
            style: context.type.body.copyWith(color: colors.error),
          ),
          subtitle: Text(
            GochanoLanguage.text(
              'Permanently removes your account, files and records.',
              'আপনার অ্যাকাউন্ট, ফাইল ও রেকর্ড স্থায়ীভাবে মুছে ফেলে।',
            ),
            style: context.type.caption,
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
          onTap: () => _deleteAccount(context),
        ),
      ],
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return CardGroup(
      children: [
        _SettingsRow(
          icon: Icons.info_outline_rounded,
          title: AppConfig.appName,
          value: GochanoLanguage.text(
            'Organize study and daily life in one place.',
            'পড়াশোনা ও দৈনন্দিন জীবন এক জায়গায় গুছিয়ে রাখুন।',
          ),
          onTap: null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Selectors
// ---------------------------------------------------------------------------

Future<void> _pickLanguage(BuildContext context) async {
  final chosen = await showModalBottomSheet<GochanoLocale>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              GochanoLanguage.text('Language', 'ভাষা'),
              style: sheetContext.type.sectionHeading,
            ),
          ),
          for (final locale in GochanoLocale.values)
            ListTile(
              // Each language names itself in its own script, so a student who
              // cannot read the other one can still pick correctly.
              title: Text(locale.nativeName),
              trailing: locale == GochanoLanguage.current.value
                  ? Icon(Icons.check_rounded, color: sheetContext.colors.brand)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(locale),
            ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ),
    ),
  );
  if (chosen != null) await GochanoLanguage.select(chosen);
}

Future<void> _pickAppearance(BuildContext context) async {
  const options = <(ThemeMode, IconData)>[
    (ThemeMode.system, Icons.brightness_auto_outlined),
    (ThemeMode.light, Icons.light_mode_outlined),
    (ThemeMode.dark, Icons.dark_mode_outlined),
  ];

  final chosen = await showModalBottomSheet<ThemeMode>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              GochanoLanguage.text('Appearance', 'চেহারা'),
              style: sheetContext.type.sectionHeading,
            ),
          ),
          for (final (mode, icon) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(_appearanceLabel(mode)),
              subtitle: mode == ThemeMode.system
                  ? Text(
                      GochanoLanguage.text(
                        'Matches your phone setting.',
                        'আপনার ফোনের সেটিং অনুসরণ করে।',
                      ),
                      style: sheetContext.type.caption,
                    )
                  : null,
              trailing: mode == GochanoAppearance.mode.value
                  ? Icon(Icons.check_rounded, color: sheetContext.colors.brand)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(mode),
            ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ),
    ),
  );
  if (chosen != null) await GochanoAppearance.select(chosen);
}

/// Edits the three profile fields this screen already displays.
///
/// Writes only to the signed-in student's own `users/{uid}` document, and
/// only these fields — `role` is untouched, which the security rules require
/// anyway. Nothing here changes authentication.
Future<void> _editProfile(
  BuildContext context,
  Map<String, dynamic> current,
) async {
  final name = TextEditingController(
    text: current['displayName']?.toString() ?? '',
  );
  final university = TextEditingController(
    text: current['university']?.toString() ?? '',
  );
  final department = TextEditingController(
    text: current['department']?.toString() ?? '',
  );

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: GochanoSpacing.md,
        right: GochanoSpacing.md,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + GochanoSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            GochanoLanguage.text('Edit profile', 'প্রোফাইল সম্পাদনা'),
            style: sheetContext.type.sectionHeading,
          ),
          const SizedBox(height: GochanoSpacing.md),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Name', 'নাম'),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: university,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('University', 'বিশ্ববিদ্যালয়'),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: department,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Department', 'বিভাগ'),
            ),
          ),
          const SizedBox(height: GochanoSpacing.md),
          PrimaryButton(
            label: GochanoLanguage.text('Save', 'সংরক্ষণ'),
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ),
    ),
  );

  if (saved != true || !context.mounted) return;

  try {
    await FirestoreService.updateProfile(
      displayName: name.text.trim(),
      university: university.text.trim(),
      department: department.text.trim(),
    );
    if (context.mounted) {
      showGochanoMessage(
        context,
        GochanoLanguage.text('Profile updated', 'প্রোফাইল হালনাগাদ হয়েছে'),
      );
    }
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  } finally {
    name.dispose();
    university.dispose();
    department.dispose();
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

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
