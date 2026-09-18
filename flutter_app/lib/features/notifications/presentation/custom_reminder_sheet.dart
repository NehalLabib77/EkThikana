import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_dates.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/notification_service.dart';
import '../../../shared/states/gochano_states.dart';

/// Opens the bottom sheet to create a lightweight custom reminder.
Future<bool> showCustomReminderSheet(
  BuildContext context, {
  String? initialTitle,
  DateTime? initialWhen,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _CustomReminderForm(
      initialTitle: initialTitle,
      initialWhen: initialWhen,
    ),
  );
  return result ?? false;
}

class _CustomReminderForm extends StatefulWidget {
  const _CustomReminderForm({this.initialTitle, this.initialWhen});

  final String? initialTitle;
  final DateTime? initialWhen;

  @override
  State<_CustomReminderForm> createState() => _CustomReminderFormState();
}

class _CustomReminderFormState extends State<_CustomReminderForm> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late DateTime _when;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle ?? '');
    _note = TextEditingController();
    final now = DateTime.now();
    _when = widget.initialWhen ?? now.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when.isAfter(now)
          ? _when
          : now.add(const Duration(minutes: 10)),
      firstDate: now,
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (!mounted) return;

    final selectedHour = time?.hour ?? _when.hour;
    final selectedMinute = time?.minute ?? _when.minute;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      selectedHour,
      selectedMinute,
    );

    if (!combined.isAfter(DateTime.now())) {
      setState(() {
        _error = GochanoLanguage.text(
          'Please pick a time in the future.',
          'ভবিষ্যতের একটি সময় নির্বাচন করুন।',
        );
      });
      return;
    }

    setState(() {
      _when = combined;
      _error = null;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() {
        _error = GochanoLanguage.text(
          'Please enter a reminder title.',
          'রিমাইন্ডারের একটি শিরোনাম দিন।',
        );
      });
      return;
    }

    if (!_when.isAfter(DateTime.now())) {
      setState(() {
        _error = GochanoLanguage.text(
          'Reminder time must be in the future.',
          'রিমাইন্ডারের সময় ভবিষ্যতের হতে হবে।',
        );
      });
      return;
    }

    if (kDebugMode) {
      debugPrint('[OfflineSave][Custom] start');
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await NotificationService.scheduleCustomReminder(
        title: title,
        note: _note.text.trim(),
        when: _when,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OfflineSave][Custom] error: $e');
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.lg,
            GochanoSpacing.md,
            GochanoSpacing.lg,
            GochanoSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    GochanoLanguage.text('New Reminder', 'নতুন রিমাইন্ডার'),
                    style: type.sectionHeading.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: GochanoLanguage.text('Close', 'বন্ধ করুন'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.md),
              TextField(
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'What to remind?',
                    'কী মনে করাতে হবে?',
                  ),
                  hintText: GochanoLanguage.text(
                    'e.g. Call Mom, Pay Rent',
                    'যেমন: মাকে কল করা, বাড়িভাড়া দেওয়া',
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'Note (optional)',
                    'নোট (ঐচ্ছিক)',
                  ),
                  hintText: GochanoLanguage.text(
                    'Additional details',
                    'অতিরিক্ত বিবরণ',
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.md),
              InkWell(
                onTap: _pickDateTime,
                borderRadius: GochanoRadius.smAll,
                child: Container(
                  padding: const EdgeInsets.all(GochanoSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: GochanoRadius.smAll,
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        color: colors.brand,
                        size: 20,
                      ),
                      const SizedBox(width: GochanoSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              GochanoLanguage.text(
                                'Remind at',
                                'রিমাইন্ডারের সময়',
                              ),
                              style: type.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              '${formatShortDate(_when)} • ${formatClock12(_when)}',
                              style: type.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  _error!,
                  style: type.caption.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: GochanoSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        GochanoLanguage.text(
                          'Save Reminder',
                          'রিমাইন্ডার সংরক্ষণ করুন',
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
