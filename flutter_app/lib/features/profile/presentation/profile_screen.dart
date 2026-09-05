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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
import '../../../services/usage_stats_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../home/presentation/home_screen.dart' show formatTaka;
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

          const SizedBox(height: GochanoSpacing.sm),
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
        final photoUrl = data['photoURL']?.toString().trim() ?? '';

        return Column(
          children: [
            const SizedBox(height: GochanoSpacing.sm),
            _ProfileAvatar(photoUrl: photoUrl),
            const SizedBox(height: GochanoSpacing.sm),
            GestureDetector(
              onTap: () => _editProfile(context, data),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      name.isEmpty
                          ? GochanoLanguage.text(
                              'Your account',
                              'আপনার অ্যাকাউন্ট',
                            )
                          : name,
                      style: context.type.pageTitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Icon(Icons.edit_rounded, size: 18, color: colors.brand),
                ],
              ),
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
                  [
                    university,
                    department,
                  ].where((e) => e.isNotEmpty).join(' · '),
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                  ),
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

/// Circular profile avatar with camera tap-to-change overlay.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasPhoto = photoUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => _changePhoto(context),
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.brand.withValues(alpha: 0.12),
              border: Border.all(
                color: colors.brand.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: hasPhoto
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      width: 96,
                      height: 96,
                      semanticLabel: GochanoLanguage.text(
                        'Profile photo',
                        'প্রোফাইল ছবি',
                      ),
                      errorBuilder: (_, _, e) => _fallbackIcon(colors),
                    )
                  : _fallbackIcon(colors),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surface,
                border: Border.all(
                  color: colors.border,
                  width: GochanoBorders.hairline,
                ),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: 16,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackIcon(GochanoColors colors) {
    return Center(
      child: GochanoIllustration(
        GochanoArt.featureProfile,
        size: 48,
        accent: colors.brand,
      ),
    );
  }
}

Future<void> _changePhoto(BuildContext context) async {
  final picker = ImagePicker();
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded),
            title: Text(GochanoLanguage.text('Take a photo', 'ছবি তুলুন')),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: Text(
              GochanoLanguage.text(
                'Choose from gallery',
                'গ্যালারি থেকে বাছুন',
              ),
            ),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  try {
    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (xFile == null || !context.mounted) return;

    showGochanoMessage(
      context,
      GochanoLanguage.text('Uploading photo…', 'ছবি আপলোড হচ্ছে…'),
    );

    final url = await ApiService.uploadProfilePhoto(xFile.path);
    if (!context.mounted) return;

    // Update the cached URL in Firestore so the stream picks it up.
    await FirestoreService.updateProfile({'photoURL': url});
    if (!context.mounted) return;

    showGochanoMessage(
      context,
      GochanoLanguage.text('Photo updated.', 'ছবি আপডেট হয়েছে।'),
    );
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Edit Profile
// ---------------------------------------------------------------------------

Future<void> _editProfile(
  BuildContext context,
  Map<String, dynamic> current,
) async {
  final nameCtl = TextEditingController(
    text: current['displayName']?.toString() ?? '',
  );
  final uniCtl = TextEditingController(
    text: current['university']?.toString() ?? '',
  );
  final deptCtl = TextEditingController(
    text: current['department']?.toString() ?? '',
  );

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: GochanoSpacing.lg,
          right: GochanoSpacing.lg,
          top: GochanoSpacing.lg,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                GochanoLanguage.text('Edit profile', 'প্রোফাইল সম্পাদনা'),
                style: sheetContext.type.pageTitle,
              ),
              const SizedBox(height: GochanoSpacing.md),
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text('Full name', 'পুরো নাম'),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
              ),
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                controller: uniCtl,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'University / Institution',
                    'বিশ্ববিদ্যালয় / প্রতিষ্ঠান',
                  ),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
              ),
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                controller: deptCtl,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'Faculty / Department',
                    'অনুষদ / বিভাগ',
                  ),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
              ),
              const SizedBox(height: GochanoSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(GochanoLanguage.text('Save', 'সংরক্ষণ')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.sm),
            ],
          ),
        ),
      );
    },
  );

  if (result != true || !context.mounted) return;

  final name = nameCtl.text.trim();
  if (name.isEmpty) {
    showGochanoMessage(
      context,
      GochanoLanguage.text('Name cannot be empty.', 'নাম খালি রাখা যাবে না।'),
      isError: true,
    );
    return;
  }

  try {
    await FirestoreService.updateProfile({
      'displayName': name,
      'university': uniCtl.text.trim(),
      'department': deptCtl.text.trim(),
    });
    if (!context.mounted) return;
    showGochanoMessage(
      context,
      GochanoLanguage.text('Profile updated.', 'প্রোফাইল আপডেট হয়েছে।'),
    );
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: GochanoSpacing.xs),
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
    if (_error.isNotEmpty && _stats == null) {
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

    // Backend returns `todaySeconds`/`monthSeconds`/`streakDays` as
    // canonical keys, with `accumulatedSeconds` already coerced server-side
    // (a 24h ceiling rejects poisoned rows). Aliases are kept for older
    // responses so a stale shape still renders something.
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
            value: GochanoLanguage.text(
              '$todayMinutes min',
              '$todayMinutes মি',
            ),
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('This month', 'এই মাস'),
            value: GochanoLanguage.text(
              '$monthMinutes min',
              '$monthMinutes মি',
            ),
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
/// One row inside a grouped settings card.
///
/// Uses a single [GestureDetector] wrapping the entire row to guarantee
/// full-width tap target on all devices — [ListTile] nested inside
/// [CardGroup]'s [ClipRRect] causes gesture-arena conflicts on some
/// Android builds where the [ListTile]'s own [Material]/[InkWell] eats
/// the tap before the outer [onTap] sees it.
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
    final effectiveTrailing =
        trailing ??
        (onTap == null
            ? null
            : Icon(Icons.chevron_right_rounded, color: colors.textTertiary));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.md,
          vertical: GochanoSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? colors.textSecondary, size: 22),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: context.type.body),
                  if (value.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: context.type.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (effectiveTrailing != null) ...[
              const SizedBox(width: GochanoSpacing.xs),
              effectiveTrailing,
            ],
          ],
        ),
      ),
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

