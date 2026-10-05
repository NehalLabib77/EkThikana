import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/local_reminder_store.dart';
import '../../../../services/notification_service.dart';
import '../../../../widgets/language_toggle.dart';
import '../../../notifications/presentation/notification_center_screen.dart';
import '../../../profile/presentation/academic_health_screen.dart';
import '../../../search/presentation/universal_search_screen.dart';
import '../../../tasks/domain/task_lifecycle.dart';
import '../ai/ziku_assistant_panel.dart';
import '../focus/focus_session_screen.dart';
import '../materials/material_reader_screen.dart';
import '../planner/coach_dashboard_screen.dart';
import '../rescue/exam_rescue_models.dart';
import '../rescue/exam_rescue_session_service.dart';

/// The approved modern Study Today experience for Gochano.
///
/// Visual hierarchy:
/// HEADER
/// ↓
/// GREETING + small contextual daily status
/// ↓
/// EXAM RESCUE HERO (or dynamic fallback hero)
/// ↓
/// TODAY'S PRIORITIES (maximum 3 cards)
/// ↓
/// ZIKU COACH + FOCUS SESSION (responsive side-by-side / stacked)
/// ↓
/// CONTINUE LEARNING
/// ↓
/// SIMPLIFIED ACADEMIC HEALTH
class StudyTodayDashboardView extends StatefulWidget {
  const StudyTodayDashboardView({
    super.key,
    required this.displayName,
    required this.onOpenDestination,
    required this.onOpenProfile,
    this.examRescueSessionService,
    this.bootstrapData,
    this.onRefresh,
  });

  final String displayName;
  final ValueChanged<int> onOpenDestination;
  final VoidCallback onOpenProfile;
  final ExamRescueSessionService? examRescueSessionService;
  final Map<String, dynamic>? bootstrapData;
  final Future<void> Function()? onRefresh;

  @override
  State<StudyTodayDashboardView> createState() => _StudyTodayDashboardViewState();
}

