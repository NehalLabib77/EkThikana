// Combined Plan dashboard (spec §40).
//
// Merges the former Tasks and Planner tabs into a single "Plan" view that
// answers the question "what should I work on today?" in one scroll.
//
// Sections:
//   1. Date / week strip — 7-day selector with a "Today" shortcut.
//   2. Today's Schedule — tasks due on the selected day.
//   3. Assignment Deadlines — upcoming tasks with due dates.
//   4. Tasks — today's / upcoming checklist with complete/undo.
//   5. Reminders — tasks that have a reminder set.
//   6. Study Goal — weekly focus target, completed focus, progress %.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
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

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final stats = await StudyService.stats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
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
          _DeadlinesSection(),
          const SizedBox(height: GochanoSpacing.md),
          _TasksSection(selectedDay: _selectedDay),
          const SizedBox(height: GochanoSpacing.md),
          _RemindersSection(),
          const SizedBox(height: GochanoSpacing.md),
          _StudyGoalSection(
            stats: _stats,
            loading: _loadingStats,
            onRetry: _loadStats,
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
// 3. Assignment Deadlines — upcoming tasks with due dates
// ---------------------------------------------------------------------------

class _DeadlinesSection extends StatelessWidget {
  const _DeadlinesSection();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) return const SizedBox.shrink();

        final now = DateTime.now();
        final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
        final deadlines = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due != null && due.isAfter(endOfToday)) {
            deadlines.add(doc);
          }
        }

        deadlines.sort((a, b) {
          final ad = (a.data()['dueAt'] as Timestamp).toDate();
          final bd = (b.data()['dueAt'] as Timestamp).toDate();
          return ad.compareTo(bd);
        });

        if (deadlines.isEmpty) return const SizedBox.shrink();

        final shown = deadlines.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: GochanoLanguage.text('Assignment deadlines', 'অ্যাসাইনমেন্ট সময়সীমা'),
              action: deadlines.length > 3
                  ? TextButton(
                      onPressed: () {
                        // Navigate to full tasks view is handled by the tab system
                      },
                      child: Text(GochanoLanguage.text('View all', 'সব দেখুন')),
                    )
                  : null,
            ),
            CardGroup(
              children: shown.map((doc) {
                final data = doc.data();
                final due = (data['dueAt'] as Timestamp).toDate();
                final overdue = due.isBefore(DateTime.now());
                return GochanoListRow(
                  illustration: GochanoArt.featureTasks,
                  accent: overdue ? context.colors.warning : context.colors.brand,
                  title: data['title']?.toString() ?? '',
                  metadata: [_shortDue(due)],
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
// 4. Tasks — today's / upcoming checklist
// ---------------------------------------------------------------------------

class _TasksSection extends StatelessWidget {
  const _TasksSection({required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) return const SizedBox.shrink();

        final tasks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          // Include tasks due today or without a date
          if (due == null || !due.isAfter(endOfToday)) {
            tasks.add(doc);
          }
        }

        tasks.sort((a, b) {
          final ad = (a.data()['dueAt'] as Timestamp?)?.toDate();
          final bd = (b.data()['dueAt'] as Timestamp?)?.toDate();
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });

        if (tasks.isEmpty) {
          return EmptyState(
            compact: true,
            illustration: GochanoArt.emptyTasks,
            title: GochanoLanguage.text('No tasks today', 'আজ কোনো কাজ নেই'),
            message: GochanoLanguage.text(
              'Your schedule is clear.',
              'আপনার দিন ফাঁকা।',
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: GochanoLanguage.text('Tasks', 'কাজ'),
            ),
            CardGroup(
              children: tasks.map((doc) {
                final data = doc.data();
                final done = data['done'] == true;
                final title = data['title']?.toString() ?? '';
                final due = (data['dueAt'] as Timestamp?)?.toDate();
                final hasReminder = data['remindAt'] != null;
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
                                    decoration: done ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                if (due != null) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        hasReminder
                                            ? Icons.notifications_active_outlined
                                            : Icons.event_rounded,
                                        size: 13,
                                        color: overdue
                                            ? context.colors.warning
                                            : context.colors.textTertiary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _dueLabel(due),
                                        style: context.type.caption.copyWith(
                                          color: overdue ? context.colors.warning : null,
                                        ),
                                      ),
                                    ],
                                  ),
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
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Reminders — tasks that have a reminder set
// ---------------------------------------------------------------------------

class _RemindersSection extends StatelessWidget {
  const _RemindersSection();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) return const SizedBox.shrink();

        final reminders = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          if (data['remindAt'] != null) {
            reminders.add(doc);
          }
        }

        reminders.sort((a, b) {
          final ar = (a.data()['remindAt'] as Timestamp).toDate();
          final br = (b.data()['remindAt'] as Timestamp).toDate();
          return ar.compareTo(br);
        });

        if (reminders.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: GochanoLanguage.text('Reminders', 'রিমাইন্ডার'),
            ),
            CardGroup(
              children: reminders.take(5).map((doc) {
                final data = doc.data();
                final remindAt = (data['remindAt'] as Timestamp).toDate();
                return GochanoListRow(
                  illustration: GochanoArt.featureReminder,
                  accent: context.colors.medicine,
                  title: data['title']?.toString() ?? '',
                  metadata: [_clock(remindAt)],
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
// 6. Study Goal — weekly focus target, completed focus, progress %
// ---------------------------------------------------------------------------

class _StudyGoalSection extends StatelessWidget {
  const _StudyGoalSection({
    required this.stats,
    required this.loading,
    required this.onRetry,
  });

  final StudyStats? stats;
  final bool loading;
  final VoidCallback onRetry;

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

    final weeklyTargetSeconds = 7 * 60 * 60; // 7 hours
    final completedSeconds = stats?.todaySeconds ?? 0;
    final progress = (completedSeconds / weeklyTargetSeconds).clamp(0.0, 1.0);
    final percent = (progress * 100).round();

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
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            GochanoLanguage.text(
              '${_formatDuration(completedSeconds)} of ${_formatDuration(weeklyTargetSeconds)} this week',
              'এই সপ্তাহে ${_formatDuration(weeklyTargetSeconds)} এর মধ্যে ${_formatDuration(completedSeconds)}',
            ),
            style: context.type.bodySecondary,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              color: colors.study,
            ),
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            GochanoLanguage.text('$percent% complete', '$percent% সম্পন্ন'),
            style: context.type.caption,
          ),
        ],
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

String _dueLabel(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;

  final hour = due.hour % 12 == 0 ? 12 : due.hour % 12;
  final minute = due.minute.toString().padLeft(2, '0');
  final clock = '$hour:$minute ${due.hour < 12 ? 'am' : 'pm'}';

  if (diff == 0) return GochanoLanguage.text('Today $clock', 'আজ $clock');
  if (diff == 1) {
    return GochanoLanguage.text('Tomorrow $clock', 'আগামীকাল $clock');
  }
  if (diff == -1) {
    return GochanoLanguage.text('Yesterday $clock', 'গতকাল $clock');
  }

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${due.day} ${months[due.month - 1]} · $clock';
}

String _shortDue(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;
  if (diff < 0) return GochanoLanguage.text('Overdue', 'সময় পেরিয়েছে');
  if (diff == 0) return GochanoLanguage.text('Today', 'আজ');
  if (diff == 1) return GochanoLanguage.text('Tomorrow', 'আগামীকাল');
  return GochanoLanguage.text('In $diff days', '$diff দিনে');
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