class _SettingsCardState extends State<_SettingsCard>
    with WidgetsBindingObserver {
  bool? _notificationsEnabled;
  bool? _usageAccessGranted;

  /// The month's amount, or null while unread. Kept separate from "zero" so
  /// a failed read is never shown as "not set".
  double? _budget;
  bool _budgetFailed = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNotifications();
    _checkUsageAccess();
    if (widget.isStudent) _loadBudget();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) {
        debugPrint('[Profile] App resumed — re-checking usage access.');
      }
      _checkUsageAccess();
    }
  }

  Future<void> _loadBudget() async {
    try {
      final body = await ApiService.getMonthlyBudget(DateTime.now());
      if (!mounted) return;
      setState(() {
        _budget = (body['availableAmount'] as num?)?.toDouble() ?? 0;
        _budgetFailed = false;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      // Says so rather than claiming nothing is set.
      setState(() {
        _budgetFailed = true;
        _loaded = true;
      });
    }
  }

  String get _budgetLabel {
    if (_budgetFailed) {
      return GochanoLanguage.text(
        'Could not load it just now. Tap to try again.',
        'এখন লোড করা যায়নি। আবার চেষ্টা করতে চাপ দিন।',
      );
    }
    final amount = _budget;
    if (amount == null && !_loaded) {
      return GochanoLanguage.text('Checking…', 'দেখা হচ্ছে…');
    }
    if (amount == null || amount <= 0) {
      return GochanoLanguage.text(
        'Not set yet — tap to set the amount for this month.',
        'এখনো ঠিক করা হয়নি — এই মাসের পরিমাণ দিতে চাপ দিন।',
      );
    }
    return formatTaka(amount);
  }

  Future<void> _checkNotifications() async {
    final enabled = await NotificationService.areNotificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _checkUsageAccess() async {
    if (kDebugMode) debugPrint('[Profile] _checkUsageAccess: checking…');
    try {
      final granted = await UsageStatsService.hasPermission();
      if (kDebugMode) {
        debugPrint('[Profile] _checkUsageAccess: granted=$granted');
      }
      if (mounted) setState(() => _usageAccessGranted = granted);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Profile] _checkUsageAccess: error=$e');
      }
      if (mounted) setState(() => _usageAccessGranted = false);
    }
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
                    // The amount itself, not a description of it. A row that
                    // only said "how much you have to spend this month" gave
                    // a student no way to tell whether what they set had
                    // actually been saved.
                    value: _budgetLabel,
                    onTap: () async {
                      final changed = await showMonthlyBudgetSheet(context);
                      if (changed) await _loadBudget();
                    },
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
                      'Medicine and task reminders are on. Tap to change '
                          'this in system settings.',
                      'ওষুধ ও কাজের রিমাইন্ডার চালু আছে। বদলাতে সিস্টেম '
                          'সেটিংসে যেতে চাপ দিন।',
                    ),
                    null => GochanoLanguage.text('Checking…', 'দেখা হচ্ছে…'),
                  },
                  // Always tappable. Whether reminders are on is an Android
                  // permission, not an app setting, so the row opens the
                  // system screen that actually controls it -- and the state
                  // is re-checked on return so the row is never stale. A row
                  // that only responded when already broken gave a student no
                  // way to turn reminders back off.
                  onTap: () async {
                    await NotificationService.openNotificationSettings();
                    await _checkNotifications();
                  },
                  trailing: enabled == false
                      ? TextButton(
                          onPressed: () async {
                            await NotificationService.openNotificationSettings();
                            await _checkNotifications();
                          },
                          child: Text(
                            GochanoLanguage.text('Turn on', 'চালু করুন'),
                          ),
                        )
                      : null,
                ),
                _SettingsRow(
                  icon: Icons.screen_lock_portrait_rounded,
                  title: GochanoLanguage.text(
                    'Usage Access',
                    'ব্যবহার অ্যাক্সেস',
                  ),
                  value: switch (_usageAccessGranted) {
                    true => GochanoLanguage.text('Granted', 'দেওয়া হয়েছে'),
                    false => GochanoLanguage.text(
                      'Permission required',
                      'অনুমতি প্রয়োজন',
                    ),
                    null => GochanoLanguage.text('Checking…', 'দেখা হচ্ছে…'),
                  },
                  onTap: () async {
                    if (kDebugMode) {
                      debugPrint(
                        '[Profile] Usage Access row tapped. '
                        'current state=$_usageAccessGranted',
                      );
                      debugPrint(
                        '[Profile] Calling UsageStatsService.openSettings() '
                        '→ ACTION_USAGE_ACCESS_SETTINGS intent…',
                      );
                    }
                    await UsageStatsService.openSettings();
                    if (kDebugMode) {
                      debugPrint(
                        '[Profile] Returned from settings. '
                        'Re-checking permission…',
                      );
                    }
                    await _checkUsageAccess();
                  },
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
  ThemeMode.system => GochanoLanguage.text(
    'Follow system',
    'সিস্টেম অনুসরণ করে',
  ),
  ThemeMode.light => GochanoLanguage.text('Light', 'উজ্জ্বল'),
  ThemeMode.dark => GochanoLanguage.text('Dark', 'অন্ধকার'),
};

