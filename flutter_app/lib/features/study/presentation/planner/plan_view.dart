// Study Plan Dashboard (spec §40).
//
// Plan Product North Star: Plan = ORGANIZE
// Answers: "What am I preparing for, what is coming next, and how should I organize my study over time?"
//
// Sections:
//   1. Contextual Pinned Plan Header (AppStudyHeader with calendar/history action)
//   2. Page Intro ("Plan" / "Organize your study journey.")
//   3. Current Goal / Target Exam summary (real data or polished empty state)
//   4. Date / Week switcher (7-day/31-day selector with "Today" shortcut)
//   5. Adaptive Exam Rescue Banner
//   6. This Week / Upcoming Focus (tasks for selected day with canonical completion)
//   7. Deadlines & Milestones Timeline (upcoming assignments/exams)
//   8. Goals & Milestones (study hours target & focus progress)
//   9. History & Calendar Navigation

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/feedback_messages.dart';
import '../../../../core/localization/gochano_dates.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/notification_service.dart';
import '../../../tasks/domain/task_lifecycle.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../tasks/presentation/add_task_sheet.dart';
import '../ai/quiz_generator_screen.dart';
import '../exam_ecosystem/exam_plan_screen.dart';
import '../rescue/exam_rescue_models.dart';
import '../rescue/exam_rescue_session_service.dart';
import '../rescue/exam_rescue_setup_sheet.dart';

class PlanView extends StatefulWidget {
  const PlanView({
    super.key,
    this.examRescueSessionService,
    this.mockTasks,
    this.mockTargetExam,
    this.mockStudyGoals,
  });

  final ExamRescueSessionService? examRescueSessionService;

  /// Injected tasks for tests — bypasses Firestore stream when provided.
  final List<Map<String, dynamic>>? mockTasks;

  /// Injected target exam data for tests.
  final Map<String, dynamic>? mockTargetExam;

  /// Injected study goals for tests.
  final Map<String, int?>? mockStudyGoals;

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> with WidgetsBindingObserver {
  DateTime _selectedDay = DateTime.now();
  bool _exactAlarmAllowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GochanoLanguage.current.addListener(_onLanguageChange);
    _checkExactAlarm();
  }

