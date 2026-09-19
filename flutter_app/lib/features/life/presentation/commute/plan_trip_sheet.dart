import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/feedback_messages.dart';
import '../../../../core/localization/gochano_dates.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import 'commute_place_picker.dart';
import 'planned_trip_models.dart';

/// Immutable result contract for the trip save flow.
@immutable
class TripSaveResult {
  const TripSaveResult({
    required this.saved,
    this.reminderMinutes = 30,
    this.isEdit = false,
    this.deleted = false,
    this.completed = false,
  });

  final bool saved;
  final int reminderMinutes;
  final bool isEdit;
  final bool deleted;
  final bool completed;
}

Future<TripSaveResult?> showPlanTripSheet(
  BuildContext context, {
  CommutePlace? initialOrigin,
  CommutePlace? initialDestination,
  PlannedCommuteTrip? existingTrip,
}) async {
  final result = await showModalBottomSheet<TripSaveResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: PlanTripForm(
        initialOrigin: initialOrigin,
        initialDestination: initialDestination,
        existingTrip: existingTrip,
      ),
    ),
  );
  if (result != null &&
      result.saved &&
      !result.deleted &&
      !result.completed &&
      context.mounted) {
    showGochanoMessage(
      context,
      FeedbackMessages.tripPlanned(
        reminderMinutes: result.reminderMinutes,
        isEdit: result.isEdit,
        isOffline: !ConnectivityService.instance.online.value,
      ),
    );
  }
  return result;
}

class PlanTripForm extends StatefulWidget {
  const PlanTripForm({
    super.key,
    this.initialOrigin,
    this.initialDestination,
    this.existingTrip,
  });

  final CommutePlace? initialOrigin;
  final CommutePlace? initialDestination;
  final PlannedCommuteTrip? existingTrip;

  @override
  State<PlanTripForm> createState() => _PlanTripFormState();
}