// ---------------------------------------------------------------------------
// Destructive and about
// ---------------------------------------------------------------------------

/// Deleting the account stands alone, away from settings a student changes
/// casually, so it can never be tapped on the way to something else.
class _DangerCard extends StatefulWidget {
  const _DangerCard();

  @override
  State<_DangerCard> createState() => _DangerCardState();
}

class _DangerCardState extends State<_DangerCard> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The destructive action is wrapped in an AppCard with an error accent
    // (spec §74). The accent rule draws a 3px bar on the leading edge so a
    // student recognises it as destructive before reading the label.
    return AppCard(
      accent: colors.error,
      padding: EdgeInsets.zero,
      child: ListTile(
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
        trailing: _deleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
        onTap: _deleting ? null : () => _deleteAccount(),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showConfirmationSheet(
      context,
      title: GochanoLanguage.text(
        'Delete your account?',
        'আপনার অ্যাকাউন্ট মুছবেন?',
      ),
      message: GochanoLanguage.text(
        'This permanently removes your account, uploaded files, expenses, medicines and study records. It cannot be undone.',
        'এটি আপনার অ্যাকাউন্ট, ফাইল, খরচ, ওষুধ ও পড়াশোনার রেকর্ড স্থায়ীভাবে মুছে ফেলবে। এটি ফেরানো যাবে না।',
      ),
      confirmLabel: GochanoLanguage.text('Delete everything', 'সবকিছু মুছুন'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ApiService.deleteAccount();
      // AuthGate listens to Firebase auth state and immediately replaces the
      // profile shell with Login after this successful deletion.
      await AuthService.logout();
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
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

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

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
