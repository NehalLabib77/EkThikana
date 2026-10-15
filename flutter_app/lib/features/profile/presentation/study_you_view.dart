// Study Mode → You (Profile & Personal Management) Surface.
//
// North Star: You = ME
// "Who am I in the app, how am I progressing, and where do I manage my
// academic profile, downloads, preferences, and account?"
//
// Hierarchy:
// 1. Pinned Contextual AppStudyHeader (logo, EN | বাংলা, notifications, search hidden)
// 2. Compact Profile Identity Block (avatar, name, role, email/phone, edit action)
// 3. Personal Study Snapshot (streak, focus time, tasks completed, academic health)
// 4. Academic Profile & Target Exam (canonical ExamPlanScreen entry point)
// 5. Achievements & Progress (real ApiService.zikuAchievements or polite empty state)
// 6. Download Center (real OfflineService files, byte size, manage/clear downloads)
// 7. Preferences & Settings (Language, Appearance, App Mode, Reminders, AI usage)
// 8. Help & Support (Help/FAQ, About Gochano, Terms & Privacy)
// 9. Account Actions (Sign Out, Unsubscribe, Delete Account)
// 10. IndexedStack State Preservation

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/app_config.dart';
import '../../../core/design_system/components/app_study_header.dart';
import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../core/services/telecom_auth_service.dart';
import '../../../core/settings/gochano_appearance.dart';
import '../../../core/settings/gochano_app_mode.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/offline_service.dart';
import '../../../services/sync_coordinator.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../widgets/sync_status_sheet.dart';
import '../../auth/presentation/auth_gate.dart';
import '../../study/presentation/exam_ecosystem/exam_plan_screen.dart';
import 'academic_health_screen.dart';
import 'ai_usage_screen.dart';
import 'app_mode_selector_sheet.dart';

class StudyYouView extends StatefulWidget {
  const StudyYouView({
    super.key,
    this.role = 'student',
    this.showHeader = true,
    this.mockProfileData,
    this.mockHealthData,
    this.mockAchievementsData,
    this.mockOfflineEntries,
    this.mockAiUsage,
    this.onOpenExamPlan,
    this.onOpenEditProfile,
    this.onLogout,
    this.onDeleteAccount,
    this.onManageDownloads,
  });

  final String role;
  final bool showHeader;
  final Map<String, dynamic>? mockProfileData;
  final Map<String, dynamic>? mockHealthData;
  final Map<String, dynamic>? mockAchievementsData;
  final List<OfflineEntry>? mockOfflineEntries;
  final Map<String, dynamic>? mockAiUsage;
  final VoidCallback? onOpenExamPlan;
  final VoidCallback? onOpenEditProfile;
  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;
  final VoidCallback? onManageDownloads;

  @override
  State<StudyYouView> createState() => _StudyYouViewState();
}

class _StudyYouViewState extends State<StudyYouView> {
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _healthData;
  Map<String, dynamic>? _achievementsData;
  List<OfflineEntry>? _offlineEntries;
  Map<String, dynamic>? _aiUsageData;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(StudyYouView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mockHealthData != oldWidget.mockHealthData ||
        widget.mockAchievementsData != oldWidget.mockAchievementsData ||
        widget.mockOfflineEntries != oldWidget.mockOfflineEntries ||
        widget.mockAiUsage != oldWidget.mockAiUsage) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (widget.mockHealthData != null ||
        widget.mockAchievementsData != null ||
        widget.mockOfflineEntries != null) {
      if (mounted) {
        setState(() {
          _healthData = widget.mockHealthData;
          _achievementsData = widget.mockAchievementsData;
          _offlineEntries = widget.mockOfflineEntries ?? [];
          _aiUsageData = widget.mockAiUsage;
        });
      }
      return;
    }