class _StudyTodayDashboardViewState extends State<StudyTodayDashboardView> {
  ExamRescueSessionService get _rescueService =>
      widget.examRescueSessionService ?? ExamRescueSessionService.instance;

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return GochanoLanguage.text('Good Morning', 'শুভ সকাল');
    } else if (hour >= 12 && hour < 17) {
      return GochanoLanguage.text('Good Afternoon', 'শুভ দুপুর');
    } else {
      return GochanoLanguage.text('Good Evening', 'শুভ সন্ধ্যা');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: widget.onRefresh ?? () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Top padding
              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.xs),
              ),

              // SECTION 1: HEADER
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _buildHeader(context),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.sm),
              ),

              // SECTION 2: GREETING & CONTEXTUAL STATUS
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _buildGreeting(context),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.md),
              ),

              // SECTION 3: HERO (EXAM RESCUE OR DYNAMIC FALLBACK)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _buildHeroSection(context),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.lg),
              ),

              // SECTION 4: TODAY'S PRIORITIES (MAX 3)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _buildPrioritiesSection(context),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.lg),
              ),

              // SECTION 5: ZIKU COACH + FOCUS SESSION
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _buildZikuAndFocusSection(context),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.lg),
              ),

              // SECTION 6: CONTINUE LEARNING
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _buildContinueLearningSection(context),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.lg),
              ),

              // SECTION 7: SIMPLIFIED ACADEMIC HEALTH
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _buildAcademicHealthSection(context),
                ),
              ),

              // Bottom breathing room
              const SliverToBoxAdapter(
                child: SizedBox(height: GochanoSpacing.xxxl + GochanoSpacing.xl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Header
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryNarrow = constraints.maxWidth < 340;

        return Row(
          children: [
            // Brand icon + name
            Container(
              width: isVeryNarrow ? 28 : 34,
              height: isVeryNarrow ? 28 : 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                AppAssets.logo,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.school_rounded,
                  color: const Color(0xFF2F6BFF),
                  size: isVeryNarrow ? 20 : 24,
                ),
              ),
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Gochano',
                    style: type.cardHeading.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: isVeryNarrow ? 15 : 17,
                      letterSpacing: -0.3,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isVeryNarrow)
                    Text(
                      GochanoLanguage.text(
                        'Study Better. A Brighter You.',
                        'পড়াশোনা সুন্দর, ভবিষ্যৎ আলোকিত।',
                      ),
                      style: type.bodySecondary.copyWith(
                        fontSize: 10.5,
                        height: 1.1,
                        color: colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Controls
            const LanguageToggle(),
            const SizedBox(width: 2),

            // Search icon
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  GochanoRoute.to(builder: (_) => const UniversalSearchScreen()),
                );
              },
              tooltip: GochanoLanguage.text('Search', 'অনুসন্ধান'),
              icon: Icon(Icons.search_rounded, size: isVeryNarrow ? 20 : 22),
              padding: isVeryNarrow ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints(
                minWidth: isVeryNarrow ? 32 : 38,
                minHeight: isVeryNarrow ? 32 : 38,
              ),
            ),

            // Notifications with badge
            ValueListenableBuilder<int>(
              valueListenable: LocalReminderStore.instance.unreadCountNotifier,
              builder: (context, unreadCount, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          GochanoRoute.to(
                            builder: (_) => const NotificationCenterScreen(),
                          ),
                        );
                      },
                      tooltip: GochanoLanguage.text(
                        'Notification Center',
                        'নোটিফিকেশন সেন্টার',
                      ),
                      icon: Icon(
                        Icons.notifications_outlined,
                        size: isVeryNarrow ? 20 : 22,
                      ),
                      padding: isVeryNarrow
                          ? const EdgeInsets.all(4)
                          : const EdgeInsets.all(8),
                      visualDensity: VisualDensity.compact,
                      constraints: BoxConstraints(
                        minWidth: isVeryNarrow ? 32 : 38,
                        minHeight: isVeryNarrow ? 32 : 38,
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 14,
                            minHeight: 14,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            // Profile avatar
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.profileStream(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final photoURL = data?['photoURL'] as String?;
                final name = (data?['displayName'] as String?)?.trim() ??
                    widget.displayName.trim();

                return InkWell(
                  onTap: widget.onOpenProfile,
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                  child: Padding(
                    padding: EdgeInsets.all(isVeryNarrow ? 2 : 4),
                    child: CircleAvatar(
                      radius: isVeryNarrow ? 15 : 17,
                      backgroundColor: colors.brand,
                      backgroundImage: photoURL != null && photoURL.isNotEmpty
                          ? NetworkImage(photoURL)
                          : null,
                      child: photoURL == null || photoURL.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isVeryNarrow ? 12 : 13,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Greeting & Contextual Status
  // ---------------------------------------------------------------------------
  Widget _buildGreeting(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.profileStream(),
      builder: (context, profileSnap) {
        final profileData = profileSnap.data?.data();
        final rawName = (profileData?['displayName'] as String?)?.trim() ??
            widget.displayName.trim();
        final name = rawName.isNotEmpty ? rawName : 'Friend';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('tasks', limit: 100),
          builder: (context, taskSnap) {
            final now = DateTime.now();
            final docs = taskSnap.data?.docs ?? const [];
            var todayTaskCount = 0;
            var completedCount = 0;

            for (final doc in docs) {
              final d = doc.data();
              if (TaskLifecycle.belongsToToday(d, now)) {
                todayTaskCount++;
                if (TaskLifecycle.isTaskCompleted(d)) {
                  completedCount++;
                }
              }
            }

            final String statusHeadline;
            final String statusSubtitle;
            if (todayTaskCount == 0) {
              statusHeadline = GochanoLanguage.text('Your day is clear', 'আজকের দিনটি মুক্ত');
              statusSubtitle = GochanoLanguage.text('No tasks scheduled', 'কোনো কাজ নির্ধারিত নেই');
            } else if (completedCount == todayTaskCount && todayTaskCount > 0) {
              statusHeadline = GochanoLanguage.text('Great work today!', 'দারুণ কাজ সম্পন্ন!');
              statusSubtitle = GochanoLanguage.text('All tasks finished', 'সব কাজ সম্পন্ন হয়েছে');
            } else {
              final remaining = todayTaskCount - completedCount;
              statusHeadline = GochanoLanguage.text('Today looks good!', 'আজকের দিন চমৎকার!');
              statusSubtitle = GochanoLanguage.text(
                '$remaining focused task${remaining > 1 ? 's' : ''} planned',
                '$remaining টি কাজ নির্ধারিত',
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 380;

                final greetingColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_greetingText()}, $name 👋',
                      style: type.pageTitle.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      GochanoLanguage.text(
                        "Today's the day to make progress.",
                        'আজই নতুন লক্ষ্য অর্জনের দিন।',
                      ),
                      style: type.bodySecondary.copyWith(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                );

                final statusCard = InkWell(
                  onTap: () => widget.onOpenDestination(2), // Plan tab
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GochanoSpacing.sm,
                      vertical: GochanoSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      border: Border.all(
                        color: const Color(0xFFBBF7D0),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.eco_rounded,
                          size: 18,
                          color: Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                statusHeadline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF15803D),
                                  fontFamily: GochanoTypography.fontFamily,
                                ),
                              ),
                              Text(
                                statusSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF166534),
                                  fontFamily: GochanoTypography.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: Color(0xFF15803D),
                        ),
                      ],
                    ),
                  ),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      greetingColumn,
                      const SizedBox(height: GochanoSpacing.xs),
                      statusCard,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: greetingColumn),
                    const SizedBox(width: GochanoSpacing.sm),
                    statusCard,
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Hero Section (Exam Rescue or Dynamic Fallback)
  // ---------------------------------------------------------------------------
  Widget _buildHeroSection(BuildContext context) {
    return StreamBuilder<ExamRescueSession?>(
      stream: _rescueService.streamNearestActiveSession(),
      builder: (context, sessionSnap) {
        final session = sessionSnap.data;
        final now = DateTime.now();

        if (session != null && session.isEligibleActive(now)) {
          // ACTIVE EXAM RESCUE HERO
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirestoreService.ownerStream('tasks', limit: 100),
            builder: (context, taskSnap) {
              final docs = taskSnap.data?.docs ?? const [];
              final taskMaps = docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['id'] = d.id;
                return m;
              }).toList();

              final progress = ExamRescueSessionService.calculateTodayProgress(
                session: session,
                tasks: taskMaps,
                now: now,
              );

              final daysLeft = session.localDaysRemaining(now);
              final hours = progress.todayPlannedMinutes ~/ 60;
              final mins = progress.todayPlannedMinutes % 60;
              final plannedText = hours > 0
                  ? '${hours}h ${mins}m'
                  : '${mins}m';

              return AppHeroCard(
                badgeText: GochanoLanguage.text('Exam Rescue', 'এক্সাম রেসকিউ'),
                title: session.examTitle,
                subtitle: GochanoLanguage.text(
                  'Your focused plan for today. Smaller steps. Stronger results.',
                  'আজকের জন্য নির্দিষ্ট প্ল্যান। ছোট পদক্ষেপে বড় সাফল্য।',
                ),
                stats: [
                  HeroStatItem(
                    icon: Icons.calendar_today_rounded,
                    value: '$daysLeft',
                    label: GochanoLanguage.text('days left', 'দিন বাকি'),
                  ),
                  HeroStatItem(
                    icon: Icons.access_time_rounded,
                    value: plannedText,
                    label: GochanoLanguage.text('planned today', 'আজ নির্ধারিত'),
                  ),
                  HeroStatItem(
                    icon: Icons.track_changes_rounded,
                    value: '${progress.todayCompleted}/${progress.todayTotal}',
                    label: GochanoLanguage.text('topics today', 'বিষয় আজ'),
                  ),
                ],
                ctaLabel: progress.isPlanAllDone
                    ? GochanoLanguage.text('Review Plan', 'প্ল্যান দেখুন')
                    : GochanoLanguage.text("Start Today's Plan", 'আজকের প্ল্যান শুরু করুন'),
                onCta: () => widget.onOpenDestination(2), // Plan tab
                illustration: _buildHeroIllustration(),
              );
            },
          );
        }

        // DYNAMIC FALLBACK HERO
        // Priority 1: Ziku recommendation from bootstrap
        final recMap = widget.bootstrapData?['recommendation'] as Map<String, dynamic>?;
        final isRecAvailable = recMap != null && recMap['available'] != false;
        final recItems = isRecAvailable ? recMap['items'] as List? : null;
        final topRec = recItems != null && recItems.isNotEmpty
            ? recItems.first as Map<String, dynamic>?
            : null;

        if (topRec != null) {
          final recTitle = topRec['title']?.toString() ?? 'Core Revision';
          final recReason = topRec['reason']?.toString() ?? 'Recommended for today';

          return AppHeroCard(
            badgeText: GochanoLanguage.text('AI Recommendation', 'এআই সুপারিশ'),
            badgeIcon: Icons.auto_awesome_rounded,
            badgeColor: const Color(0xFF38BDF8),
            gradient: AppGradients.fallbackHero,
            title: recTitle,
            subtitle: recReason,
            stats: [
              HeroStatItem(
                icon: Icons.track_changes_rounded,
                value: GochanoLanguage.text('Focus', 'ফোকাস'),
                label: GochanoLanguage.text('High impact', 'জরুরি'),
              ),
              HeroStatItem(
                icon: Icons.timer_outlined,
                value: '30 min',
                label: GochanoLanguage.text('estimated', 'আনুমানিক'),
              ),
            ],
            ctaLabel: GochanoLanguage.text('Start Study Session', 'সেশন শুরু করুন'),
            onCta: () => widget.onOpenDestination(2), // Plan tab
            illustration: _buildHeroIllustration(),
          );
        }

        // Priority 4: Deterministic daily study kickoff
        return AppHeroCard(
          badgeText: GochanoLanguage.text('Daily Focus', 'দৈনিক ফোকাস'),
          badgeIcon: Icons.bolt_rounded,
          badgeColor: const Color(0xFFFBBF24),
          gradient: AppGradients.fallbackHero,
          title: GochanoLanguage.text(
            'Make Every Hour Count',
            'প্রতিটি মুহূর্তকে কাজে লাগাও',
          ),
          subtitle: GochanoLanguage.text(
            'Master one topic at a time. Small daily consistency builds mastery.',
            'এক সময়ে একটি বিষয়ে মনোনিবেশ করুন। প্রতিদিনের অভ্যাসই সাফল্য আনবে।',
          ),
          stats: [
            HeroStatItem(
              icon: Icons.school_rounded,
              value: GochanoLanguage.text('Focused', 'মনোযোগ'),
              label: GochanoLanguage.text('Daily progress', 'অগ্রগতি'),
            ),
          ],
          ctaLabel: GochanoLanguage.text('Open Plan', 'প্ল্যান দেখুন'),
          onCta: () => widget.onOpenDestination(2),
          illustration: _buildHeroIllustration(),
        );
      },
    );
  }

  Widget _buildHeroIllustration() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: 34,
          ),
          SizedBox(height: 4),
          Text(
            'DISCIPLINE\nBRIGHTER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Today's Priorities (Maximum 3 cards)
  // ---------------------------------------------------------------------------
  Widget _buildPrioritiesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionHeader(
          icon: Icons.track_changes_rounded,
          iconColor: const Color(0xFF7048F5),
          title: GochanoLanguage.text("Today's Priorities", 'আজকের অগ্রাধিকার'),
          actionLabel: GochanoLanguage.text('See All', 'সব দেখুন'),
          onAction: () => widget.onOpenDestination(2), // Plan tab
        ),
        const SizedBox(height: GochanoSpacing.xs),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('tasks', limit: 100),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppSkeleton(height: 120);
            }

            final now = DateTime.now();
            final docs = snapshot.data?.docs ?? const [];
            final todayOpenTasks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            for (final doc in docs) {
              final d = doc.data();
              // Canonical TaskLifecycle rule: only include open tasks belonging to Today
              if (TaskLifecycle.belongsToToday(d, now) &&
                  !TaskLifecycle.isTaskCompleted(d)) {
                todayOpenTasks.add(doc);
              }
            }

            // Sort by due date ascending
            todayOpenTasks.sort((a, b) {
              final at = TaskLifecycle.parseDateTime(a.data()['dueAt']);
              final bt = TaskLifecycle.parseDateTime(b.data()['dueAt']);
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return at.compareTo(bt);
            });

            if (todayOpenTasks.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GochanoSpacing.lg),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? context.colors.surface
                      : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border.all(
                    color: context.colors.border,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFFECFDF5),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF059669),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            GochanoLanguage.text(
                              'All priorities clear!',
                              'আজকের সব কাজ সম্পন্ন!',
                            ),
                            style: context.type.cardHeading.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            GochanoLanguage.text(
                              'Add new tasks from Plan or enjoy your day.',
                              'পরিকল্পনা থেকে নতুন কাজ যোগ করুন।',
                            ),
                            style: context.type.bodySecondary.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Show maximum 3 cards
            final displayDocs = todayOpenTasks.take(3).toList();

            return LayoutBuilder(
              builder: (context, constraints) {
                // Responsive card width calculation
                final cardWidth = constraints.maxWidth >= 500
                    ? (constraints.maxWidth - 24) / 3
                    : (constraints.maxWidth >= 380
                        ? (constraints.maxWidth - 12) / 2.2
                        : 200.0);

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (int i = 0; i < displayDocs.length; i++) ...[
                        if (i > 0) const SizedBox(width: GochanoSpacing.sm),
                        SizedBox(
                          width: cardWidth,
                          child: _buildPriorityItem(displayDocs[i]),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildPriorityItem(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = data['title']?.toString() ?? 'Task';
    final topic = data['topic']?.toString() ?? data['subject']?.toString();
    final duration = data['estimatedMinutes'] is num
        ? (data['estimatedMinutes'] as num).toInt()
        : null;
    final category = data['category']?.toString() ??
        (data['type']?.toString() == 'assignment' ? 'Assignment' : 'Practice');

    return AppPriorityTaskCard(
      title: title,
      subtitle: topic,
      durationMinutes: duration,
      category: category,
      categoryTint: CategoryTint.resolve('$title $topic $category'),
      icon: _iconForCategory(category, title),
      onTap: () => widget.onOpenDestination(2),
      onComplete: () async {
        // Canonical completion: update doc, cancel reminder
        try {
          await doc.reference.update({
            'done': true,
            'completed': true,
            'completedAt': FieldValue.serverTimestamp(),
          });
          await NotificationService.cancelTask(doc.id);
        } catch (_) {}
      },
    );
  }

  IconData _iconForCategory(String category, String title) {
    final lower = '$category $title'.toLowerCase();
    if (lower.contains('math') || lower.contains('গণিত')) {
      return Icons.functions_rounded;
    }
    if (lower.contains('physic') || lower.contains('পদার্থ')) {
      return Icons.description_rounded;
    }
    if (lower.contains('chem') || lower.contains('রসায়ন')) {
      return Icons.science_rounded;
    }
    return Icons.menu_book_rounded;
  }

  // ---------------------------------------------------------------------------
  // 5. Ziku Coach + Focus Session
  // ---------------------------------------------------------------------------
  Widget _buildZikuAndFocusSection(BuildContext context) {
    final coach = widget.bootstrapData?['coach'];
    final isCoachAvailable = coach is Map<String, dynamic> && coach['available'] != false;
    final coachHeadline = isCoachAvailable ? coach['headline']?.toString() : null;
    final coachMessage = coachHeadline != null && coachHeadline.isNotEmpty
        ? coachHeadline
        : GochanoLanguage.text(
            "Today's plan is clear and achievable! 🎯 Focus on one step at a time.",
            'আজকের প্ল্যান প্রস্তুত! একটি করে ধাপে এগিয়ে চলুন।',
          );

    final focus = widget.bootstrapData?['focus'];
    final focusNudge = focus is Map<String, dynamic>
        ? focus['nudge']?.toString()
        : null;
    final focusSubtitle = focusNudge != null && focusNudge.isNotEmpty
        ? focusNudge
        : 'Deep work. Real progress.';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 380;

        final coachWidget = AppCoachCard(
          message: coachMessage,
          onTap: () {
            Navigator.of(context).push(
              GochanoRoute.to(
                builder: (_) => CoachDashboardScreen(
                  briefFn: () async => coach is Map<String, dynamic> ? coach : {},
                  onOpenPlan: widget.onOpenDestination,
                ),
              ),
            );
          },
          onCta: () {
            ZikuAssistantPanel.show(context, currentDestination: 'today');
          },
        );

        final focusWidget = AppFocusCard(
          timerDisplay: '25:00',
          statusSubtitle: focusSubtitle,
          ctaLabel: GochanoLanguage.text('Start Focus Session', 'ফোকাস সেশন শুরু করুন'),
          onTap: () {
            Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const FocusSessionScreen()),
            );
          },
          onStart: () {
            Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const FocusSessionScreen()),
            );
          },
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: coachWidget),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(child: focusWidget),
            ],
          );
        }

        return Column(
          children: [
            coachWidget,
            const SizedBox(height: GochanoSpacing.sm),
            focusWidget,
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Continue Learning
  // ---------------------------------------------------------------------------
  Widget _buildContinueLearningSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionHeader(
          icon: Icons.menu_book_rounded,
          iconColor: const Color(0xFF2563EB),
          title: GochanoLanguage.text('Continue Learning', 'পড়া চালিয়ে যান'),
          actionLabel: GochanoLanguage.text('See All', 'সব দেখুন'),
          onAction: () => widget.onOpenDestination(1), // Workspace tab
        ),
        const SizedBox(height: GochanoSpacing.xs),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('materials', limit: 10),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppSkeleton(height: 75);
            }

            final docs = snapshot.data?.docs ?? const [];
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GochanoSpacing.md),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? context.colors.surface
                      : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border.all(
                    color: context.colors.border,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.library_books_rounded,
                        color: Color(0xFF2563EB),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            GochanoLanguage.text(
                              'No recent material yet',
                              'সাম্প্রতিক কোনো ফাইল নেই',
                            ),
                            style: context.type.cardHeading.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            GochanoLanguage.text(
                              'Upload a note or PDF in Workspace to start.',
                              'ওয়ার্কস্পেস থেকে নোট বা পিডিএফ যুক্ত করুন।',
                            ),
                            style: context.type.bodySecondary.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    ElevatedButton(
                      onPressed: () => widget.onOpenDestination(1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F6BFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.sm,
                          vertical: GochanoSpacing.xs,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: Text(
                        GochanoLanguage.text('Workspace', 'ওয়ার্কস্পেস'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }

            final latestDoc = docs.first;
            final data = latestDoc.data();
            final title = (data['title']?.toString().trim().isNotEmpty ?? false)
                ? data['title'].toString()
                : data['fileName']?.toString() ?? 'Study Material';
            final subject = data['subject']?.toString() ??
                data['category']?.toString() ??
                'Learning Note';

            // Honest progress: only show progress if genuinely present
            final rawProgress = data['progressFraction'];
            final double? progress = rawProgress is num
                ? rawProgress.toDouble()
                : null;
            final String? progressLabel =
                progress != null ? '${(progress * 100).toInt()}%' : null;

            return AppContinueLearningCard(
              title: title,
              subtitle: subject,
              progressFraction: progress,
              progressLabel: progressLabel,
              onTap: () {
                Navigator.of(context).push(
                  GochanoRoute.to(
                    builder: (_) => MaterialReaderScreen(
                      materialId: latestDoc.id,
                      title: title,
                      mimeType: data['mimeType']?.toString() ?? '',
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. Simplified Academic Health
  // ---------------------------------------------------------------------------
  Widget _buildAcademicHealthSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionHeader(
          icon: Icons.bar_chart_rounded,
          iconColor: const Color(0xFF10B981),
          title: GochanoLanguage.text('Academic Health', 'একাডেমিক হেলথ'),
          actionLabel: GochanoLanguage.text('View Details', 'বিস্তারিত দেখুন'),
          onAction: () {
            Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const AcademicHealthScreen()),
            );
          },
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Builder(
          builder: (context) {
            final health = widget.bootstrapData?['academicHealth'];
            final hasData = health is Map<String, dynamic>
                ? health['hasData'] == true
                : true;
            final score = health is Map<String, dynamic> && health['score'] is num
                ? (health['score'] as num).toInt()
                : 78;
            final headline = health is Map<String, dynamic> &&
                    health['headline']?.toString().isNotEmpty == true
                ? health['headline'].toString()
                : GochanoLanguage.text("You're on track! 🎯", 'আপনি সঠিক পথে আছেন! 🎯');

            return AppSimplifiedAcademicHealthCard(
              score: score,
              hasData: hasData,
              headline: headline,
              subtitle: GochanoLanguage.text(
                'Keep up the consistent study and practice.',
                'নিয়মিত অনুশীলন এবং পড়াশোনা চালিয়ে যান।',
              ),
              strongestMetric: GochanoLanguage.text(
                'Focus Consistency +12%',
                'ফোকাস বৃদ্ধি +১২%',
              ),
              attentionOrStreakMetric: GochanoLanguage.text(
                'Study Streak 3 days',
                'স্টাডি স্ট্রিক ৩ দিন',
              ),
              onTap: () {
                Navigator.of(context).push(
                  GochanoRoute.to(builder: (_) => const AcademicHealthScreen()),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
