import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import 'commute_place_picker.dart';
import 'planned_trip_models.dart';

Future<bool?> showPlanTripSheet(
  BuildContext context, {
  CommutePlace? initialOrigin,
  CommutePlace? initialDestination,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _PlanTripForm(
        initialOrigin: initialOrigin,
        initialDestination: initialDestination,
      ),
    ),
  );
}

class _PlanTripForm extends StatefulWidget {
  const _PlanTripForm({
    this.initialOrigin,
    this.initialDestination,
  });

  final CommutePlace? initialOrigin;
  final CommutePlace? initialDestination;

  @override
  State<_PlanTripForm> createState() => _PlanTripFormState();
}

class _PlanTripFormState extends State<_PlanTripForm> {
  late CommutePlace? _origin = widget.initialOrigin;
  late CommutePlace? _destination = widget.initialDestination;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(minutes: 30)),
  );
  int _reminderMinutes = 30;
  bool _saving = false;
  String? _error;

  DateTime get _departureDateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickPlace({required bool isOrigin}) async {
    final place = await showCommutePlacePicker(
      context,
      title: isOrigin
          ? GochanoLanguage.text('Where from?', 'কোথা থেকে?')
          : GochanoLanguage.text('Where to?', 'কোথায় যাবেন?'),
    );
    if (place != null && mounted) {
      setState(() {
        if (isOrigin) {
          _origin = place;
        } else {
          _destination = place;
        }
      });
    }
  }

  Future<void> _save() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) {
      setState(() {
        _error = GochanoLanguage.text(
          'Please select both origin and destination.',
          'উৎস এবং গন্তব্য উভয়ই নির্বাচন করুন।',
        );
      });
      return;
    }

    final departure = _departureDateTime;
    if (!departure.isAfter(DateTime.now())) {
      setState(() {
        _error = GochanoLanguage.text(
          'Departure time must be in the future.',
          'যাত্রার সময় ভবিষ্যতের হতে হবে।',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await CommuteTripService.createTrip(
        originName: origin.name,
        destinationName: destination.name,
        originLat: origin.lat,
        originLon: origin.lon,
        destinationLat: destination.lat,
        destinationLon: destination.lon,
        departureTime: departure,
        reminderMinutes: _reminderMinutes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.departure_board_rounded, color: colors.commute),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Plan a future trip', 'ভবিষ্যৎ যাত্রা পরিকল্পনা'),
                  style: type.sectionHeading,
                ),
              ),
              IconButton(
                tooltip: GochanoLanguage.text('Close', 'বন্ধ করুন'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),

          // Origin & Destination pickers
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.trip_origin_rounded, color: colors.commute),
            title: Text(
              _origin?.name ?? GochanoLanguage.text('Pick starting place', 'শুরুর স্থান বাছুন'),
              style: _origin != null ? type.body : type.bodySecondary,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickPlace(isOrigin: true),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.place_rounded, color: colors.error),
            title: Text(
              _destination?.name ?? GochanoLanguage.text('Pick destination', 'গন্তব্য বাছুন'),
              style: _destination != null ? type.body : type.bodySecondary,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickPlace(isOrigin: false),
          ),
          const SizedBox(height: GochanoSpacing.md),

          // Date & Time pickers
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text('${_date.day}/${_date.month}/${_date.year}'),
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(_time.format(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.md),

          // Reminder chips
          Text(
            GochanoLanguage.text('Leave-by Reminder', 'রওনা হওয়ার রিমাইন্ডার'),
            style: type.label,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Wrap(
            spacing: GochanoSpacing.xs,
            children: [
              for (final mins in [0, 10, 30, 60])
                ChoiceChip(
                  label: Text(
                    mins == 0
                        ? GochanoLanguage.text('None', 'নেই')
                        : GochanoLanguage.text('$mins min before', '$mins মিনিট আগে'),
                  ),
                  selected: _reminderMinutes == mins,
                  onSelected: (val) {
                    if (val) setState(() => _reminderMinutes = mins);
                  },
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.md),

          if (_error != null) ...[
            Text(
              _error!,
              style: type.caption.copyWith(color: colors.error),
            ),
            const SizedBox(height: GochanoSpacing.sm),
          ],

          PrimaryButton(
            label: GochanoLanguage.text('Save planned trip', 'যাত্রা সেভ করুন'),
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