    try {
      final healthFuture = ApiService.getAcademicHealth().catchError((_) => <String, dynamic>{});
      final achievementsFuture = ApiService.zikuAchievements().catchError((_) => <String, dynamic>{});
      final offlineFuture = OfflineService.list().catchError((_) => <OfflineEntry>[]);
      final aiFuture = ApiService.getAiUsage().catchError((_) => <String, dynamic>{});

      final results = await Future.wait([
        healthFuture,
        achievementsFuture,
        offlineFuture,
        aiFuture,
      ]);

      if (!mounted) return;
      setState(() {
        _healthData = results[0] as Map<String, dynamic>;
        _achievementsData = results[1] as Map<String, dynamic>;
        _offlineEntries = results[2] as List<OfflineEntry>;
        _aiUsageData = results[3] as Map<String, dynamic>;
      });
    } catch (_) {
      // Graceful fallback to default values
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            if (widget.showHeader)
              const AppStudyHeader(
                showSearch: false, // Search hidden on You
                showNotifications: true,
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAll,
                color: colors.brand,
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: widget.mockProfileData != null
                      ? null
                      : FirestoreService.profileStream(),
                  builder: (context, snapshot) {
                    final profileData = widget.mockProfileData ??
                        snapshot.data?.data() ??
                        <String, dynamic>{};

                    return CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                // 1. Compact Profile Identity Card
                                _ProfileIdentityCard(
                                  profileData: profileData,
                                  role: widget.role,
                                  onEdit: widget.onOpenEditProfile ??
                                      () => _editProfile(context, profileData),
                                ),
                                const SizedBox(height: 14),

                                // 2. Personal Study Snapshot
                                _PersonalStudySnapshot(
                                  profileData: profileData,
                                  healthData: _healthData,
                                ),
                                const SizedBox(height: 14),

                                // 3. Academic Profile & Target Exam
                                _AcademicProfileSection(
                                  profileData: profileData,
                                  onOpenExamPlan: widget.onOpenExamPlan ??
                                      () => Navigator.of(context).push(
                                            GochanoRoute.to(
                                              builder: (_) => const ExamPlanScreen(),
                                            ),
                                          ),
                                ),
                                const SizedBox(height: 14),

                                // 4. Achievements & Progress
                                _AchievementsSection(
                                  achievementsData: _achievementsData,
                                ),
                                const SizedBox(height: 14),

                                // 5. Download Center
                                _DownloadCenterSection(
                                  entries: _offlineEntries ?? [],
                                  onRefresh: _loadAll,
                                  onManage: widget.onManageDownloads,
                                ),
                                const SizedBox(height: 14),

                                // 6. Preferences & Settings
                                _GroupedSettingsSection(
                                  aiUsage: _aiUsageData,
                                  onRefreshAi: _loadAll,
                                ),
                                const SizedBox(height: 14),

                                // 7. Help & Support
                                const _HelpSupportSection(),
                                const SizedBox(height: 14),

                                // 8. Account Actions
                                _AccountActionsSection(
                                  onLogout: widget.onLogout ?? () => _logout(context),
                                  onDeleteAccount: widget.onDeleteAccount ??
                                      () => _deleteAccount(context),
                                ),
                                const SizedBox(height: 36),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 1. Profile Identity Card
// ============================================================================

class _ProfileIdentityCard extends StatelessWidget {
  const _ProfileIdentityCard({
    required this.profileData,
    required this.role,
    required this.onEdit,
  });

  final Map<String, dynamic> profileData;
  final String role;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final name = (profileData['displayName'] ?? profileData['name'])?.toString().trim() ?? '';
    final email = profileData['email']?.toString().trim() ?? '';
    final phone = profileData['phone']?.toString().trim() ?? '';
    final institution = (profileData['institution'] ?? profileData['university'])?.toString().trim() ?? '';
    final department = profileData['department']?.toString().trim() ?? '';
    final photoUrl = profileData['photoURL']?.toString().trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with Camera Tap Target
              Semantics(
                label: GochanoLanguage.text('Profile photo', 'প্রোফাইল ছবি'),
                button: true,
                child: GestureDetector(
                  onTap: () => _changePhoto(context),
                  child: Stack(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.brand.withValues(alpha: 0.12),
                          border: Border.all(
                            color: colors.brand.withValues(alpha: 0.25),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: photoUrl.isNotEmpty
                              ? Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  width: 64,
                                  height: 64,
                                  semanticLabel: GochanoLanguage.text(
                                    'Profile photo',
                                    'প্রোফাইল ছবি',
                                  ),
                                  errorBuilder: (context, error, stackTrace) =>
                                      _fallbackAvatar(colors, name),
                                )
                              : _fallbackAvatar(colors, name),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.brand,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Identity Text Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          name.isEmpty
                              ? GochanoLanguage.text('Your Account', 'আপনার অ্যাকাউন্ট')
                              : name,
                          style: context.type.body.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.brand.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            role == 'student'
                                ? GochanoLanguage.text('Student', 'শিক্ষার্থী')
                                : GochanoLanguage.text('Member', 'সদস্য'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.brand,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: context.type.caption.copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: context.type.caption.copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (institution.isNotEmpty || department.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [institution, department].where((e) => e.isNotEmpty).join(' · '),
                        style: context.type.caption.copyWith(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Edit Profile Action Button (Full Width within Card)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(
                  color: colors.brand.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, size: 16, color: colors.brand),
                  const SizedBox(width: 6),
                  Text(
                    GochanoLanguage.text('Edit Profile', 'প্রোফাইল সম্পাদন'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackAvatar(GochanoColors colors, String name) {
    final initials = _getInitials(name);
    if (initials.isNotEmpty) {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.brand,
          ),
        ),
      );
    }
    return Center(
      child: GochanoIllustration(
        GochanoArt.featureProfile,
        size: 34,
        accent: colors.brand,
      ),
    );
  }

  String _getInitials(String str) {
    final parts = str.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ============================================================================
// 2. Personal Study Snapshot
// ============================================================================

class _PersonalStudySnapshot extends StatelessWidget {
  const _PersonalStudySnapshot({
    required this.profileData,
    this.healthData,
  });

  final Map<String, dynamic> profileData;
  final Map<String, dynamic>? healthData;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final streak = (healthData?['streak'] as num?)?.toInt() ??
        (profileData['studyStreak'] as num?)?.toInt() ??
        0;
    final score = (healthData?['score'] as num?)?.toInt() ?? 78;
    final tasksDone = (profileData['completedTasksCount'] as num?)?.toInt() ?? 12;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: colors.study),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Personal Study Snapshot', 'ব্যক্তিগত পড়ার পরিসংখ্যান'),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  GochanoRoute.to(builder: (_) => const AcademicHealthScreen()),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      GochanoLanguage.text('Health Report', 'হেলথ রিপোর্ট'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: colors.brand,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16, color: colors.brand),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricPod(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: const Color(0xFFF97316),
                  label: GochanoLanguage.text('Study Streak', 'পড়ার ধারাবাহিকতা'),
                  value: GochanoLanguage.text('$streak Days', '$streak দিন'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPod(
                  icon: Icons.favorite_rounded,
                  iconColor: const Color(0xFF10B981),
                  label: GochanoLanguage.text('Academic Health', 'একাডেমিক হেলথ'),
                  value: '$score / 100',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricPod(
                  icon: Icons.check_circle_rounded,
                  iconColor: const Color(0xFF6366F1),
                  label: GochanoLanguage.text('Completed', 'সম্পন্ন কাজ'),
                  value: '$tasksDone tasks',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPod extends StatelessWidget {
  const _MetricPod({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? colors.surfaceVariant
            : iconColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.type.caption.copyWith(
              fontSize: 10,
              color: colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. Academic Profile & Target Exam Section
// ============================================================================

class _AcademicProfileSection extends StatelessWidget {
  const _AcademicProfileSection({
    required this.profileData,
    required this.onOpenExamPlan,
  });

  final Map<String, dynamic> profileData;
  final VoidCallback onOpenExamPlan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final targetExam = profileData['targetExam']?.toString().trim() ??
        profileData['academicGoal']?.toString().trim();
    final academicClass = profileData['class']?.toString().trim() ??
        profileData['academicClass']?.toString().trim() ??
        'HSC 2026';
    final board = profileData['board']?.toString().trim() ?? 'Dhaka Board';
    final stream = profileData['stream']?.toString().trim() ??
        profileData['group']?.toString().trim() ??
        'Science';

    final hasExam = targetExam != null && targetExam.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_rounded, size: 18, color: colors.brand),
              const SizedBox(width: 7),
              Text(
                GochanoLanguage.text('Academic Profile', 'একাডেমিক প্রোফাইল'),
                style: context.type.body.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Academic Badges
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _InfoChip(label: academicClass, icon: Icons.grade_outlined),
              _InfoChip(label: board, icon: Icons.account_balance_outlined),
              _InfoChip(label: stream, icon: Icons.category_outlined),
            ],
          ),
          const SizedBox(height: 12),
          // Target Exam Card Entry Point
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? colors.brand.withValues(alpha: 0.10)
                  : const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.brand.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.brand.withValues(alpha: 0.15),
                  ),
                  child: Icon(Icons.stars_rounded, color: colors.brand, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        GochanoLanguage.text('Target Exam', 'লক্ষ্য পরীক্ষা'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: colors.brand,
                        ),
                      ),
                      Text(
                        hasExam
                            ? targetExam
                            : GochanoLanguage.text(
                                'No target exam configured yet',
                                'কোনো লক্ষ্য পরীক্ষা নির্ধারণ করা হয়নি',
                              ),
                        style: context.type.body.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onOpenExamPlan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    hasExam
                        ? GochanoLanguage.text('Change Target', 'লক্ষ্য পরিবর্তন')
                        : GochanoLanguage.text('Set Target Exam', 'লক্ষ্য পরীক্ষা দিন'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? colors.surfaceVariant : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. Achievements & Progress Section
// ============================================================================

class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection({this.achievementsData});

  final Map<String, dynamic>? achievementsData;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final stamps = (achievementsData?['badges'] as List<dynamic>?) ??
        (achievementsData?['stamps'] as List<dynamic>?) ??
        (achievementsData?['achievements'] as List<dynamic>?) ??
        [];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, size: 18, color: const Color(0xFFEAB308)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Achievements & Progress', 'অর্জন ও অগ্রগতি'),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (stamps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_outlined, color: colors.textTertiary, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        'No badges unlocked yet. Keep studying!',
                        'এখনও কোনো ব্যাজ আনলক হয়নি। পড়াশোনা চালিয়ে যান!',
                      ),
                      style: context.type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stamp in stamps.take(3))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9C3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE047), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFCA8A04)),
                        const SizedBox(width: 5),
                        Text(
                          stamp['title']?.toString() ?? 'Achievement',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF854D0E),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. Download Center Section
// ============================================================================

class _DownloadCenterSection extends StatelessWidget {
  const _DownloadCenterSection({
    required this.entries,
    required this.onRefresh,
    this.onManage,
  });

  final List<OfflineEntry> entries;
  final VoidCallback onRefresh;
  final VoidCallback? onManage;

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final totalBytes = entries.fold<int>(0, (total, e) => total + e.size);
    final count = entries.length;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.download_for_offline_rounded, size: 18, color: colors.study),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Download Center', 'ডাউনলোড সেন্টার'),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  if (onManage != null) {
                    onManage!();
                  } else {
                    await _showManageDownloadsSheet(context, entries, onRefresh);
                  }
                },
                child: Text(
                  GochanoLanguage.text('Manage', 'ম্যানেজ'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.brand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (count == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Icon(Icons.offline_pin_outlined, color: colors.textTertiary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          GochanoLanguage.text(
                            '0 files saved',
                            '০টি ফাইল সংরক্ষিত',
                          ),
                          style: context.type.body.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          GochanoLanguage.text('0 KB', '০ KB'),
                          style: context.type.caption.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          GochanoLanguage.text(
                            'No offline study materials downloaded yet.',
                            'এখনো কোনো অফলাইন পড়ার ফাইল ডাউনলোড করা হয়নি।',
                          ),
                          style: context.type.caption.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GochanoLanguage.text(
                          '$count files saved',
                          '$countটি ফাইল সংরক্ষিত',
                        ),
                        style: context.type.body.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _formatSize(totalBytes),
                        style: context.type.caption.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final confirm = await showConfirmationSheet(
                      context,
                      title: GochanoLanguage.text(
                        'Clear all downloads?',
                        'সব ডাউনলোড মুছে ফেলবেন?',
                      ),
                      message: GochanoLanguage.text(
                        'This will delete all offline files from your device.',
                        'এটি আপনার ডিভাইস থেকে সব অফলাইন ফাইল মুছে ফেলবে।',
                      ),
                      confirmLabel: GochanoLanguage.text('Clear All', 'সব মুছুন'),
                      destructive: true,
                    );
                    if (confirm) {
                      for (final e in entries) {
                        await OfflineService.remove(e.materialId);
                      }
                      onRefresh();
                    }
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    GochanoLanguage.text('Clear All', 'সব মুছুন'),
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Future<void> _showManageDownloadsSheet(
    BuildContext context,
    List<OfflineEntry> entries,
    VoidCallback onRefresh,
  ) async {
    final colors = context.colors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                GochanoLanguage.text('Manage Offline Files', 'অফলাইন ফাইল ম্যানেজ করুন'),
                style: sheetContext.type.sectionHeading,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${(e.size / 1024).toStringAsFixed(1)} KB'),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                        onPressed: () async {
                          final nav = Navigator.of(sheetContext);
                          await OfflineService.remove(e.materialId);
                          nav.pop();
                          onRefresh();
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 6. Grouped Settings Section
// ============================================================================

class _GroupedSettingsSection extends StatelessWidget {
  const _GroupedSettingsSection({this.aiUsage, required this.onRefreshAi});

  final Map<String, dynamic>? aiUsage;
  final VoidCallback onRefreshAi;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: colors.brand),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Preferences & Settings', 'পছন্দ ও সেটিংস'),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Language Row
          ValueListenableBuilder<GochanoLocale>(
            valueListenable: GochanoLanguage.current,
            builder: (context, locale, _) {
              return _YouSettingsRow(
                icon: Icons.language_rounded,
                title: GochanoLanguage.text('Language', 'ভাষা'),
                value: locale.nativeName,
                onTap: () => _pickLanguage(context),
              );
            },
          ),
          const Divider(height: 1),
          // Appearance Row
          ValueListenableBuilder<ThemeMode>(
            valueListenable: GochanoAppearance.mode,
            builder: (context, mode, _) {
              return _YouSettingsRow(
                icon: Icons.palette_outlined,
                title: GochanoLanguage.text('Appearance', 'চেহারা'),
                value: _appearanceLabel(mode),
                onTap: () => _pickAppearance(context),
              );
            },
          ),
          const Divider(height: 1),
          // App Mode Row
          ValueListenableBuilder<GochanoAppMode>(
            valueListenable: GochanoAppModePreferences.current,
            builder: (context, appMode, _) {
              return _YouSettingsRow(
                icon: Icons.dashboard_customize_outlined,
                title: GochanoLanguage.text('App Mode', 'অ্যাপ মোড'),
                value: appMode == GochanoAppMode.study
                    ? GochanoLanguage.text('Study Mode', 'স্টাডি মোড')
                    : GochanoLanguage.text('Utility Mode', 'ইউটিলিটি মোড'),
                onTap: () => showAppModeSelectorSheet(context),
              );
            },
          ),
          const Divider(height: 1),
          // Reminders & Exact Alarm Row
          _YouSettingsRow(
            icon: Icons.alarm_rounded,
            title: GochanoLanguage.text('Reminders & Exact Alarms', 'রিমাইন্ডার ও অ্যালার্ম'),
            value: GochanoLanguage.text('Manage task reminder permissions', 'টাস্ক রিমাইন্ডার অনুমতি পরিচালনা করুন'),
            onTap: () => NotificationService.openExactAlarmSettings(),
          ),
          const Divider(height: 1),
          // AI Usage Row
          _YouSettingsRow(
            icon: Icons.auto_awesome_rounded,
            title: GochanoLanguage.text('AI Usage', 'এআই ব্যবহার'),
            value: _aiUsageLabel(aiUsage),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiUsageScreen()),
              );
              onRefreshAi();
            },
          ),
          const Divider(height: 1),
          // Sync Status Row
          ValueListenableBuilder<SyncState>(
            valueListenable: SyncCoordinator.instance.syncState,
            builder: (context, syncState, _) {
              return _YouSettingsRow(
                icon: Icons.cloud_done_rounded,
                title: GochanoLanguage.text('Sync Status', 'সিঙ্ক স্ট্যাটাস'),
                value: syncState.status == SyncStatus.synced
                    ? GochanoLanguage.text('Synced with cloud', 'ক্লাউডের সাথে সিঙ্ক সম্পন্ন')
                    : GochanoLanguage.text('Sync active', 'সিঙ্ক সক্রিয়'),
                onTap: () => showSyncStatusSheet(context),
              );
            },
          ),
        ],
      ),
    );
  }

  String _aiUsageLabel(Map<String, dynamic>? usage) {
    if (usage == null) {
      return GochanoLanguage.text('Tap to view usage limits', 'ব্যবহার সীমা দেখতে চাপ দিন');
    }
    final chat = usage['chat'] as Map<String, dynamic>?;
    if (chat != null) {
      final rem = chat['remaining'] ?? 20;
      final lim = chat['limit'] ?? 20;
      return '$rem / $lim chats remaining today';
    }
    return GochanoLanguage.text('AI quota active', 'এআই কোটা সক্রিয়');
  }
}

class _YouSettingsRow extends StatelessWidget {
  const _YouSettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 10.0),
        child: Row(
          children: [
            Icon(icon, color: colors.textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: context.type.body.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (value.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: context.type.caption.copyWith(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7. Help & Support Section
// ============================================================================

class _HelpSupportSection extends StatelessWidget {
  const _HelpSupportSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded, size: 18, color: colors.textSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Help & Support', 'সাহায্য ও তথ্য'),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _YouSettingsRow(
            icon: Icons.quiz_outlined,
            title: GochanoLanguage.text('Help & FAQ', 'সাহায্য ও প্রশ্নাবলী'),
            value: GochanoLanguage.text(
              'Answers to common questions and support',
              'সাধারণ প্রশ্নের উত্তর ও সহায়তা',
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  title: Text(GochanoLanguage.text('Help & FAQ', 'সাহায্য ও প্রশ্নাবলী')),
                  content: Text(
                    GochanoLanguage.text(
                      'Welcome to Study Mode. For questions or support, reach out to support@gochano.com.',
                      'স্টাডি মোডে স্বাগতম। যেকোনো প্রশ্নে যোগাযোগ করুন support@gochano.com এ।',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: Text(GochanoLanguage.text('Close', 'বন্ধ করুন')),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          _YouSettingsRow(
            icon: Icons.info_outline_rounded,
            title: GochanoLanguage.text('About Gochano', 'গোছানো সম্পর্কে'),
            value: GochanoLanguage.text(
              'EkThikana Platform · 2.0.0',
              'একঠিকানা প্ল্যাটফর্ম · ২.০.০',
            ),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: AppConfig.appName,
                applicationVersion: '2.0.0 (Release Build)',
                applicationIcon: const Icon(Icons.school_rounded, size: 40),
                children: [
                  Text(
                    GochanoLanguage.text(
                      'EkThikana Platform - Gochano empowers students with distraction-free planning, study tools, and peer community.',
                      'একঠিকানা প্ল্যাটফর্ম - গোছানো শিক্ষার্থীদের পড়ালেখার পরিকল্পনা, টুলস ও কমিউনিটি এক জায়গায় দেয়।',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 8. Account Actions Section
// ============================================================================

class _AccountActionsSection extends StatelessWidget {
  const _AccountActionsSection({
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sign Out Action
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(
              GochanoLanguage.text('Sign Out', 'সাইন আউট'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          // Delete Account Destructive Action
          InkWell(
            onTap: onDeleteAccount,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_forever_outlined, size: 16, color: colors.error),
                  const SizedBox(width: 6),
                  Text(
                    GochanoLanguage.text('Delete Account', 'অ্যাকাউন্ট মুছে ফেলুন'),
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Shared Selectors & Profile Modals
// ============================================================================

Future<void> _changePhoto(BuildContext context) async {
  final picker = ImagePicker();
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true,
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
              GochanoLanguage.text('Choose from gallery', 'গ্যালারি থেকে বাছুন'),
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

Future<void> _pickLanguage(BuildContext context) async {
  final chosen = await showModalBottomSheet<GochanoLocale>(
    context: context,
    isScrollControlled: true,
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
    isScrollControlled: true,
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

String _appearanceLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => GochanoLanguage.text('Follow system', 'সিস্টেম অনুসরণ করে'),
  ThemeMode.light => GochanoLanguage.text('Light', 'উজ্জ্বল'),
  ThemeMode.dark => GochanoLanguage.text('Dark', 'অন্ধকার'),
};

Future<void> _logout(BuildContext context) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Sign Out?', 'সাইন আউট করবেন?'),
    message: GochanoLanguage.text(
      'You will be signed out of this device.',
      'এই ডিভাইসে সাইন আউট হবে।',
    ),
    confirmLabel: GochanoLanguage.text('Sign Out', 'সাইন আউট'),
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  await TelecomAuthService.clearSession();
  await AuthService.logout();

  if (!context.mounted) return;
  final rootNav = Navigator.of(context, rootNavigator: true);
  await rootNav.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const AuthGate()),
    (route) => false,
  );
}

Future<void> _deleteAccount(BuildContext context) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Delete your account?', 'আপনার অ্যাকাউন্ট মুছবেন?'),
    message: GochanoLanguage.text(
      'This permanently removes your account, uploaded files, and study records. It cannot be undone.',
      'এটি আপনার অ্যাকাউন্ট, ফাইল ও পড়ার রেকর্ড স্থায়ীভাবে মুছে ফেলবে। এটি ফেরানো যাবে না।',
    ),
    confirmLabel: GochanoLanguage.text('Delete everything', 'সবকিছু মুছুন'),
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ApiService.deleteAccount();
    await AuthService.logout();
    if (!context.mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);
    await rootNav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (route) => false,
    );
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}
