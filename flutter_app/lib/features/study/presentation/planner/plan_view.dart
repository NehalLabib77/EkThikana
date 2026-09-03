// Combined Plan dashboard (spec §40).
//
// Merges the former Tasks and Planner tabs into a single "Plan" view that
// answers the question "what should I work on today?" in one scroll.
//
// Sections:
//   1. Date / week strip — 7-day selector with a "Today" shortcut.
//   2. Today's Schedule — tasks due on the selected day.
//   3+4. Assignment Deadlines + Tasks — compact side-by-side bento cards.
//   5. Study Goal — weekly focus target, completed focus, progress %.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
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
          _ScheduleSection(selectedDay: _selectedDay),
          const SizedBox(height: GochanoSpacing.md),
          _AssignmentTaskBento(selectedDay: _selectedDay),
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

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selectedDay, required this.onDaySelected});

  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
    final days = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));

    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final currentMonth = '${months[selectedDay.month - 1]} ${selectedDay.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                GochanoLanguage.text(currentMonth, '${selectedDay.month} মাস ${selectedDay.year}'),
                style: context.type.sectionHeading,
              ),
            ),
            TextButton(
              onPressed: () => onDaySelected(today),
              child: Text(GochanoLanguage.text('Today', 'আজ')),
            ),
          ],
        ),
        const SizedBox(height: GochanoSpacing.xs),
        SizedBox(
          height: 56,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final isSelected = DateTime(day.year, day.month, day.day) ==
                  DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
              final isToday = day == today;
              final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

              return GestureDetector(
                onTap: () => onDaySelected(day),
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
// 2. Today's Schedule — tasks due on the selected day
// ---------------------------------------------------------------------------

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({required this.selectedDay});

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

        final tasks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          if (!due.isAfter(dayKey) && due.isBefore(endOfDay)) {
            tasks.add(doc);
          }
        }

        if (tasks.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: GochanoLanguage.text("Today's schedule", 'আজকের সময়সূচি'),
            ),
            CardGroup(
              children: tasks.map((doc) {
                final data = doc.data();
                final due = (data['dueAt'] as Timestamp?)?.toDate();
                return GochanoListRow(
                  illustration: GochanoArt.featureTasks,
                  accent: context.colors.brand,
                  title: data['title']?.toString() ?? '',
                  metadata: [if (due != null) _clock(due)],
                  onTap: () => showAddTaskSheet(context, existing: doc),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3+4. Assignment Deadlines + Tasks — compact side-by-side bento cards
// ---------------------------------------------------------------------------

class _AssignmentTaskBento extends StatelessWidget {
  const _AssignmentTaskBento({required this.selectedDay});

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

        final docs = snapshot.data?.docs ?? [];

        // Split into assignments and tasks.
        //
        // Documents carry an explicit `type` field ('assignment' / 'task').
        // Legacy documents written before the type field existed have
        // type == null and default to Task.  We never infer the type from
        // the due date — a future-dated normal task is still a task.
        final deadlines = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final tasks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in docs) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final isAssignment = data['type']?.toString() == 'assignment';
          if (isAssignment) {
            deadlines.add(doc);
          } else {
            tasks.add(doc);
          }
        }

        deadlines.sort((a, b) {
          final ad = (a.data()['dueAt'] as Timestamp).toDate();
          final bd = (b.data()['dueAt'] as Timestamp).toDate();
          return ad.compareTo(bd);
        });

        tasks.sort((a, b) {
          final ad = (a.data()['dueAt'] as Timestamp?)?.toDate();
          final bd = (b.data()['dueAt'] as Timestamp?)?.toDate();
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });

        if (deadlines.isEmpty && tasks.isEmpty) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 600;
            final cards = [
              Expanded(
                flex: 1,
                child: _AssignmentCard(deadlines: deadlines),
              ),
              if (sideBySide) const SizedBox(width: GochanoSpacing.sm),
              if (!sideBySide) const SizedBox(height: GochanoSpacing.sm),
              Expanded(
                flex: 1,
                child: _TaskCard(tasks: tasks),
              ),
            ];

            return sideBySide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: cards)
                : Column(children: cards);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Assignment Deadlines card
// ---------------------------------------------------------------------------

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.deadlines});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> deadlines;

  @override
  Widget build(BuildContext context) {
    if (deadlines.isEmpty) return const SizedBox.shrink();

    final shown = deadlines.take(3).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  padding: EdgeInsets.zero,
                  title: GochanoLanguage.text(
                    'Assignments',
                    'অ্যাসাইনমেন্ট',
                  ),
                  action: deadlines.length > 3
                      ? TextButton(
                          onPressed: () {},
                          child: Text(
                            GochanoLanguage.text('View all', 'সব দেখুন'),
                          ),
                        )
                      : null,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                onPressed: () =>
                    showAddTaskSheet(context, type: 'assignment'),
                tooltip: GochanoLanguage.text(
                  'Add assignment',
                  'অ্যাসাইনমেন্ট যোগ করুন',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          ...shown.map((doc) {
            final data = doc.data();
            final due = (data['dueAt'] as Timestamp).toDate();
            final remindAt = (data['remindAt'] as Timestamp?)?.toDate();
            final overdue = due.isBefore(DateTime.now());

            return InkWell(
              onTap: () => showAddTaskSheet(context, existing: doc),
              borderRadius: GochanoRadius.smAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data['title']?.toString() ?? '',
                      style: context.type.cardHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: GochanoSpacing.xxs),
                    Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 12,
                          color: overdue
                              ? context.colors.warning
                              : context.colors.textTertiary,
                        ),
                        const SizedBox(width: GochanoSpacing.xxs),
                        Text(
                          '${formatShortDate(due)} · ${formatClock12(due)}',
                          style: context.type.caption.copyWith(
                            color: overdue
                                ? context.colors.warning
                                : context.colors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        _deadlineStateBadge(due),
                      ],
                    ),
                    if (remindAt != null) ...[
                      const SizedBox(height: GochanoSpacing.xxs),
                      _reminderInfo(context, remindAt),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Tasks card — checklist with complete/undo
// ---------------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.tasks});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return EmptyState(
        compact: true,
        illustration: GochanoArt.emptyTasks,
        title: GochanoLanguage.text('No tasks today', 'আজ কোনো কাজ নেই'),
        message: GochanoLanguage.text(
          'Your schedule is clear.',
          'আপনার দিন ফাঁকা।',
        ),
        actionLabel: GochanoLanguage.text('Add task', 'কাজ যোগ করুন'),
        onAction: () => showAddTaskSheet(context, type: 'task'),
      );
    }

    final shown = tasks.take(3).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  padding: EdgeInsets.zero,
                  title: GochanoLanguage.text('Tasks', 'কাজ'),
                  action: tasks.length > 3
                      ? TextButton(
                          onPressed: () {},
                          child: Text(
                            GochanoLanguage.text('View all', 'সব দেখুন'),
                          ),
                        )
                      : null,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                onPressed: () =>
                    showAddTaskSheet(context, type: 'task'),
                tooltip: GochanoLanguage.text(
                  'Add task',
                  'কাজ যোগ করুন',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          ...shown.map((doc) {
            final data = doc.data();
            final done = data['done'] == true;
            final title = data['title']?.toString() ?? '';
            final due = (data['dueAt'] as Timestamp?)?.toDate();
            final remindAt = (data['remindAt'] as Timestamp?)?.toDate();
            final overdue = !done && due != null && due.isBefore(DateTime.now());

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.xs,
                vertical: GochanoSpacing.xxs,
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: done,
                    onChanged: (value) => _setDone(context, doc, value ?? false),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => showAddTaskSheet(context, existing: doc),
                      borderRadius: GochanoRadius.smAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: GochanoSpacing.xs,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: context.type.cardHeading.copyWith(
                                color: done ? context.colors.textSecondary : null,
                                decoration:
                                    done ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  due != null
                                      ? (remindAt != null
                                          ? Icons.notifications_active_outlined
                                          : Icons.event_rounded)
                                      : Icons.schedule_rounded,
                                  size: 12,
                                  color: overdue
                                      ? context.colors.warning
                                      : context.colors.textTertiary,
                                ),
                                const SizedBox(width: GochanoSpacing.xxs),
                                Text(
                                  due != null
                                      ? '${formatShortDate(due)} · ${formatClock12(due)}'
                                      : GochanoLanguage.text(
                                          'No due date',
                                          'কোনো সময়সীমা নেই',
                                        ),
                                  style: context.type.caption.copyWith(
                                    color: overdue
                                        ? context.colors.warning
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            if (remindAt != null) ...[
                              const SizedBox(height: GochanoSpacing.xxs),
                              _reminderInfo(context, remindAt),
                            ],
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
                        onSelected: () =>
                            showAddTaskSheet(context, existing: doc),
                      ),
                      GochanoMenuAction(
                        label: done
                            ? GochanoLanguage.text(
                                'Mark not done',
                                'অসম্পন্ন করুন',
                              )
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
          }),
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

String _clock(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${when.hour < 12 ? 'am' : 'pm'}';
}

Widget _deadlineStateBadge(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;

  if (diff < 0) {
    return GochanoBadge(
      label: GochanoLanguage.text('Overdue', 'সময় পেরিয়েছে'),
      tone: GochanoBadgeTone.error,
      icon: Icons.warning_rounded,
    );
  }
  if (diff == 0) {
    return GochanoBadge(
      label: GochanoLanguage.text('Today', 'আজ'),
      tone: GochanoBadgeTone.warning,
      icon: Icons.today_rounded,
    );
  }
  if (diff == 1) {
    return GochanoBadge(
      label: GochanoLanguage.text('Tomorrow', 'আগামীকাল'),
      tone: GochanoBadgeTone.info,
      icon: Icons.arrow_forward_rounded,
    );
  }
  return GochanoBadge(
    label: GochanoLanguage.text('In $diff days', '$diff দিনে'),
  );
}

Widget _reminderInfo(BuildContext context, DateTime remindAt) {
  return Row(
    children: [
      Icon(
        Icons.notifications_active_outlined,
        size: 12,
        color: context.colors.textTertiary,
      ),
      const SizedBox(width: GochanoSpacing.xxs),
      Text(
        '${GochanoLanguage.text('Reminder', 'রিমাইন্ডার')}: ${formatClock12(remindAt)}',
        style: context.type.caption.copyWith(
          color: context.colors.textTertiary,
        ),
      ),
    ],
  );
}

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