class _PlanTripFormState extends State<PlanTripForm> {
  late CommutePlace? _origin;
  late CommutePlace? _destination;
  late DateTime _date;
  late TimeOfDay _time;
  late int _reminderMinutes;
  late bool _showMoreOptions;
  PlannedCommuteTrip? _editingTrip;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _editingTrip = widget.existingTrip;
    _origin = widget.existingTrip != null
        ? CommutePlace(
            name: widget.existingTrip!.originName,
            lat: widget.existingTrip!.originLat,
            lon: widget.existingTrip!.originLon,
          )
        : widget.initialOrigin;
    _destination = widget.existingTrip != null
        ? CommutePlace(
            name: widget.existingTrip!.destinationName,
            lat: widget.existingTrip!.destinationLat,
            lon: widget.existingTrip!.destinationLon,
          )
        : widget.initialDestination;
    _date = widget.existingTrip?.departureTime ?? DateTime.now();
    _time = widget.existingTrip != null
        ? TimeOfDay.fromDateTime(widget.existingTrip!.departureTime)
        : TimeOfDay.fromDateTime(
            DateTime.now().add(const Duration(minutes: 30)),
          );
    _reminderMinutes = widget.existingTrip?.reminderMinutes ?? 30;
    _showMoreOptions =
        widget.existingTrip != null &&
        widget.existingTrip!.reminderMinutes != 30;
  }

  DateTime get _departureDateTime =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
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
      if (_editingTrip != null) {
        await CommuteTripService.updateTrip(
          tripId: _editingTrip!.id,
          originName: origin.name,
          destinationName: destination.name,
          originLat: origin.lat,
          originLon: origin.lon,
          destinationLat: destination.lat,
          destinationLon: destination.lon,
          departureTime: departure,
          reminderMinutes: _reminderMinutes,
        );
      } else {
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
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        TripSaveResult(
          saved: true,
          reminderMinutes: _reminderMinutes,
          isEdit: _editingTrip != null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _delete() async {
    final existing = _editingTrip;
    if (existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          GochanoLanguage.text('Delete planned trip?', 'যাত্রা মুছে ফেলবেন?'),
        ),
        content: Text(
          GochanoLanguage.text(
            'This trip and its reminder will be cancelled.',
            'এই যাত্রা এবং এর রিমাইন্ডার বাতিল করা হবে।',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(GochanoLanguage.text('Delete', 'মুছুন')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });

    try {
      await CommuteTripService.deleteTrip(existing);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(const TripSaveResult(saved: true, deleted: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _complete() async {
    final existing = _editingTrip;
    if (existing == null || existing.isCompleted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          GochanoLanguage.text('I did the trip', 'ভ্রমণটি সম্পন্ন করেছি'),
        ),
        content: Text(
          GochanoLanguage.text(
            'This trip will be marked as completed and removed from upcoming.',
            'এই যাত্রা সম্পন্ন হিসাবে চিহ্নিত হবে এবং আসন্ন তালিকা থেকে সরিয়ে ফেলা হবে।',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              GochanoLanguage.text('I did the trip', 'ভ্রমণটি সম্পন্ন করেছি'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await CommuteTripService.completeTrip(existing);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(const TripSaveResult(saved: true, completed: true));
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
    final isEditing = _editingTrip != null;

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
                  isEditing
                      ? GochanoLanguage.text(
                          'Edit planned trip',
                          'যাত্রা সম্পাদনা',
                        )
                      : GochanoLanguage.text(
                          'Plan a future trip',
                          'ভবিষ্যৎ যাত্রা পরিকল্পনা',
                        ),
                  style: type.sectionHeading,
                ),
              ),
              IconButton(
                tooltip: GochanoLanguage.text('Close', 'বন্ধ করুন'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),

          // Origin & Destination pickers
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.trip_origin_rounded, color: colors.commute),
            title: Text(
              _origin?.name ??
                  GochanoLanguage.text(
                    'Pick starting place',
                    'শুরুর স্থান বাছুন',
                  ),
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
              _destination?.name ??
                  GochanoLanguage.text('Pick destination', 'গন্তব্য বাছুন'),
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
                  label: Text(() {
                    final h = _time.hour;
                    final h12 = h % 12 == 0 ? 12 : h % 12;
                    final m = _time.minute.toString().padLeft(2, '0');
                    return '$h12:$m ${h < 12 ? 'AM' : 'PM'}';
                  }()),
                ),
              ),
            ],
          ),
          // More options toggle (progressive disclosure)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('trip_more_options_toggle'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                style: type.bodySecondary.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.brand,
                ),
              ),
            ),
          ),

          if (_showMoreOptions) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text(
                'Leave-by Reminder',
                'রওনা হওয়ার রিমাইন্ডার',
              ),
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
                          : mins == 60
                          ? GochanoLanguage.text('1 hour before', '১ ঘণ্টা আগে')
                          : GochanoLanguage.text(
                              '$mins min before',
                              '${GochanoLanguage.toBanglaDigits(mins)} মিনিট আগে',
                            ),
                    ),
                    selected: _reminderMinutes == mins,
                    onSelected: (val) {
                      if (val) setState(() => _reminderMinutes = mins);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: GochanoSpacing.md),

          if (_error != null) ...[
            Text(_error!, style: type.caption.copyWith(color: colors.error)),
            const SizedBox(height: GochanoSpacing.sm),
          ],

          PrimaryButton(
            label: isEditing
                ? GochanoLanguage.text('Update trip', 'যাত্রা আপডেট করুন')
                : GochanoLanguage.text('Save planned trip', 'যাত্রা সেভ করুন'),
            busy: _saving,
            onPressed: (_saving || _deleting) ? null : _save,
          ),

          if (isEditing) ...[
            const SizedBox(height: GochanoSpacing.sm),
            if (_editingTrip != null &&
                _editingTrip!.isUpcoming &&
                !_editingTrip!.isCompleted) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_saving || _deleting) ? null : _complete,
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    GochanoLanguage.text(
                      'I did the trip',
                      'ভ্রমণটি সম্পন্ন করেছি',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),
            ],
            OutlinedButton.icon(
              onPressed: (_saving || _deleting) ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.delete_outline_rounded, color: colors.error),
              label: Text(
                GochanoLanguage.text('Delete trip', 'যাত্রা মুছুন'),
                style: type.label.copyWith(color: colors.error),
              ),
            ),
          ] else ...[
            const SizedBox(height: GochanoSpacing.lg),
            const Divider(),
            const SizedBox(height: GochanoSpacing.xs),
            _PlannedTripsListSection(
              onSelectTrip: (trip) {
                Navigator.of(context).pop();
                showPlanTripSheet(context, existingTrip: trip);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PlannedTripsListSection extends StatelessWidget {
  const _PlannedTripsListSection({required this.onSelectTrip});

  final void Function(PlannedCommuteTrip trip) onSelectTrip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return StreamBuilder<List<PlannedCommuteTrip>>(
      stream: CommuteTripService.streamPlannedTrips(),
      builder: (context, snapshot) {
        final trips = snapshot.data ?? const [];
        if (trips.isEmpty) return const SizedBox.shrink();

        final upcoming = trips.where((t) => t.isUpcoming).toList();
        final missed = trips
            .where((t) => t.isMissed)
            .toList()
            .reversed
            .toList();
        final completed = trips
            .where((t) => t.isCompleted)
            .toList()
            .reversed
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GochanoLanguage.text(
                'Your Planned Trips',
                'আপনার পরিকল্পিত যাত্রা',
              ),
              style: type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            if (upcoming.isNotEmpty) ...[
              for (final trip in upcoming)
                _PlannedTripTile(
                  trip: trip,
                  isMissed: false,
                  onTap: () => onSelectTrip(trip),
                ),
            ],
            if (missed.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text('History', 'ইতিহাস'),
                style: type.label.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              for (final trip in missed)
                _PlannedTripTile(
                  trip: trip,
                  isMissed: true,
                  onTap: () => onSelectTrip(trip),
                ),
            ],
            if (completed.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text('Completed', 'সম্পন্ন'),
                style: type.label.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              for (final trip in completed)
                _PlannedTripTile(
                  trip: trip,
                  isMissed: false,
                  isCompleted: true,
                  onTap: () => onSelectTrip(trip),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _PlannedTripTile extends StatelessWidget {
  const _PlannedTripTile({
    required this.trip,
    required this.isMissed,
    required this.onTap,
    this.isCompleted = false,
  });

  final PlannedCommuteTrip trip;
  final bool isMissed;
  final bool isCompleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final tripDateTimeStr = formatPlannedTripDateTime(trip.departureTime);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
        child: Row(
          children: [
            Icon(
              isCompleted
                  ? Icons.check_circle_outline_rounded
                  : isMissed
                  ? Icons.history_rounded
                  : Icons.directions_transit_rounded,
              size: 20,
              color: isCompleted
                  ? colors.success
                  : isMissed
                  ? colors.textTertiary
                  : colors.commute,
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trip.originName} → ${trip.destinationName}',
                    style: type.body.copyWith(
                      color: isMissed
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    tripDateTimeStr,
                    style: type.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GochanoSpacing.xs),
            if (isCompleted)
              GochanoBadge(
                label: GochanoLanguage.text('Completed', 'সম্পন্ন'),
                tone: GochanoBadgeTone.success,
              )
            else if (isMissed)
              GochanoBadge(
                label: GochanoLanguage.text('Missed', 'মিসড'),
                tone: GochanoBadgeTone.warning,
              )
            else
              GochanoBadge(
                label: GochanoLanguage.text('Upcoming', 'আসন্ন'),
                tone: GochanoBadgeTone.neutral,
              ),
          ],
        ),
      ),
    );
  }
}
