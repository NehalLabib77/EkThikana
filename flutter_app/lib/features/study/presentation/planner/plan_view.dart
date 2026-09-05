// Combined Plan dashboard (spec §40).
//
// Merges the former Tasks and Planner tabs into a single "Plan" view that
// answers the question "what should I work on today?" in one scroll.
//
// Sections:
//   1. Date / week strip — 7-day selector with a "Today" shortcut.
//   2. Today's Schedule — tasks due on the selected day.
//   3+4. Assignments & Tasks — single combined card with two sections.
//   5. Study Goal — weekly focus target, completed focus, progress %.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_dates.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/study_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../tasks/presentation/add_task_sheet.dart';

class PlanView extends StatefulWidget {
  const PlanView({super.key});

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  DateTime _selectedDay = DateTime.now();
  StudyStats? _stats;
  bool _loadingStats = true;
  int? _dailyGoalMinutes;
  int? _weeklyGoalMinutes;
  int _weeklyCompletedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final results = await Future.wait([
        StudyService.stats(),
        FirestoreService.studyGoals(),
        StudyService.weeklySeconds(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as StudyStats;
        final goals = results[1] as Map<String, int?>;
        _dailyGoalMinutes = goals['dailyGoalMinutes'];
        _weeklyGoalMinutes = goals['weeklyGoalMinutes'];
        _weeklyCompletedSeconds = results[2] as int;
        _loadingStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadStats();
      },
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _DateStrip(
            selectedDay: _selectedDay,
            onDaySelected: (day) => setState(() => _selectedDay = day),
          ),
          const SizedBox(height: GochanoSpacing.md),
          _CombinedPlannerList(selectedDay: _selectedDay),
          const SizedBox(height: GochanoSpacing.md),
          _StudyGoalSection(
            stats: _stats,
            loading: _loadingStats,
            dailyGoalMinutes: _dailyGoalMinutes,
            weeklyGoalMinutes: _weeklyGoalMinutes,
            weeklyCompletedSeconds: _weeklyCompletedSeconds,
            onRetry: _loadStats,
            onGoalSaved: () => _loadStats(),
          ),
          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Date / Week strip
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
  static const _cellWidth = 44.0 + 8.0; // cell width + right margin
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
    final totalDays = _totalDays;
    final todayIndex = totalDays - 15; // today is 15 days from start
    final targetOffset = (todayIndex - _visibleBeforeToday) * _cellWidth;
    _scrollController.jumpTo(targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    ));
  }

  static const _totalDays = 31; // ~1 month of scrollable dates

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(const Duration(days: 15));
    final days = List.generate(_totalDays, (i) => startDate.add(Duration(days: i)));

    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final currentMonth = '${months[widget.selectedDay.month - 1]} ${widget.selectedDay.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                GochanoLanguage.text(currentMonth, '${widget.selectedDay.month} মাস ${widget.selectedDay.year}'),
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
          height: 56,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final isSelected = DateTime(day.year, day.month, day.day) ==
                  DateTime(widget.selectedDay.year, widget.selectedDay.month, widget.selectedDay.day);
              final isToday = day == today;
              final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

