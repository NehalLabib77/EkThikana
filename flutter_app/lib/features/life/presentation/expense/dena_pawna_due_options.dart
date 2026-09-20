import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_dates.dart';
import '../../../../core/localization/gochano_language.dart';

/// Progressive 'More options' section for Dena/Pawna forms.
///
/// Encapsulates optional due date and reminder time pickers, keeping the primary
/// transaction form minimal while supporting offline expense due alarms.
class DenaPawnaDueOptions extends StatefulWidget {
  const DenaPawnaDueOptions({
    super.key,
    this.initialDateTime,
    required this.onDateTimeChanged,
  });

  final DateTime? initialDateTime;
  final ValueChanged<DateTime?> onDateTimeChanged;

  @override
  State<DenaPawnaDueOptions> createState() => _DenaPawnaDueOptionsState();
}

class _DenaPawnaDueOptionsState extends State<DenaPawnaDueOptions> {
  late bool _isExpanded;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    if (widget.initialDateTime != null) {
      _selectedDate = DateTime(
        widget.initialDateTime!.year,
        widget.initialDateTime!.month,
        widget.initialDateTime!.day,
      );
      _selectedTime = TimeOfDay.fromDateTime(widget.initialDateTime!);
      _isExpanded = true;
    } else {
      _isExpanded = false;
    }
  }

  void _notifyChange() {
    if (_selectedDate == null) {
      widget.onDateTimeChanged(null);
      return;
    }
    final time = _selectedTime ?? const TimeOfDay(hour: 9, minute: 0);
    final combined = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      time.hour,
      time.minute,
    );
    widget.onDateTimeChanged(combined);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate != null && _selectedDate!.isAfter(now)
          ? _selectedDate!
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _selectedTime ??= const TimeOfDay(hour: 9, minute: 0);
    });
    _notifyChange();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedTime = picked;
    });
    _notifyChange();
  }

  void _clearDueDate() {
    setState(() {
      _selectedDate = null;
      _selectedTime = null;
    });
    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('dena_pawna_more_options_toggle'),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: colors.brand,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  GochanoLanguage.text('More options', 'আরও অপশন'),
                  style: type.bodySecondary.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_selectedDate != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.brandSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      GochanoLanguage.text('Reminder set', 'রিমাইন্ডার সেট'),
                      style: type.caption.copyWith(color: colors.brand),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: GochanoSpacing.xs),
          Container(
            padding: const EdgeInsets.all(GochanoSpacing.sm),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Due date selector
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: const ValueKey('dena_pawna_due_date_tile'),
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                GochanoLanguage.text(
                                  'Due date (optional)',
                                  'পরিশোধের তারিখ (ঐচ্ছিক)',
                                ),
                                style: type.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selectedDate != null
                                    ? formatShortDate(_selectedDate!)
                                    : GochanoLanguage.text(
                                        'No due date',
                                        'তারিখ নির্ধারিত নেই',
                                      ),
                                style: type.body.copyWith(
                                  color: _selectedDate != null
                                      ? colors.textPrimary
                                      : colors.textTertiary,
                                  fontWeight: _selectedDate != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_selectedDate != null)
                      IconButton(
                        tooltip: GochanoLanguage.text('Clear', 'মুছুন'),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.textTertiary,
                        ),
                        onPressed: _clearDueDate,
                      ),
                  ],
                ),

                // Reminder time selector (shown when due date is set)
                if (_selectedDate != null) ...[
                  const Divider(height: 12),
                  InkWell(
                    key: const ValueKey('dena_pawna_reminder_time_tile'),
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 18,
                            color: colors.brand,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  GochanoLanguage.text(
                                    'Reminder time',
                                    'রিমাইন্ডার সময়',
                                  ),
                                  style: type.caption.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedTime != null
                                      ? _selectedTime!.format(context)
                                      : '9:00 AM',
                                  style: type.body.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.access_time_rounded,
                            size: 18,
                            color: colors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
