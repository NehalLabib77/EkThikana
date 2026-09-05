// Tasks — Today / Upcoming / Completed (spec §39).
//
// Three views, no Kanban. Spec §39 is explicit: "Do not introduce unnecessary
// Kanban complexity." Add, edit, complete, undo, delete and reminders are all
// here; the reminder is set on the same sheet as the due date that drives it.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/firestore_service.dart';
import '../../../services/notification_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import 'add_task_sheet.dart';

/// Which slice of the task list is shown.
enum TaskFilter { today, upcoming, completed }

class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  TaskFilter _filter = TaskFilter.today;

  String _label(TaskFilter filter) => switch (filter) {
        TaskFilter.today => GochanoLanguage.text('Today', 'আজ'),
        TaskFilter.upcoming => GochanoLanguage.text('Upcoming', 'আসন্ন'),
        TaskFilter.completed => GochanoLanguage.text('Completed', 'সম্পন্ন'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddTaskSheet(context),
        icon: const Icon(Icons.task_alt_rounded),
        label: Text(GochanoLanguage.text('Add task', 'কাজ যোগ')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GochanoSpacing.md,
              GochanoSpacing.xs,
              GochanoSpacing.md,
              GochanoSpacing.xs,
            ),
            child: FilterChipBar<TaskFilter>(
              options: TaskFilter.values,
              selected: _filter,
              onSelected: (value) => setState(() => _filter = value),
              labelOf: _label,
            ),
          ),
          Expanded(child: _buildList(context)),
        ],
      ),
    );
  }

  /// Build a Firestore query with server-side filtering to avoid pulling
  /// all 300 tasks and filtering client-side on every rebuild.
  Query<Map<String, dynamic>> _taskQuery() {
    final base = FirestoreService.db
        .collection('tasks')
        .where('ownerId', isEqualTo: FirestoreService.uid);

    switch (_filter) {
      case TaskFilter.completed:
        return base
            .where('done', isEqualTo: true)
            .orderBy('updatedAt', descending: true)
            .limit(100);
      case TaskFilter.today:
        final now = DateTime.now();
        final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
        // Include undated tasks (dueAt == null) as "today" items.
        return base
            .where('done', isEqualTo: false)
            .where('dueAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday))
            .orderBy('dueAt')
            .limit(100);
      case TaskFilter.upcoming:
        final now = DateTime.now();
        final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return base
            .where('done', isEqualTo: false)
            .where('dueAt', isGreaterThan: Timestamp.fromDate(endOfToday))
            .orderBy('dueAt')
            .limit(100);
    }
  }

  Widget _buildList(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _taskQuery().snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text('Loading tasks…', 'কাজ লোড হচ্ছে…'),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        final docs = [...?snapshot.data?.docs];

        // For the "today" filter, we also need to include tasks with no dueAt
        // that the server-side query might have missed (null dueAt is not
        // returned by isLessThanOrEqualTo). We do a single pass.
        final todayDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (_filter == TaskFilter.today) {
          for (final doc in docs) {
            final data = doc.data();
            final due = (data['dueAt'] as Timestamp?)?.toDate();
            // Undated tasks (due == null) are included in "today".
            if (due == null || !due.isAfter(
              DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
                23, 59, 59,
              ),
            )) {
              todayDocs.add(doc);
            }
          }
        }

        final effectiveDocs = _filter == TaskFilter.today ? todayDocs : docs;

        effectiveDocs.sort((a, b) {
          final ad = (a.data()['dueAt'] as Timestamp?)?.toDate();
          final bd = (b.data()['dueAt'] as Timestamp?)?.toDate();
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return _filter == TaskFilter.completed
              ? bd.compareTo(ad)
              : ad.compareTo(bd);
        });

        if (effectiveDocs.isEmpty) {
          return EmptyState(
            illustration: GochanoArt.emptyTasks,
            title: switch (_filter) {
              TaskFilter.today =>
                GochanoLanguage.text('No tasks today', 'আজ কোনো কাজ নেই'),
              TaskFilter.upcoming =>
                GochanoLanguage.text('Nothing upcoming', 'আসন্ন কিছু নেই'),
              TaskFilter.completed => GochanoLanguage.text(
                  'Nothing completed yet',
                  'এখনো কিছু সম্পন্ন হয়নি',
                ),
            },
            message: switch (_filter) {
              TaskFilter.today => GochanoLanguage.text(
                  'Your schedule is clear.',
                  'আপনার দিন ফাঁকা।',
                ),
              TaskFilter.upcoming => GochanoLanguage.text(
                  'Tasks with a future due date appear here.',
                  'ভবিষ্যৎ সময়সীমার কাজ এখানে দেখা যাবে।',
                ),
              TaskFilter.completed => GochanoLanguage.text(
                  'Tasks you finish appear here.',
                  'আপনি যেসব কাজ শেষ করবেন সেগুলো এখানে দেখা যাবে।',
                ),
            },
            // Spec §25: the floating Add button is the only entry-point.
            // EmptyState used to render its own "Add task" button too,
            // which placed two identical CTAs on the same empty screen.
          );
        }

        return ListView.builder(
          padding: GochanoSpacing.scrollBody,
          itemCount: effectiveDocs.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: _TaskRow(doc: effectiveDocs[i]),
            ),
          ),
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                        color: done ? colors.textSecondary : null,
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
                            color:
                                overdue ? colors.warning : colors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _dueLabel(due),
                            style: context.type.caption.copyWith(
                              color: overdue ? colors.warning : null,
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
  }
}

/// Completing a task cancels its reminder; un-completing restores it.
///
/// Without this a finished task still buzzes the phone at its due time, and
/// re-opening one silently loses the reminder it used to have.
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