              return GestureDetector(
                onTap: () => widget.onDaySelected(day),
                child: Container(
                  width: 44,
                  margin: const EdgeInsets.only(right: GochanoSpacing.xs),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.brand
                        : isToday
                            ? colors.brandSoft
                            : colors.surface,
                    borderRadius: GochanoRadius.mdAll,
                    border: isToday && !isSelected
                        ? Border.all(color: colors.brand, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dayNames[day.weekday % 7],
                        style: context.type.caption.copyWith(
                          color: isSelected
                              ? Colors.white
                              : colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: context.type.cardHeading.copyWith(
                          color: isSelected ? Colors.white : colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Combined Tasks & Assignments — single chronological list with category badges
// ---------------------------------------------------------------------------

class _CombinedPlannerList extends StatelessWidget {
  const _CombinedPlannerList({required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) return const SizedBox.shrink();

        final dayKey = DateTime(
          selectedDay.year,
          selectedDay.month,
          selectedDay.day,
        );
        final endOfDay = dayKey.add(const Duration(days: 1));

        final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          if (!due.isBefore(dayKey) && due.isBefore(endOfDay)) {
            docs.add(doc);
          }
        }

        // Sort by dueAt ascending (items with no due go last).
        docs.sort((a, b) {
          final ad = (a.data()['dueAt'] as Timestamp?)?.toDate();
          final bd = (b.data()['dueAt'] as Timestamp?)?.toDate();
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });

        if (docs.isEmpty) {
          return AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GochanoIllustration(
                  GochanoArt.emptyTasks,
                  size: GochanoSizes.illustrationEmpty,
                  accent: context.colors.textTertiary,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text(
                    'Nothing due on this day.',
                    'এই দিনে কিছু নেই।',
                  ),
                  style: context.type.sectionHeading,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        showAddTaskSheet(context, initialDate: selectedDay),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                        GochanoLanguage.text('Add task', 'কাজ যোগ করুন')),
                  ),
                ),
              ],
            ),
          );
        }

        return AppCard(
          padding: const EdgeInsets.all(GochanoSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.event_rounded, size: 14, color: context.colors.brand),
                  const SizedBox(width: GochanoSpacing.xxs),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        'Due this day',
                        'এই দিনের কাজ',
                      ),
                      style: context.type.label.copyWith(
                        fontSize: 13,
                        color: context.colors.brand,
                      ),
                    ),
                  ),
                  GochanoBadge(
                    label: '${docs.length}',
                    tone: GochanoBadgeTone.brand,
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              for (final doc in docs) ...[
                _PlannerItemRow(doc: doc),
                if (doc != docs.last)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Divider(height: 1, color: context.colors.border),
                  ),
              ],
              const SizedBox(height: GochanoSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showAddTaskSheet(
                        context,
                        type: 'task',
                        initialDate: selectedDay,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(GochanoLanguage.text('Task', 'কাজ')),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showAddTaskSheet(
                        context,
                        type: 'assignment',
                        initialDate: selectedDay,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(
                          GochanoLanguage.text('Assignment', 'অ্যাসাইনমেন্ট')),
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
// 3+4. Single planner row — shows category badge, title, due, and actions
// ---------------------------------------------------------------------------

class _PlannerItemRow extends StatelessWidget {
  const _PlannerItemRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final done = data['done'] == true;
    final title = data['title']?.toString() ?? '';
    final due = (data['dueAt'] as Timestamp?)?.toDate();
    final overdue = !done && due != null && due.isBefore(DateTime.now());
    final isAssignment = data['type']?.toString() == 'assignment';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (!isAssignment)
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: done,
                onChanged: (value) => _setDone(context, doc, value ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            Icon(
              Icons.assignment_outlined,
              size: 16,
              color: context.colors.brand,
            ),
          const SizedBox(width: GochanoSpacing.xxs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isAssignment
                  ? context.colors.brand.withValues(alpha: 0.10)
                  : context.colors.study.withValues(alpha: 0.10),
              borderRadius: GochanoRadius.smAll,
            ),
            child: Text(
              isAssignment
                  ? GochanoLanguage.text('Asm', 'অ্যাস')
                  : GochanoLanguage.text('Task', 'কাজ'),
              style: context.type.caption.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isAssignment ? context.colors.brand : context.colors.study,
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          Expanded(
            child: InkWell(
              onTap: () => showAddTaskSheet(context, existing: doc),
              borderRadius: GochanoRadius.smAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: context.type.body.copyWith(
                        fontSize: 13,
                        color: done ? context.colors.textSecondary : null,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (due != null)
                      Text(
                        '${formatShortDate(due)} ${formatClock12(due)}',
                        style: context.type.caption.copyWith(
                          fontSize: 10,
                          color: overdue ? context.colors.warning : context.colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          GochanoOverflowMenu(
            items: [
              GochanoMenuAction(
                label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
                icon: Icons.edit_outlined,
                onSelected: () => showAddTaskSheet(context, existing: doc),
              ),
              GochanoMenuAction(
                label: done
                    ? GochanoLanguage.text('Mark not done', 'অসম্পন্ন করুন')
                    : GochanoLanguage.text('Mark done', 'সম্পন্ন করুন'),
                icon: done ? Icons.undo_rounded : Icons.check_rounded,
                onSelected: () => _setDone(context, doc, !done),
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Delete', 'মুছুন'),
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: () => _delete(context, doc, title),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Study Goal — daily + weekly focus targets, completed focus, progress %
// ---------------------------------------------------------------------------

class _StudyGoalSection extends StatelessWidget {
  const _StudyGoalSection({
    required this.stats,
    required this.loading,
    required this.dailyGoalMinutes,
    required this.weeklyGoalMinutes,
    required this.weeklyCompletedSeconds,
    required this.onRetry,
    required this.onGoalSaved,
  });

  final StudyStats? stats;
  final bool loading;
  final int? dailyGoalMinutes;
  final int? weeklyGoalMinutes;
  final int weeklyCompletedSeconds;
  final VoidCallback onRetry;
  final VoidCallback onGoalSaved;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (loading) {
      return StaticLoadingState(
        compact: true,
        message: GochanoLanguage.text(
          'Loading study goal…',
          'পড়াশোনার লক্ষ্য লোড হচ্ছে…',
        ),
      );
    }

    final goalsSet = dailyGoalMinutes != null || weeklyGoalMinutes != null;

    if (!goalsSet) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'Study Goal',
                      'পড়াশোনার লক্ষ্য',
                    ),
                    style: context.type.label,
                  ),
                ),
                if (stats?.streakDays != null && stats!.streakDays > 0)
                  GochanoBadge(
                    label: GochanoLanguage.text(
                      '${stats!.streakDays} day streak',
                      '${stats!.streakDays} দিনের ধারা',
                    ),
                    tone: GochanoBadgeTone.success,
                    icon: Icons.local_fire_department_rounded,
                  ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text(
                'Set a daily or weekly study target to track your progress.',
                'আপনার অগ্রগতি ট্র্যাক করতে একটি দৈনিক বা সাপ্তাহিক পড়াশোনার লক্ষ্য নির্ধারণ করুন।',
              ),
              style: context.type.bodySecondary,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _showEditGoalSheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  GochanoLanguage.text('Set study goal', 'পড়াশোনার লক্ষ্য নির্ধারণ করুন'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final dailyTargetSeconds = (dailyGoalMinutes ?? 0) * 60;
    final weeklyTargetSeconds = (weeklyGoalMinutes ?? 0) * 60;
    final dailyCompleted = stats?.todaySeconds ?? 0;

    // Guard against zero goals.
    final dailyProgress = dailyTargetSeconds > 0
        ? (dailyCompleted / dailyTargetSeconds).clamp(0.0, 1.0)
        : 0.0;
    final weeklyProgress = weeklyTargetSeconds > 0
        ? (weeklyCompletedSeconds / weeklyTargetSeconds).clamp(0.0, 1.0)
        : 0.0;
    final dailyPercent = (dailyProgress * 100).round();
    final weeklyPercent = (weeklyProgress * 100).round();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  GochanoLanguage.text('Study Goal', 'পড়াশোনার লক্ষ্য'),
                  style: context.type.label,
                ),
              ),
              if (stats?.streakDays != null && stats!.streakDays > 0)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '${stats!.streakDays} day streak',
                    '${stats!.streakDays} দিনের ধারা',
                  ),
                  tone: GochanoBadgeTone.success,
                  icon: Icons.local_fire_department_rounded,
                ),
              const SizedBox(width: GochanoSpacing.xs),
              IconActionButton(
                icon: Icons.edit_outlined,
                label: GochanoLanguage.text('Edit goal', 'লক্ষ্য সম্পাদনা'),
                onPressed: () => _showEditGoalSheet(context),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          // Daily progress
          Text(
            GochanoLanguage.text(
              'Today: ${_formatDuration(dailyCompleted)} / ${_formatDuration(dailyTargetSeconds)}',
              'আজ: ${_formatDuration(dailyTargetSeconds)} এর মধ্যে ${_formatDuration(dailyCompleted)}',
            ),
            style: context.type.bodySecondary,
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: dailyProgress,
              minHeight: 5,
              backgroundColor: colors.surfaceVariant,
              color: colors.study,
            ),
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            GochanoLanguage.text(
              '$dailyPercent% daily',
              '$dailyPercent% দৈনিক',
            ),
            style: context.type.caption,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          // Weekly progress
          Text(
            GochanoLanguage.text(
              'This week: ${_formatDuration(weeklyCompletedSeconds)} / ${_formatDuration(weeklyTargetSeconds)}',
              'এই সপ্তাহে: ${_formatDuration(weeklyTargetSeconds)} এর মধ্যে ${_formatDuration(weeklyCompletedSeconds)}',
            ),
            style: context.type.bodySecondary,
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: weeklyProgress,
              minHeight: 5,
              backgroundColor: colors.surfaceVariant,
              color: colors.study,
            ),
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            GochanoLanguage.text(
              '$weeklyPercent% weekly',
              '$weeklyPercent% সাপ্তাহিক',
            ),
            style: context.type.caption,
          ),
        ],
      ),
    );
  }

  void _showEditGoalSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditGoalSheet(
        dailyGoalMinutes: dailyGoalMinutes ?? 0,
        weeklyGoalMinutes: weeklyGoalMinutes ?? 0,
        onSaved: onGoalSaved,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _formatDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours == 0) return GochanoLanguage.text('$minutes min', '$minutes মিনিট');
  if (minutes == 0) return GochanoLanguage.text('$hours h', '$hours ঘন্টা');
  return GochanoLanguage.text(
    '$hours h $minutes min',
    '$hours ঘন্টা $minutes মিনিট',
  );
}

// ---------------------------------------------------------------------------
// 5b. Edit Goal — compact bottom sheet for daily/weekly hours + minutes
// ---------------------------------------------------------------------------

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
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.lg,
            GochanoSpacing.xs,
            GochanoSpacing.lg,
            GochanoSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                GochanoLanguage.text('Edit study goal', 'পড়াশোনার লক্ষ্য সম্পাদনা'),
                style: context.type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.md),
              // Daily goal
              Text(
                GochanoLanguage.text('Daily goal', 'দৈনিক লক্ষ্য'),
                style: context.type.label,
              ),
              const SizedBox(height: GochanoSpacing.xs),
              _HourMinuteRow(
                hours: _dailyH,
                minutes: _dailyM,
                onChanged: (h, m) => setState(() {
                  _dailyH = h;
                  _dailyM = m;
                  _error = null;
                }),
              ),
              const SizedBox(height: GochanoSpacing.md),
              // Weekly goal
              Text(
                GochanoLanguage.text('Weekly goal', 'সাপ্তাহিক লক্ষ্য'),
                style: context.type.label,
              ),
              const SizedBox(height: GochanoSpacing.xs),
              _HourMinuteRow(
                hours: _weeklyH,
                minutes: _weeklyM,
                onChanged: (h, m) => setState(() {
                  _weeklyH = h;
                  _weeklyM = m;
                  _error = null;
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  _error!,
                  style: context.type.bodySecondary.copyWith(
                    color: colors.error,
                  ),
                ),
              ],
              const SizedBox(height: GochanoSpacing.md),
              PrimaryButton(
                label: GochanoLanguage.text('Save goal', 'লক্ষ্য সংরক্ষণ'),
                busy: _saving,
                busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5c. Hour / Minute row — compact stepper for goal editing
// ---------------------------------------------------------------------------

class _HourMinuteRow extends StatelessWidget {
  const _HourMinuteRow({
    required this.hours,
    required this.minutes,
    required this.onChanged,
  });

  final int hours;
  final int minutes;
  final void Function(int hours, int minutes) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CompactStepper(
          label: GochanoLanguage.text('h', 'ঘ'),
          value: hours,
          min: 0,
          max: 24,
          onChanged: (v) => onChanged(v, minutes),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        _CompactStepper(
          label: GochanoLanguage.text('m', 'মি'),
          value: minutes,
          min: 0,
          max: 59,
          step: 5,
          onChanged: (v) => onChanged(hours, v),
        ),
        const Spacer(),
        Text(
          _formatDuration(hours * 60 + minutes),
          style: context.type.bodySecondary,
        ),
      ],
    );
  }
}

class _CompactStepper extends StatelessWidget {
  const _CompactStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final int step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: value > min ? () => onChanged((value - step).clamp(min, max)) : null,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: value > min ? colors.surfaceVariant : colors.surface,
              borderRadius: GochanoRadius.smAll,
            ),
            child: Icon(
              Icons.remove_rounded,
              size: 18,
              color: value > min ? colors.textPrimary : colors.textTertiary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.xs),
          child: SizedBox(
            width: 40,
            child: Text(
              '$value$label',
              style: context.type.cardHeading,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        GestureDetector(
          onTap: value < max ? () => onChanged((value + step).clamp(min, max)) : null,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: value < max ? colors.surfaceVariant : colors.surface,
              borderRadius: GochanoRadius.smAll,
            ),
            child: Icon(
              Icons.add_rounded,
              size: 18,
              color: value < max ? colors.textPrimary : colors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _setDone(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  bool done,
) async {
  final data = doc.data();
  final title = data['title']?.toString() ?? '';
  final remindAt = (data['remindAt'] as Timestamp?)?.toDate();

  try {
    await doc.reference.update({
      'done': done,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await NotificationService.rescheduleTask(
      taskId: doc.id,
      title: title,
      when: done ? null : remindAt,
    );
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _delete(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  String title,
) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Delete this task?', 'কাজটি মুছবেন?'),
    message: title,
    confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
  );
  if (!confirmed || !context.mounted) return;
  try {
    await NotificationService.cancelTask(doc.id);
    await doc.reference.delete();
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}