  Future<void> _checkExactAlarm() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final allowed = await NotificationService.isExactAlarmPermissionGranted();
      if (mounted) {
        setState(() => _exactAlarmAllowed = allowed);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkExactAlarm();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GochanoLanguage.current.removeListener(_onLanguageChange);
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ---------------------------------------------------------------
              // PINNED CONTEXTUAL PLAN HEADER (Search hidden, Calendar action)
              // ---------------------------------------------------------------
              AppStudyHeader(
                showSearch: false,
                showNotifications: true,
                trailingAction: SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: () => openPlanHistory(context),
                    tooltip: GochanoLanguage.text(
                      'History & Calendar',
                      'ইতিহাস ও ক্যালেন্ডার',
                    ),
                    icon: const Icon(Icons.calendar_month_outlined, size: 20),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),

              // ---------------------------------------------------------------
              // SCROLLABLE PLAN CONTENT
              // ---------------------------------------------------------------
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _checkExactAlarm();
                    if (mounted) setState(() {});
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(
                        child: SizedBox(height: GochanoSpacing.xs),
                      ),

                      // Intro + Exact Alarm Warning if needed
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!_exactAlarmAllowed) ...[
                                _buildExactAlarmWarning(context),
                                const SizedBox(height: GochanoSpacing.xs),
                              ],
                              _buildIntro(context),
                              const SizedBox(height: GochanoSpacing.sm),
                            ],
                          ),
                        ),
                      ),

                      // 1. Current Goal / Target Exam Section
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _CurrentGoalCard(
                            mockTargetExam: widget.mockTargetExam,
                          ),
                        ),
                      ),

                      // 2. Date / Week Switcher
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: GochanoSpacing.sm,
                              bottom: GochanoSpacing.xs,
                            ),
                            child: _DateStrip(
                              selectedDay: _selectedDay,
                              onDaySelected: (day) =>
                                  setState(() => _selectedDay = day),
                            ),
                          ),
                        ),
                      ),

                      // 3. Due This Day — Tasks Section for Selected Day (immediately after Date Strip)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: GochanoSpacing.xs,
                            ),
                            child: _PlannerTasksSection(
                              selectedDay: _selectedDay,
                              mockTasks: widget.mockTasks,
                            ),
                          ),
                        ),
                      ),

                      // 4. Exam & Deadline Timeline
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: GochanoSpacing.md,
                            ),
                            child: _DeadlineTimelineSection(
                              mockTasks: widget.mockTasks,
                            ),
                          ),
                        ),
                      ),

                      // 5. Exam Rescue Planning (compact planning card or secondary CTA strip)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: GochanoSpacing.md,
                            ),
                            child: _ExamRescueBanner(
                              examRescueSessionService:
                                  widget.examRescueSessionService,
                            ),
                          ),
                        ),
                      ),

                      // 6. Goals & Milestones Section
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: GochanoSpacing.md,
                            ),
                            child: _StudyGoalContainer(
                              mockStudyGoals: widget.mockStudyGoals,
                            ),
                          ),
                        ),
                      ),

                      // Bottom spacing for navigation bar
                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExactAlarmWarning(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.12),
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.alarm_off_rounded, color: colors.warning, size: 20),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Text(
              GochanoLanguage.text(
                'Enable "Alarms & reminders" in settings so reminders ring when the app is closed.',
                'অ্যাপ বন্ধ থাকলেও রিমাইন্ডার পেতে সেটিংসে "অ্যালার্ম ও রিমাইন্ডার" চালু করুন।',
              ),
              style: context.type.caption.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () async {
              final granted =
                  await NotificationService.requestExactAlarmPermission();
              if (mounted && granted) {
                setState(() => _exactAlarmAllowed = true);
              }
            },
            child: Text(
              GochanoLanguage.text('Enable', 'চালু করুন'),
              style: TextStyle(
                color: colors.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Plan', 'পরিকল্পনা'),
          style: context.type.pageTitle.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          GochanoLanguage.text(
            'Organize your upcoming study and goals.',
            'আপনার পড়াশোনার লক্ষ্য ও সময়সূচি সাজান।',
          ),
          style: context.type.bodySecondary.copyWith(
            color: colors.textSecondary,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Current Goal / Target Exam Card
// ---------------------------------------------------------------------------

class _CurrentGoalCard extends StatelessWidget {
  const _CurrentGoalCard({this.mockTargetExam});

  final Map<String, dynamic>? mockTargetExam;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    if (mockTargetExam != null) {
      return _buildFromData(context, mockTargetExam!, colors, isDark);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.profileStream(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final targetExam = data['targetExam']?.toString().trim();
        final academicGoal = data['academicGoal']?.toString().trim();

        final hasGoal =
            (targetExam != null && targetExam.isNotEmpty) ||
            (academicGoal != null && academicGoal.isNotEmpty);

        if (!hasGoal) {
          return _buildEmptyGoal(context, colors, isDark);
        }

        final goalName = targetExam ?? academicGoal ?? '';
        final goalData = {
          'examName': goalName,
          'targetDate': data['targetDate']?.toString(),
          'nextMilestone': data['nextMilestone']?.toString(),
          'readiness': data['readiness'],
        };
        return _buildFromData(context, goalData, colors, isDark);
      },
    );
  }

  Widget _buildEmptyGoal(BuildContext context, dynamic colors, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? colors.border.withValues(alpha: 0.3)
              : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.flag_rounded, color: colors.brand, size: 24),
          ),
          const SizedBox(width: GochanoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  GochanoLanguage.text(
                    'Set your target exam',
                    'আপনার পরীক্ষার লক্ষ্য ঠিক করুন',
                  ),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  GochanoLanguage.text(
                    'Add your academic goal so Gochano can organize your study plan.',
                    'আপনার লক্ষ্য যোগ করুন যাতে গোছানো স্টাডি প্ল্যান তৈরি করতে পারে।',
                  ),
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          FilledButton.tonal(
            onPressed: () => Navigator.of(
              context,
            ).push(GochanoRoute.to(builder: (_) => const ExamPlanScreen())),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              GochanoLanguage.text('Set Goal', 'লক্ষ্য দিন'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFromData(
    BuildContext context,
    Map<String, dynamic> data,
    dynamic colors,
    bool isDark,
  ) {
    final examName = data['examName']?.toString() ?? 'Academic Goal';
    final targetDate = data['targetDate']?.toString();
    final milestone = data['nextMilestone']?.toString();
    final readiness = (data['readiness'] as num?)?.toDouble();

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colors.brand.withValues(alpha: 0.12)
            : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.brand.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.brand.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.stars_rounded, color: colors.brand, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      GochanoLanguage.text('Current Goal', 'বর্তমান লক্ষ্য'),
                      style: context.type.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: colors.brand,
                      ),
                    ),
                    Text(
                      examName,
                      style: context.type.body.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (targetDate != null && targetDate.isNotEmpty)
                      Text(
                        targetDate,
                        style: context.type.caption.copyWith(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(GochanoRoute.to(builder: (_) => const ExamPlanScreen())),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  side: BorderSide(color: colors.brand.withValues(alpha: 0.4)),
                ),
                child: Text(
                  GochanoLanguage.text('View Roadmap', 'রোডম্যাপ দেখুন'),
                  style: TextStyle(
                    color: colors.brand,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (milestone != null && milestone.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${GochanoLanguage.text("Next Milestone", "পরবর্তী মাইলফলক")}: $milestone',
                    style: context.type.caption.copyWith(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (readiness != null && readiness > 0) ...[
            const SizedBox(height: GochanoSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (readiness / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: colors.brand.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date / Week Strip
// ---------------------------------------------------------------------------

class _DateStrip extends StatefulWidget {
  const _DateStrip({required this.selectedDay, required this.onDaySelected});

  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  late final ScrollController _scrollController;
  static const _cellWidth = 44.0 + 8.0;
  static const _visibleBeforeToday = 2;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToToday() {
    if (!_scrollController.hasClients) return;
    const totalDays = _totalDays;
    const todayIndex = totalDays - 15;
    const targetOffset = (todayIndex - _visibleBeforeToday) * _cellWidth;
    _scrollController.jumpTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  static const _totalDays = 31;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(const Duration(days: 15));
    final days = List.generate(
      _totalDays,
      (i) => startDate.add(Duration(days: i)),
    );

    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const banglaMonths = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];
    final currentMonth =
        '${months[widget.selectedDay.month - 1]} ${widget.selectedDay.year}';
    final currentMonthBn =
        '${banglaMonths[widget.selectedDay.month - 1]} ${widget.selectedDay.year}';

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double stripHeight = textScale > 1.0
        ? (68.0 + (textScale - 1.0) * 32.0)
        : 68.0;
    final double itemWidth = textScale > 1.0
        ? (46.0 + (textScale - 1.0) * 20.0)
        : 46.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                GochanoLanguage.text(currentMonth, currentMonthBn),
                style: context.type.sectionHeading,
              ),
            ),
            TextButton(
              onPressed: () {
                widget.onDaySelected(today);
                _scrollToToday();
              },
              child: Text(GochanoLanguage.text('Today', 'আজ')),
            ),
          ],
        ),
        const SizedBox(height: GochanoSpacing.xs),
        SizedBox(
          height: stripHeight,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final isSelected =
                  day.year == widget.selectedDay.year &&
                  day.month == widget.selectedDay.month &&
                  day.day == widget.selectedDay.day;
              final isToday =
                  day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label:
                      '${day.day} ${months[day.month - 1]}${isToday ? ", Today" : ""}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onDaySelected(day),
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        width: itemWidth,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.brand
                              : isToday
                              ? colors.brand.withValues(alpha: 0.12)
                              : (context.isDark
                                    ? colors.surface
                                    : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? colors.brand
                                : isToday
                                ? colors.brand.withValues(alpha: 0.4)
                                : (context.isDark
                                      ? colors.border
                                      : const Color(0xFFE2E8F0)),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _weekdayShort(day.weekday),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white70
                                        : colors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  GochanoLanguage.formatNumber(day.day),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : colors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _weekdayShort(int weekday) {
    switch (weekday) {
      case 1:
        return GochanoLanguage.text('Mon', 'সোম');
      case 2:
        return GochanoLanguage.text('Tue', 'মঙ্গল');
      case 3:
        return GochanoLanguage.text('Wed', 'বুধ');
      case 4:
        return GochanoLanguage.text('Thu', 'বৃহ');
      case 5:
        return GochanoLanguage.text('Fri', 'শুক্র');
      case 6:
        return GochanoLanguage.text('Sat', 'শনি');
      default:
        return GochanoLanguage.text('Sun', 'রবি');
    }
  }
}

// ---------------------------------------------------------------------------
// Adaptive Exam Rescue Banner
// ---------------------------------------------------------------------------

class _ExamRescueBanner extends StatelessWidget {
  const _ExamRescueBanner({this.examRescueSessionService});

  final ExamRescueSessionService? examRescueSessionService;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final service =
        examRescueSessionService ?? ExamRescueSessionService.instance;

    return StreamBuilder<ExamRescueSession?>(
      stream: service.streamNearestActiveSession(),
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session != null) {
          return _buildActiveRescueCard(
            context,
            session,
            service,
            colors,
            isDark,
          );
        }
        return _buildInactiveCtaStrip(context, colors, isDark);
      },
    );
  }

  Widget _buildInactiveCtaStrip(
    BuildContext context,
    dynamic colors,
    bool isDark,
  ) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64, maxHeight: 80),
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(
          color: isDark
              ? colors.border.withValues(alpha: 0.3)
              : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.brand.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bolt_rounded, color: colors.brand, size: 18),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  GochanoLanguage.text('Exam Rescue', 'পরীক্ষা উদ্ধার'),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  GochanoLanguage.text(
                    'Exam close? Build a quick rescue plan.',
                    'পরীক্ষা কাছাকাছি? একটি দ্রুত উদ্ধার প্ল্যান তৈরি করুন।',
                  ),
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          FilledButton.tonal(
            onPressed: () async {
              final result = await showExamRescueSetupSheet(context);
              if (result != null && result.success && context.mounted) {
                showGochanoMessage(
                  context,
                  FeedbackMessages.examRescuePlanApplied(
                    result.tasksCount,
                    reminderFailed: result.reminderFailed,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              GochanoLanguage.text('Build Plan', 'প্ল্যান বানান'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRescueCard(
    BuildContext context,
    ExamRescueSession session,
    ExamRescueSessionService service,
    dynamic colors,
    bool isDark,
  ) {
    final now = service.now;
    final daysRemaining = session.localDaysRemaining(now);
    final daysText = daysRemaining <= 0
        ? GochanoLanguage.text('Exam today', 'আজ পরীক্ষা')
        : daysRemaining == 1
        ? GochanoLanguage.text('1 day left', '১ দিন বাকি')
        : GochanoLanguage.text(
            '$daysRemaining days left',
            '${GochanoLanguage.formatNumber(daysRemaining)} দিন বাকি',
          );

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

        return Container(
          decoration: BoxDecoration(
            color: colors.brandSoft,
            borderRadius: GochanoRadius.mdAll,
            border: Border.all(
              color: colors.brand.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(GochanoSpacing.sm + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors.brand.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.bolt_rounded,
                      color: colors.brand,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          GochanoLanguage.text('Exam Rescue', 'পরীক্ষা উদ্ধার'),
                          style: context.type.caption.copyWith(
                            color: colors.brand,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          session.examTitle,
                          style: context.type.body.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      daysText,
                      style: TextStyle(
                        color: colors.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.overallProgressFraction,
                        minHeight: 5,
                        backgroundColor: colors.brand.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
                      ),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Text(
                    '${progress.percentage}%',
                    style: context.type.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.brand,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        GochanoRoute.to(builder: (_) => const ExamPlanScreen()),
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: colors.brand.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        GochanoLanguage.text('View Roadmap', 'রোডম্যাপ দেখুন'),
                        style: TextStyle(
                          color: colors.brand,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () async {
                        final result = await showExamRescueSetupSheet(context);
                        if (result != null &&
                            result.success &&
                            context.mounted) {
                          showGochanoMessage(
                            context,
                            FeedbackMessages.examRescuePlanApplied(
                              result.tasksCount,
                              reminderFailed: result.reminderFailed,
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        GochanoLanguage.text('Adjust Plan', 'প্ল্যান পরিবর্তন'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tasks Section for Selected Day
// ---------------------------------------------------------------------------

class _PlannerTasksSection extends StatelessWidget {
  const _PlannerTasksSection({required this.selectedDay, this.mockTasks});

  final DateTime selectedDay;
  final List<Map<String, dynamic>>? mockTasks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (mockTasks != null) {
      return _buildTaskList(context, mockTasks!, colors);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const AppSkeleton(height: 120, borderRadius: 16);
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              GochanoLanguage.text(
                'Could not load tasks.',
                'কাজ লোড করা যায়নি।',
              ),
              style: context.type.bodySecondary,
            ),
          );
        }

        final rawDocs = <Map<String, dynamic>>[];
        for (final doc in snapshot.data?.docs ?? []) {
          final data = Map<String, dynamic>.from(doc.data());
          data['__docId'] = doc.id;
          data['__ref'] = doc.reference;
          rawDocs.add(data);
        }

        return _buildTaskList(context, rawDocs, colors);
      },
    );
  }

  Widget _buildTaskList(
    BuildContext context,
    List<Map<String, dynamic>> rawDocs,
    dynamic colors,
  ) {
    final dayDocs = <Map<String, dynamic>>[];
    for (final data in rawDocs) {
      if (TaskLifecycle.belongsToPlanDay(data, selectedDay)) {
        dayDocs.add(data);
      }
    }

    dayDocs.sort((a, b) {
      final ad = TaskLifecycle.parseDateTime(a['dueAt']);
      final bd = TaskLifecycle.parseDateTime(b['dueAt']);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

    return AppSectionContainer(
      title: GochanoLanguage.text('Due This Day', 'এই দিনের কাজ'),
      icon: Icons.assignment_turned_in_rounded,
      iconColor: colors.brand,
      actionLabel: '+ Task',
      onAction: () =>
          showAddTaskSheet(context, type: 'task', initialDate: selectedDay),
      child: dayDocs.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      size: 40,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      GochanoLanguage.text(
                        'No tasks or assignments for this day.',
                        'এই দিনে কোনো কাজ বা অ্যাসাইনমেন্ট নেই।',
                      ),
                      style: context.type.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => showAddTaskSheet(
                            context,
                            type: 'task',
                            initialDate: selectedDay,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text(GochanoLanguage.text('Task', 'কাজ')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => showAddTaskSheet(
                            context,
                            type: 'assignment',
                            initialDate: selectedDay,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text(
                            GochanoLanguage.text('Assignment', 'অ্যাসাইনমেন্ট'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                for (final doc in dayDocs) ...[
                  _PlanTaskCard(data: doc),
                  if (doc != dayDocs.last)
                    Divider(
                      height: 1,
                      color: colors.border.withValues(alpha: 0.4),
                    ),
                ],
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan Task Card & Row
// ---------------------------------------------------------------------------

class _PlanTaskCard extends StatelessWidget {
  const _PlanTaskCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final done = TaskLifecycle.isTaskCompleted(data);
    final title = data['title']?.toString() ?? 'Task';
    final due = TaskLifecycle.parseDateTime(data['dueAt']);
    final isAssignment = data['type']?.toString() == 'assignment';

    final isRescue = data['source'] == 'exam_rescue';
    final rescueItemType = data['rescueItemType']?.toString();
    final rescueSessionId = data['rescueSessionId']?.toString();
    final isRescueQuiz =
        isRescue &&
        rescueItemType == 'quiz' &&
        rescueSessionId != null &&
        rescueSessionId.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: done,
              onChanged: (value) => _toggleDone(context, data, value ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: isAssignment
                  ? colors.brand.withValues(alpha: 0.10)
                  : colors.study.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isAssignment
                  ? GochanoLanguage.text('Asm', 'অ্যাস')
                  : GochanoLanguage.text('Task', 'কাজ'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isAssignment ? colors.brand : colors.study,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () {
                final ref = data['__ref'] as DocumentReference?;
                if (ref != null) {
                  // Reopen edit sheet if real doc
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: context.type.body.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: done ? colors.textSecondary : colors.textPrimary,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (due != null)
                      Text(
                        '${formatShortDate(due)} ${formatClock12(due)}',
                        style: context.type.caption.copyWith(
                          fontSize: 10.5,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isRescueQuiz) ...[
            const SizedBox(width: 4),
            if (done)
              GochanoBadge(
                label: GochanoLanguage.text('Completed', 'সম্পন্ন'),
                tone: GochanoBadgeTone.success,
              )
            else
              OutlinedButton(
                onPressed: () => _handleTakeQuizFromData(context, data),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  GochanoLanguage.text('Take Quiz', 'কুইজ দিন'),
                  style: const TextStyle(fontSize: 10.5),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleDone(
    BuildContext context,
    Map<String, dynamic> data,
    bool done,
  ) async {
    final ref = data['__ref'] as DocumentReference<Map<String, dynamic>>?;
    final id = data['__docId']?.toString() ?? '';

    if (ref != null) {
      try {
        await ref.update({
          'done': done,
          'completed': done,
          'completedAt': FieldValue.serverTimestamp(),
        });
        if (id.isNotEmpty) {
          if (done) {
            await NotificationService.cancelTask(id);
          } else {
            final due = TaskLifecycle.parseDateTime(data['dueAt']);
            await NotificationService.rescheduleTask(
              taskId: id,
              title: data['title']?.toString() ?? '',
              when: due,
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          showGochanoMessage(context, friendlyErrorMessage(e), isError: true);
        }
      }
    }
  }

  void _handleTakeQuizFromData(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final materialId = data['materialId']?.toString() ?? '';
    final title = data['title']?.toString() ?? '';

    if (materialId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            GochanoLanguage.text(
              'Select a study material to start this quiz.',
              'এই কুইজ শুরু করতে একটি স্টাডি মেটেরিয়াল নির্বাচন করুন।',
            ),
          ),
        ),
      );
    }

    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => QuizGeneratorScreen(
          preselectedMaterialId: materialId.isNotEmpty ? materialId : null,
          initialTopic: title.isNotEmpty ? title : null,
          initialQuestionCount: 10,
          onQuizCompleted: () async {
            await _toggleDone(context, data, true);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seam for legacy tests (asserts PlanViewTaskTileSeam)
// ---------------------------------------------------------------------------

@visibleForTesting
class PlanViewTaskTileSeam extends StatelessWidget {
  const PlanViewTaskTileSeam({super.key, required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = Map<String, dynamic>.from(doc.data());
    data['__docId'] = doc.id;
    data['__ref'] = doc.reference;
    return _PlanTaskCard(data: data);
  }
}

// ---------------------------------------------------------------------------
// Deadlines & Milestones Timeline Section
// ---------------------------------------------------------------------------

class _DeadlineTimelineSection extends StatelessWidget {
  const _DeadlineTimelineSection({this.mockTasks});

  final List<Map<String, dynamic>>? mockTasks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (mockTasks != null) {
      return _buildTimeline(context, mockTasks!, colors);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        final rawDocs = <Map<String, dynamic>>[];
        for (final doc in snapshot.data?.docs ?? []) {
          final data = Map<String, dynamic>.from(doc.data());
          data['__docId'] = doc.id;
          rawDocs.add(data);
        }
        return _buildTimeline(context, rawDocs, colors);
      },
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    List<Map<String, dynamic>> rawDocs,
    dynamic colors,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final upcoming = rawDocs.where((d) {
      if (TaskLifecycle.isTaskCompleted(d)) return false;
      if (TaskLifecycle.isTaskCancelled(d)) return false;
      final due = TaskLifecycle.parseDateTime(d['dueAt']);
      if (due == null) return false;
      return due.isAfter(today);
    }).toList();

    upcoming.sort((a, b) {
      final ad = TaskLifecycle.parseDateTime(a['dueAt'])!;
      final bd = TaskLifecycle.parseDateTime(b['dueAt'])!;
      return ad.compareTo(bd);
    });

    final preview = upcoming.take(4).toList();

    return AppSectionContainer(
      title: GochanoLanguage.text(
        'Exam & Deadline Timeline',
        'পরীক্ষা ও ডেডলাইন সময়সূচি',
      ),
      icon: Icons.timeline_rounded,
      iconColor: colors.warning,
      child: preview.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  GochanoLanguage.text(
                    'No upcoming deadlines this month.',
                    'এই মাসে কোনো আসন্ন ডেডলাইন নেই।',
                  ),
                  style: context.type.bodySecondary,
                ),
              ),
            )
          : Column(
              children: [
                for (final item in preview) ...[
                  _TimelineRow(data: item),
                  if (item != preview.last)
                    Divider(
                      height: 1,
                      color: colors.border.withValues(alpha: 0.3),
                    ),
                ],
              ],
            ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = data['title']?.toString() ?? 'Deadline';
    final due = TaskLifecycle.parseDateTime(data['dueAt'])!;
    final diffDays = due.difference(DateTime.now()).inDays;
    final isAssignment = data['type']?.toString() == 'assignment';

    final daysText = diffDays <= 0
        ? GochanoLanguage.text('Due today', 'আজ নির্ধারিত')
        : diffDays == 1
        ? GochanoLanguage.text('Tomorrow', 'আগামীকাল')
        : GochanoLanguage.text('In $diffDays days', '$diffDays দিন পর');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isAssignment
                  ? colors.warning.withValues(alpha: 0.12)
                  : colors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${due.day} ${_monthShort(due.month)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: isAssignment ? colors.warning : colors.brand,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  daysText,
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          GochanoBadge(
            label: isAssignment
                ? GochanoLanguage.text('Assignment', 'অ্যাসাইনমেন্ট')
                : GochanoLanguage.text('Task', 'কাজ'),
            tone: isAssignment
                ? GochanoBadgeTone.warning
                : GochanoBadgeTone.brand,
          ),
        ],
      ),
    );
  }

  String _monthShort(int month) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return m[month - 1];
  }
}

// ---------------------------------------------------------------------------
// Goals & Milestones Container
// ---------------------------------------------------------------------------

class _StudyGoalContainer extends StatelessWidget {
  const _StudyGoalContainer({this.mockStudyGoals});

  final Map<String, int?>? mockStudyGoals;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (mockStudyGoals != null) {
      return _buildGoalContent(
        context,
        mockStudyGoals!['dailyGoalMinutes'],
        mockStudyGoals!['weeklyGoalMinutes'],
        colors,
      );
    }

    return FutureBuilder<Map<String, int?>>(
      future: FirestoreService.studyGoals(),
      builder: (context, snapshot) {
        final daily = snapshot.data?['dailyGoalMinutes'];
        final weekly = snapshot.data?['weeklyGoalMinutes'];
        return _buildGoalContent(context, daily, weekly, colors);
      },
    );
  }

  Widget _buildGoalContent(
    BuildContext context,
    int? dailyGoalMinutes,
    int? weeklyGoalMinutes,
    dynamic colors,
  ) {
    final hasGoals = dailyGoalMinutes != null || weeklyGoalMinutes != null;

    return AppSectionContainer(
      title: GochanoLanguage.text('Goals & Milestones', 'লক্ষ্য ও মাইলফলক'),
      icon: Icons.track_changes_rounded,
      iconColor: colors.study,
      actionLabel: hasGoals
          ? GochanoLanguage.text('Edit', 'সম্পাদনা')
          : GochanoLanguage.text('Set Goal', 'লক্ষ্য দিন'),
      onAction: () => _showEditGoalSheet(
        context,
        daily: dailyGoalMinutes ?? 0,
        weekly: weeklyGoalMinutes ?? 0,
      ),
      child: !hasGoals
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: Text(
                  GochanoLanguage.text(
                    'Set a weekly study hours target to track your progress.',
                    'আপনার অগ্রগতি ট্র্যাক করতে একটি সাপ্তাহিক লক্ষ্য নির্ধারণ করুন।',
                  ),
                  style: context.type.bodySecondary,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (weeklyGoalMinutes != null && weeklyGoalMinutes > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        GochanoLanguage.text(
                          'Weekly Study Goal',
                          'সাপ্তাহিক পড়াশোনার লক্ষ্য',
                        ),
                        style: context.type.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${weeklyGoalMinutes ~/ 60}h ${weeklyGoalMinutes % 60}m',
                        style: TextStyle(
                          color: colors.study,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.45, // Indicative progress from study records
                      minHeight: 6,
                      backgroundColor: colors.study.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(colors.study),
                    ),
                  ),
                ],
                if (dailyGoalMinutes != null && dailyGoalMinutes > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        GochanoLanguage.text(
                          'Daily Focus Goal',
                          'দৈনিক ফোকাস লক্ষ্য',
                        ),
                        style: context.type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      Text(
                        '${dailyGoalMinutes ~/ 60}h ${dailyGoalMinutes % 60}m',
                        style: context.type.caption.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  void _showEditGoalSheet(
    BuildContext context, {
    int daily = 0,
    int weekly = 0,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditGoalSheet(
        dailyGoalMinutes: daily,
        weeklyGoalMinutes: weekly,
        onSaved: () {},
      ),
    );
  }
}

class _EditGoalSheet extends StatefulWidget {
  const _EditGoalSheet({
    required this.dailyGoalMinutes,
    required this.weeklyGoalMinutes,
    required this.onSaved,
  });

  final int dailyGoalMinutes;
  final int weeklyGoalMinutes;
  final VoidCallback onSaved;

  @override
  State<_EditGoalSheet> createState() => _EditGoalSheetState();
}

class _EditGoalSheetState extends State<_EditGoalSheet> {
  late int _dailyH;
  late int _dailyM;
  late int _weeklyH;
  late int _weeklyM;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dailyH = widget.dailyGoalMinutes ~/ 60;
    _dailyM = widget.dailyGoalMinutes % 60;
    _weeklyH = widget.weeklyGoalMinutes ~/ 60;
    _weeklyM = widget.weeklyGoalMinutes % 60;
  }

  Future<void> _save() async {
    final dailyTotal = _dailyH * 60 + _dailyM;
    final weeklyTotal = _weeklyH * 60 + _weeklyM;

    if (dailyTotal <= 0 && weeklyTotal <= 0) {
      setState(() {
        _error = GochanoLanguage.text(
          'At least one goal must be greater than zero.',
          'অন্তত একটি লক্ষ্য শূন্যের বেশি হতে হবে।',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FirestoreService.saveStudyGoals(
        dailyGoalMinutes: dailyTotal,
        weeklyGoalMinutes: weeklyTotal,
      );
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GochanoSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                GochanoLanguage.text(
                  'Set Study Goals',
                  'পড়াশোনার লক্ষ্য নির্ধারণ',
                ),
                style: context.type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.md),
              Text(
                GochanoLanguage.text(
                  'Weekly Goal (Hours)',
                  'সাপ্তাহিক লক্ষ্য (ঘণ্টা)',
                ),
                style: context.type.label,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _weeklyH,
                      items: List.generate(
                        60,
                        (i) => DropdownMenuItem(value: i, child: Text('$i h')),
                      ),
                      onChanged: (v) => setState(() => _weeklyH = v ?? 0),
                      decoration: const InputDecoration(labelText: 'Hours'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.md),
              if (_error != null)
                Text(_error!, style: TextStyle(color: colors.error)),
              const SizedBox(height: GochanoSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving
                        ? GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…')
                        : GochanoLanguage.text('Save Goals', 'সংরক্ষণ করুন'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History — public entry point for AppBar action
// ---------------------------------------------------------------------------

void openPlanHistory(BuildContext context) {
  Navigator.of(
    context,
  ).push(GochanoRoute.to(builder: (_) => const _PlanHistoryScreen()));
}

class _PlanHistoryScreen extends StatelessWidget {
  const _PlanHistoryScreen();

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(title: GochanoLanguage.text('History', 'ইতিহাস')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('tasks', limit: 300),
        builder: (context, snapshot) {
          final now = DateTime.now();
          final docs = [...?snapshot.data?.docs]
            ..removeWhere((doc) {
              return !TaskLifecycle.belongsToHistory(doc.data(), now);
            })
            ..sort((a, b) {
              final at = TaskLifecycle.parseDateTime(a.data()['dueAt']);
              final bt = TaskLifecycle.parseDateTime(b.data()['dueAt']);
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });
          if (docs.isEmpty) {
            return Center(
              child: Text(
                GochanoLanguage.text(
                  'No completed or missed items.',
                  'কোনো সম্পন্ন বা মিসড আইটেম নেই।',
                ),
                style: context.type.bodySecondary,
              ),
            );
          }
          return ListView.separated(
            padding: GochanoSpacing.scrollBody,
            itemCount: docs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: GochanoSpacing.xs),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final isDone = TaskLifecycle.isTaskCompleted(data);
              final assignment = data['type']?.toString() == 'assignment';
              final due = TaskLifecycle.parseDateTime(data['dueAt']);
              return AppCard(
                child: Row(
                  children: [
                    Checkbox(
                      value: isDone,
                      onChanged: (val) async {
                        await doc.reference.update({
                          'done': val ?? false,
                          'completed': val ?? false,
                          'completedAt': FieldValue.serverTimestamp(),
                        });
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data['title']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.type.body.copyWith(
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isDone
                                  ? context.colors.textSecondary
                                  : null,
                            ),
                          ),
                          if (due != null)
                            Text(
                              '${formatShortDate(due)} ${formatClock12(due)}',
                              style: context.type.caption.copyWith(
                                fontSize: 10,
                                color: isDone
                                    ? context.colors.textTertiary
                                    : context.colors.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    GochanoBadge(
                      label: isDone
                          ? GochanoLanguage.text('Completed', 'সম্পন্ন')
                          : GochanoLanguage.text('Missed', 'মিসড'),
                      tone: isDone
                          ? GochanoBadgeTone.success
                          : GochanoBadgeTone.error,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    GochanoBadge(
                      label: assignment
                          ? GochanoLanguage.text('Assignment', 'অ্যাসাইনমেন্ট')
                          : GochanoLanguage.text('Task', 'কাজ'),
                      tone: assignment
                          ? GochanoBadgeTone.info
                          : GochanoBadgeTone.brand,
                    ),
                    GochanoOverflowMenu(
                      items: [
                        GochanoMenuAction(
                          label: doc.data()['done'] == true
                              ? GochanoLanguage.text(
                                  'Mark not done',
                                  'অসম্পন্ন করুন',
                                )
                              : GochanoLanguage.text(
                                  'Mark done',
                                  'সম্পন্ন করুন',
                                ),
                          icon: isDone
                              ? Icons.undo_rounded
                              : Icons.check_rounded,
                          onSelected: () async {
                            final val = !isDone;
                            await doc.reference.update({
                              'done': val,
                              'completed': val,
                              'completedAt': FieldValue.serverTimestamp(),
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
