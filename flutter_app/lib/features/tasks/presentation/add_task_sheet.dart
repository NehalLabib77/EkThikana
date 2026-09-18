// Add / edit a task (spec §39).
//
// One sheet, reachable from Home's quick actions and from the Tasks screen,
// so there is a single definition of what a task is and a single validation
// path. Reminder scheduling happens here too, next to the due date that
// drives it, rather than in a separate follow-up screen.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/feedback_messages.dart';
import '../../../core/localization/gochano_dates.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/firestore_service.dart';
import '../../../services/notification_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';

/// Immutable result contract for the task save flow.
///
/// Every exit path of [showAddTaskSheet] returns this type. Cancel / back
/// returns `null`; save returns a populated instance.
@immutable
class TaskSaveResult {
  const TaskSaveResult({
    required this.saved,
    this.taskId,
    this.title,
    this.dueAt,
    this.remindAt,
    this.reminderScheduled = false,
    this.reminderFailed = false,
    this.isAssignment = false,
  });

  /// Named constructor for the cancel/dismiss case.
  const TaskSaveResult.cancelled()
    : saved = false,
      taskId = null,
      title = null,
      dueAt = null,
      remindAt = null,
      reminderScheduled = false,
      reminderFailed = false,
      isAssignment = false;

  final bool saved;
  final String? taskId;
  final String? title;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final bool reminderScheduled;
  final bool reminderFailed;
  final bool isAssignment;
}

/// Opens the add/edit task sheet. Returns [TaskSaveResult] when a task was
/// saved, or null if dismissed/cancelled without saving.
///
/// [type] defaults to `'task'`. Pass `'assignment'` to preselect the form
/// as an assignment — the document is stamped with this value so the Plan
/// cards can filter reliably.
///
/// [initialDate] pre-fills the due date for new tasks (ignored for edits).
/// When provided, the due time defaults to 09:00 on that date so the task
/// appears immediately in the selected Plan day's list.
Future<TaskSaveResult?> showAddTaskSheet(
  BuildContext context, {
  DocumentSnapshot<Map<String, dynamic>>? existing,
  String type = 'task',
  DateTime? initialDate,
}) async {
  final existingType = existing?.data()?['type']?.toString();
  final resolvedType = existingType == 'assignment' ? 'assignment' : type;
  final result = await showModalBottomSheet<TaskSaveResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _TaskForm(
      existing: existing,
      type: resolvedType,
      initialDate: initialDate,
    ),
  );
  if (result != null && result.saved && context.mounted) {
    showGochanoMessage(
      context,
      FeedbackMessages.taskSaved(
        isAssignment: result.isAssignment,
        remindAt: result.remindAt,
        reminderFailed: result.reminderFailed,
      ),
    );
  }
  return result;
}

