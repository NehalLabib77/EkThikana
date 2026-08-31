// Add / edit a task (spec §39).
//
// One sheet, reachable from Home's quick actions and from the Tasks screen,
// so there is a single definition of what a task is and a single validation
// path. Reminder scheduling happens here too, next to the due date that
// drives it, rather than in a separate follow-up screen.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/firestore_service.dart';
import '../../../services/notification_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';

/// Opens the add/edit task sheet. Returns true when a task was saved.
Future<bool> showAddTaskSheet(
  BuildContext context, {
  DocumentSnapshot<Map<String, dynamic>>? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      // Lift the sheet above the keyboard so the Save button and the field
      // being typed into are both reachable (spec §23).
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _TaskForm(existing: existing),
    ),
  );
  return saved ?? false;
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.existing});

  final DocumentSnapshot<Map<String, dynamic>>? existing;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final TextEditingController _title;
  DateTime? _dueAt;
  bool _remind = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existing?.data() ?? const <String, dynamic>{};
    _title = TextEditingController(text: data['title']?.toString() ?? '');
    _dueAt = (data['dueAt'] as Timestamp?)?.toDate();
    _remind = data['remindAt'] != null || !_isEdit;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(hours: 1)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _dueAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (!mounted) return;

    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() {
        _error = GochanoLanguage.text(
          'Give the task a name.',
          'কাজটির একটি নাম দিন।',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'title': title,
        'dueAt': _dueAt == null ? null : Timestamp.fromDate(_dueAt!),
        'remindAt':
            _remind && _dueAt != null ? Timestamp.fromDate(_dueAt!) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final String taskId;
      if (_isEdit) {
        taskId = widget.existing!.id;
        await widget.existing!.reference.update(payload);
      } else {
        final ref = await FirestoreService.addOwnerRecord('tasks', {
          ...payload,
          'done': false,
        });
        taskId = ref.id;
      }

      // `rescheduleTask` is the single safe primitive for an edit flow: it
      // recycles the same deterministic notification id, so editing a task
      // cannot leave a stale reminder queued alongside the new one. Passing
      // a null/cleared `when` cancels without rescheduling.
      await NotificationService.rescheduleTask(
        taskId: taskId,
        title: title,
        when: _remind ? _dueAt : null,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
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
              _isEdit
                  ? GochanoLanguage.text('Edit task', 'কাজ সম্পাদনা')
                  : GochanoLanguage.text('New task', 'নতুন কাজ'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.md),
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('What needs doing?', 'কী করতে হবে?'),
                hintText: GochanoLanguage.text(
                  'Finish DBMS assignment',
                  'ডিবিএমএস অ্যাসাইনমেন্ট শেষ করা',
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            InkWell(
              onTap: _pickDueDate,
              borderRadius: GochanoRadius.mdAll,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text('Due', 'সময়সীমা'),
                  prefixIcon: const Icon(Icons.event_rounded),
                  suffixIcon: _dueAt == null
                      ? null
                      : IconActionButton(
                          icon: Icons.close_rounded,
                          label: GochanoLanguage.text('Clear due date', 'সময়সীমা মুছুন'),
                          onPressed: () => setState(() => _dueAt = null),
                        ),
                ),
                child: Text(
                  _dueAt == null
                      ? GochanoLanguage.text('No due date', 'কোনো সময়সীমা নেই')
                      : _formatDueDate(_dueAt!),
                  style: context.type.body.copyWith(
                    color: _dueAt == null ? colors.textTertiary : null,
                  ),
                ),
              ),
            ),
            if (_dueAt != null) ...[
              const SizedBox(height: GochanoSpacing.xxs),
              SwitchListTile.adaptive(
                value: _remind,
                onChanged: (value) => setState(() => _remind = value),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  GochanoLanguage.text('Remind me', 'মনে করিয়ে দিন'),
                  style: context.type.body,
                ),
                subtitle: Text(
                  GochanoLanguage.text(
                    'A notification at the due time',
                    'সময়সীমায় একটি নোটিফিকেশন',
                  ),
                  style: context.type.caption,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                _error!,
                style: context.type.bodySecondary.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              label: GochanoLanguage.text('Save task', 'কাজ সংরক্ষণ'),
              busy: _saving,
              busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDueDate(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final suffix = when.hour < 12 ? 'am' : 'pm';
  return '${when.day} ${months[when.month - 1]} ${when.year} · $hour:$minute $suffix';
}