/// Preset durations before dueAt. Index 0 = no reminder.
const _kPresetDurations = <Duration>[
  Duration.zero, // no reminder
  Duration(minutes: 10),
  Duration(minutes: 30),
  Duration(hours: 1),
];

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.existing, this.type = 'task', this.initialDate});

  final DocumentSnapshot<Map<String, dynamic>>? existing;
  final String type;

  /// Pre-fills the due date for a new task (9 am on this date). Ignored when
  /// [existing] is provided (edit mode).
  final DateTime? initialDate;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> with WidgetsBindingObserver {
  late final TextEditingController _title;
  DateTime? _dueAt;
  DateTime? _remindAt;
  int _reminderPreset = 0;
  bool _saving = false;
  String? _error;
  bool _exactAlarmAllowed = true;
  late bool _showMoreOptions;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExactAlarm();
    final data = widget.existing?.data() ?? const <String, dynamic>{};
    _title = TextEditingController(text: data['title']?.toString() ?? '');
    _dueAt = (data['dueAt'] as Timestamp?)?.toDate();
    if (_dueAt == null && widget.initialDate != null && !_isEdit) {
      final d = widget.initialDate!;
      _dueAt = DateTime(d.year, d.month, d.day, 9, 0);
    }
    _remindAt = (data['remindAt'] as Timestamp?)?.toDate();
    _reminderPreset = _detectPreset();
    _showMoreOptions = _isEdit && _reminderPreset > 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _title.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkExactAlarm();
    }
  }

  int _detectPreset() {
    if (_dueAt == null || _remindAt == null) return 0;
    final diff = _dueAt!.difference(_remindAt!).inMinutes;
    if (diff <= 0) return 0;
    for (var i = _kPresetDurations.length - 1; i >= 1; i--) {
      if (diff == _kPresetDurations[i].inMinutes) return i;
    }
    return 0;
  }

  void _applyReminderPreset() {
    if (_reminderPreset == 0 || _dueAt == null) {
      _remindAt = null;
    } else {
      _remindAt = _dueAt!.subtract(_kPresetDurations[_reminderPreset]);
    }
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
      _applyReminderPreset();
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() {
        _error = widget.type == 'assignment'
            ? GochanoLanguage.text(
                'Give the assignment a name.',
                'অ্যাসাইনমেন্টের একটি নাম দিন।',
              )
            : GochanoLanguage.text(
                'Give the task a name.',
                'কাজটির একটি নাম দিন।',
              );
      });
      return;
    }

    if (kDebugMode) {
      debugPrint('[OfflineSave][Task] start');
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    if (_remindAt != null && _dueAt != null && !_remindAt!.isBefore(_dueAt!)) {
      setState(() {
        _saving = false;
        _error = GochanoLanguage.text(
          'Reminder must be before the due time.',
          'রিমাইন্ডার সময়সীমার আগে হতে হবে।',
        );
      });
      return;
    }

    try {
      final payload = <String, dynamic>{
        'title': title,
        'type': widget.type,
        'dueAt': _dueAt == null ? null : Timestamp.fromDate(_dueAt!),
        'remindAt': _remindAt != null ? Timestamp.fromDate(_remindAt!) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 1. Establish stable domain ID locally & synchronously without waiting for network
      final DocumentReference<Map<String, dynamic>> docRef = _isEdit
          ? widget.existing!.reference
          : FirestoreService.db.collection('tasks').doc();
      final String taskId = docRef.id;

      // 2. Enqueue/dispatch Firestore write locally to offline cache.
      final currentUid = FirestoreService.uid;
      final writePayload = <String, dynamic>{
        ...payload,
        if (!_isEdit) 'ownerId': currentUid,
        if (!_isEdit) 'done': false,
        if (!_isEdit) 'createdAt': FieldValue.serverTimestamp(),
      };

      unawaited(
        docRef.set(writePayload, SetOptions(merge: true)).catchError((e) {
          if (kDebugMode) {
            debugPrint('[OfflineSave][Task] remote sync deferred/failed: $e');
          }
        }),
      );

      if (kDebugMode) {
        debugPrint('[OfflineSave][Task] local/domain write queued id=$taskId');
      }

      final shouldScheduleReminder = _dueAt != null;

      var reminderFailed = false;
      if (shouldScheduleReminder) {
        try {
          await NotificationService.rescheduleTask(
            taskId: taskId,
            title: title,
            when: _dueAt,
            type: widget.type,
          );
          if (kDebugMode) {
            debugPrint('[OfflineSave][Task] alarm scheduled');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[OfflineSave][Task] alarm schedule failed: $e');
          }
          reminderFailed = true;
        }
      } else {
        await NotificationService.cancelTask(taskId);
      }

      if (kDebugMode) {
        debugPrint('[OfflineSave][Task] ui complete');
      }

      if (!mounted) return;
      final effectiveRemindAt = _remindAt ?? _dueAt;
      Navigator.of(context).pop(
        TaskSaveResult(
          saved: true,
          taskId: taskId,
          title: title,
          dueAt: _dueAt,
          remindAt: shouldScheduleReminder ? effectiveRemindAt : null,
          reminderScheduled: shouldScheduleReminder && !reminderFailed,
          reminderFailed: reminderFailed && shouldScheduleReminder,
          isAssignment: widget.type == 'assignment',
        ),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[OfflineSave][Task] save error: $error');
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
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
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
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
                    ? widget.type == 'assignment'
                          ? GochanoLanguage.text(
                              'Edit assignment',
                              'অ্যাসাইনমেন্ট সম্পাদনা',
                            )
                          : GochanoLanguage.text('Edit task', 'কাজ সম্পাদনা')
                    : widget.type == 'assignment'
                    ? GochanoLanguage.text(
                        'New assignment',
                        'নতুন অ্যাসাইনমেন্ট',
                      )
                    : GochanoLanguage.text('New task', 'নতুন কাজ'),
                style: context.type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.md),
              TextField(
                key: const ValueKey('task_title_input'),
                controller: _title,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'What needs doing?',
                    'কী করতে হবে?',
                  ),
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
                            label: GochanoLanguage.text(
                              'Clear due date',
                              'সময়সীমা মুছুন',
                            ),
                            onPressed: () => setState(() {
                              _dueAt = null;
                              _remindAt = null;
                              _reminderPreset = 0;
                            }),
                          ),
                  ),
                  child: Text(
                    _dueAt == null
                        ? GochanoLanguage.text(
                            'No due date',
                            'কোনো সময়সীমা নেই',
                          )
                        : _formatDueDate(_dueAt!),
                    style: context.type.body.copyWith(
                      color: _dueAt == null ? colors.textTertiary : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),

              // More options toggle (progressive disclosure)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('task_more_options_toggle'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, GochanoSizes.minTouchTarget),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () =>
                      setState(() => _showMoreOptions = !_showMoreOptions),
                  icon: Icon(
                    _showMoreOptions
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                  ),
                  label: Text(
                    GochanoLanguage.text('More options', 'আরও অপশন'),
                    style: context.type.bodySecondary.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.brand,
                    ),
                  ),
                ),
              ),

              if (_showMoreOptions) ...[
                const SizedBox(height: GochanoSpacing.xs),
                if (!_exactAlarmAllowed) ...[
                  Container(
                    padding: const EdgeInsets.all(GochanoSpacing.sm),
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.12),
                      borderRadius: GochanoRadius.mdAll,
                      border: Border.all(
                        color: colors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.alarm_off_rounded,
                          color: colors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: GochanoSpacing.sm),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              'Enable "Alarms & reminders" in settings so reminders ring when the app is closed.',
                              'অ্যাপ বন্ধ থাকলেও রিমাইন্ডার পেতে সেটিংসে "অ্যালার্ম ও রিমাইন্ডার" চালু করুন।',
                            ),
                            style: context.type.caption.copyWith(
                              color: colors.textPrimary,
                            ),
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
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                ],
                Text(
                  GochanoLanguage.text('Reminder', 'রিমাইন্ডার'),
                  style: context.type.label,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                if (_dueAt != null)
                  Wrap(
                    spacing: GochanoSpacing.xs,
                    runSpacing: GochanoSpacing.xs,
                    children: [
                      _buildPresetChip(
                        context,
                        index: 0,
                        label: GochanoLanguage.text('None', 'নেই'),
                      ),
                      _buildPresetChip(
                        context,
                        index: 1,
                        label: GochanoLanguage.text(
                          '10 min before',
                          '১০ মিনিট আগে',
                        ),
                      ),
                      _buildPresetChip(
                        context,
                        index: 2,
                        label: GochanoLanguage.text(
                          '30 min before',
                          '৩০ মিনিট আগে',
                        ),
                      ),
                      _buildPresetChip(
                        context,
                        index: 3,
                        label: GochanoLanguage.text(
                          '1 hour before',
                          '১ ঘণ্টা আগে',
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    GochanoLanguage.text(
                      'Select a due date above to set reminders.',
                      'রিমাইন্ডার সেট করতে উপরে সময়সীমা নির্ধারণ করুন।',
                    ),
                    style: context.type.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
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
                key: const ValueKey('task_save_button'),
                label: widget.type == 'assignment'
                    ? GochanoLanguage.text(
                        'Save assignment',
                        'অ্যাসাইনমেন্ট সংরক্ষণ করুন',
                      )
                    : GochanoLanguage.text('Save task', 'কাজ সংরক্ষণ'),
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

  Widget _buildPresetChip(
    BuildContext context, {
    required int index,
    required String label,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: _reminderPreset == index,
      onSelected: (selected) {
        if (!selected) return;
        setState(() {
          _reminderPreset = index;
          _applyReminderPreset();
        });
      },
    );
  }
}

String _formatDueDate(DateTime when) {
  if (GochanoLanguage.isBangla) {
    final day = GochanoLanguage.toBanglaDigits(when.day);
    final month = shortMonthLabel(when.month);
    final year = GochanoLanguage.toBanglaDigits(when.year);
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final bnHour = GochanoLanguage.toBanglaDigits(hour);
    final minute = when.minute.toString().padLeft(2, '0');
    final bnMinute = GochanoLanguage.toBanglaDigits(minute);
    final suffix = when.hour < 12 ? 'পূর্বাহ্ন' : 'অপরাহ্ন';
    return '$day $month $year · $bnHour:$bnMinute $suffix';
  }
  const months = [
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
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final suffix = when.hour < 12 ? 'am' : 'pm';
  return '${when.day} ${months[when.month - 1]} ${when.year} · $hour:$minute $suffix';
}
