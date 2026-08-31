// Add / edit a medicine (spec §52, §57, §59).
//
// Manual entry is always available and is never skippable — a prescription
// scan lands *here* with fields pre-filled for the student to correct and
// confirm, it does not save anything on its own (spec §57).
//
// The single hard rule in this form: **Gochano never guesses a reminder
// time.** OCR can suggest a medicine name and a dose because those are
// printed on the paper; a schedule is a medical decision, so at least one
// time must be entered by the student before the form will save.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../home/presentation/home_screen.dart' show formatTaka;

class MedicineFormScreen extends StatefulWidget {
  const MedicineFormScreen({
    super.key,
    this.medicineId,
    this.initialData,
    this.ocrSourceText = '',
    this.ocrSuggested = false,
  });

  /// Edit an existing medicine. When set and [initialData] is null the
  /// document is fetched on open.
  final String? medicineId;

  /// Pre-filled values — used by the prescription review step.
  final Map<String, dynamic>? initialData;

  /// The OCR text these values came from, stored for provenance so a student
  /// can later see what the suggestion was based on.
  final String ocrSourceText;

  /// True when the values arrived from OCR rather than from typing.
  final bool ocrSuggested;

  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  static const _units = ['tablet', 'capsule', 'ml', 'drop', 'sachet', 'unit'];

  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _instruction = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unitPrice = TextEditingController();
  final _packPrice = TextEditingController();
  final _unitsInPack = TextEditingController();

  String _unit = 'tablet';
  String _priceMode = 'unit';
  List<String> _times = [];
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.medicineId != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _apply(widget.initialData!);
    } else if (widget.medicineId != null) {
      _loading = true;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    try {
      final snap = await FirestoreService.db
          .collection('medicines')
          .doc(widget.medicineId)
          .get();
      if (!mounted) return;
      setState(() {
        _apply(snap.data() ?? const <String, dynamic>{});
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  void _apply(Map<String, dynamic> d) {
    _name.text = d['name']?.toString() ?? '';
    _strength.text = d['strength']?.toString() ?? '';
    _instruction.text =
        d['instruction']?.toString() ?? d['dose']?.toString() ?? '';
    _quantity.text = _trim((d['quantityPerDose'] as num?)?.toDouble() ?? 1);
    final unitPrice = (d['unitPrice'] as num?)?.toDouble() ?? 0;
    _unitPrice.text = unitPrice == 0 ? '' : _trim(unitPrice);
    final packPrice = (d['packPrice'] as num?)?.toDouble() ?? 0;
    _packPrice.text = packPrice == 0 ? '' : _trim(packPrice);
    final unitsInPack = (d['unitsInPack'] as num?)?.toDouble() ?? 0;
    _unitsInPack.text = unitsInPack == 0 ? '' : _trim(unitsInPack);
    _unit = _units.contains(d['unit']) ? d['unit'].toString() : 'tablet';
    _priceMode = d['priceMode']?.toString() == 'pack' ? 'pack' : 'unit';
    _times = ((d['times'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    final start = d['startDate'];
    _startDate = start is Timestamp ? start.toDate() : DateTime.now();
    final end = d['endDate'];
    _endDate = end is Timestamp ? end.toDate() : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _instruction.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    _packPrice.dispose();
    _unitsInPack.dispose();
    super.dispose();
  }

  /// Per-unit price, whichever way the student chose to enter it.
  ///
  /// Pack mode exists because medicine is usually sold by the strip: a
  /// student knows "৳80 for 10 tablets", not "৳8 per tablet".
  double get _resolvedUnitPrice {
    if (_priceMode == 'unit') {
      return double.tryParse(_unitPrice.text.trim()) ?? 0;
    }
    final price = double.tryParse(_packPrice.text.trim()) ?? 0;
    final count = double.tryParse(_unitsInPack.text.trim()) ?? 0;
    return count <= 0 ? 0 : price / count;
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: GochanoLanguage.text(
        'Add reminder time',
        'রিমাইন্ডারের সময় যোগ করুন',
      ),
    );
    if (picked == null) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    if (_times.contains(value)) return;
    setState(() {
      _times = [..._times, value]..sort();
      _error = null;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? now),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final quantity = double.tryParse(_quantity.text.trim()) ?? 0;
    final price = _resolvedUnitPrice;

    String? problem;
    if (name.isEmpty) {
      problem = GochanoLanguage.text(
        'Enter the medicine name.',
        'ওষুধের নাম লিখুন।',
      );
    } else if (quantity <= 0) {
      problem = GochanoLanguage.text(
        'Quantity per dose must be greater than zero.',
        'প্রতি ডোজের পরিমাণ শূন্যের বেশি হতে হবে।',
      );
    } else if (price < 0) {
      problem = GochanoLanguage.text(
        'Price cannot be negative.',
        'দাম ঋণাত্মক হতে পারে না।',
      );
    } else if (_times.isEmpty) {
      // The rule that keeps Gochano out of medical decisions.
      problem = GochanoLanguage.text(
        'Add at least one reminder time. Gochano will not guess when to take '
        'a medicine.',
        'অন্তত একটি রিমাইন্ডারের সময় যোগ করুন। কখন ওষুধ খেতে হবে গোছানো তা অনুমান করবে না।',
      );
    }

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = FirestoreService.db;
      final ref = widget.medicineId == null
          ? db.collection('medicines').doc()
          : db.collection('medicines').doc(widget.medicineId);

      // Clear the old schedule before writing the new one, or an edited
      // medicine keeps firing at times the student removed.
      if (widget.medicineId != null) {
        final old = await ref.get();
        final oldTimes = ((old.data()?['times'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        await NotificationService.cancelMedicineTimes(ref.id, oldTimes);
      }

      await ref.set(
        {
          'ownerId': FirestoreService.uid,
          'name': name,
          'strength': _strength.text.trim(),
          'instruction': _instruction.text.trim(),
          // `dose` is the legacy field name; both are written so older
          // reads keep working.
          'dose': _instruction.text.trim(),
          'quantityPerDose': quantity,
          'unit': _unit,
          'priceMode': _priceMode,
          'unitPrice': price,
          'packPrice': _priceMode == 'pack'
              ? double.tryParse(_packPrice.text.trim()) ?? 0
              : null,
          'unitsInPack': _priceMode == 'pack'
              ? double.tryParse(_unitsInPack.text.trim()) ?? 0
              : null,
          'times': _times,
          'schedule': _times.join(', '),
          'startDate': Timestamp.fromDate(_startDate),
          'endDate': _endDate == null ? null : Timestamp.fromDate(_endDate!),
          'active': true,
          'paused': false,
          // Provenance: whatever OCR suggested, this document only exists
          // because the student pressed Save on it.
          'confirmedByUser': true,
          'ocrSuggested': widget.ocrSuggested,
          'ocrSourceText': widget.ocrSourceText,
          if (widget.medicineId == null)
            'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      for (final hhmm in _times) {
        await NotificationService.scheduleDailyMedicine(
          medicineId: ref.id,
          medicineName: name,
          hhmm: hhmm,
          instruction: _instruction.text.trim(),
          quantityPerDose: quantity,
          unitPrice: price,
          unit: _unit,
        );
      }

      // If the OS denied notification permission the schedule calls above
      // silently do nothing, so say so rather than letting the student
      // believe reminders are armed.
      final notificationsEnabled =
          await NotificationService.areNotificationsEnabled();

      if (!mounted) return;
      Navigator.of(context).pop(true);
      if (notificationsEnabled == false) {
        showGochanoMessage(
          context,
          GochanoLanguage.text(
            'Saved. Reminders will not appear until notifications are enabled '
            'for Gochano in system settings.',
            'সংরক্ষিত হয়েছে। সিস্টেম সেটিংসে নোটিফিকেশন চালু না করা পর্যন্ত রিমাইন্ডার দেখা যাবে না।',
          ),
          isError: true,
        );
      }
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
    final type = context.type;

    if (_loading) {
      return GochanoScaffold(
        appBar: GochanoAppBar(
          title: GochanoLanguage.text('Edit medicine', 'ওষুধ সম্পাদনা'),
        ),
        body: StaticLoadingState(
          message: GochanoLanguage.text(
            'Loading this medicine…',
            'ওষুধটি লোড হচ্ছে…',
          ),
        ),
      );
    }

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: _isEdit
            ? GochanoLanguage.text('Edit medicine', 'ওষুধ সম্পাদনা')
            : GochanoLanguage.text('Add medicine', 'ওষুধ যোগ করুন'),
      ),
      bottomBar: PrimaryButton(
        label: GochanoLanguage.text('Save medicine', 'ওষুধ সংরক্ষণ'),
        busy: _saving,
        busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
        onPressed: _save,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (widget.ocrSuggested) ...[
            const _OcrReviewNotice(),
            const SizedBox(height: GochanoSpacing.md),
          ],

          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Medicine name', 'ওষুধের নাম'),
              hintText: 'Napa',
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _strength,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text(
                'Strength (optional)',
                'শক্তি (ঐচ্ছিক)',
              ),
              hintText: '500 mg',
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _instruction,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text(
                'Instruction (optional)',
                'নির্দেশনা (ঐচ্ছিক)',
              ),
              hintText: GochanoLanguage.text('After food', 'খাবারের পরে'),
            ),
          ),

          SectionHeader(
            title: GochanoLanguage.text('Each dose', 'প্রতি ডোজ'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantity,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('How many', 'কতটি'),
                  ),
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Form', 'ধরন'),
                  ),
                  items: [
                    for (final unit in _units)
                      DropdownMenuItem(value: unit, child: Text(unit)),
                  ],
                  onChanged: (value) =>
                      setState(() => _unit = value ?? 'tablet'),
                ),
              ),
            ],
          ),

          SectionHeader(
            title: GochanoLanguage.text('Reminder times', 'রিমাইন্ডারের সময়'),
            subtitle: GochanoLanguage.text(
              'You choose these. Gochano never sets them for you.',
              'আপনি এগুলো নির্ধারণ করবেন। গোছানো কখনো নিজে থেকে সেট করবে না।',
            ),
          ),
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xs,
            children: [
              for (final time in _times)
                InputChip(
                  label: Text(time),
                  avatar: Icon(
                    Icons.access_time_rounded,
                    size: 16,
                    color: colors.medicine,
                  ),
                  onDeleted: () =>
                      setState(() => _times = [..._times]..remove(time)),
                  deleteButtonTooltipMessage: GochanoLanguage.text(
                    'Remove $time',
                    '$time মুছুন',
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(GochanoLanguage.text('Add time', 'সময় যোগ')),
                onPressed: _addTime,
              ),
            ],
          ),

          SectionHeader(
            title: GochanoLanguage.text('Course dates', 'কোর্সের তারিখ'),
          ),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: GochanoLanguage.text('Start', 'শুরু'),
                  value: _formatDate(_startDate),
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: _DateField(
                  label: GochanoLanguage.text('End (optional)', 'শেষ (ঐচ্ছিক)'),
                  value: _endDate == null
                      ? GochanoLanguage.text('Ongoing', 'চলমান')
                      : _formatDate(_endDate!),
                  onTap: () => _pickDate(isStart: false),
                  onClear: _endDate == null
                      ? null
                      : () => setState(() => _endDate = null),
                ),
              ),
            ],
          ),

          SectionHeader(
            title: GochanoLanguage.text('Cost (optional)', 'খরচ (ঐচ্ছিক)'),
            subtitle: GochanoLanguage.text(
              'Used to add a taken dose to your monthly spending.',
              'নেওয়া ডোজ আপনার মাসিক খরচে যোগ করতে ব্যবহৃত হয়।',
            ),
          ),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'unit',
                label: Text(GochanoLanguage.text('Per unit', 'প্রতি একক')),
              ),
              ButtonSegment(
                value: 'pack',
                label: Text(GochanoLanguage.text('Per pack', 'প্রতি প্যাক')),
              ),
            ],
            selected: {_priceMode},
            onSelectionChanged: (value) =>
                setState(() => _priceMode = value.first),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          if (_priceMode == 'unit')
            TextField(
              controller: _unitPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Price per $_unit', 'প্রতি $_unit দাম'),
                prefixText: '৳ ',
              ),
              onChanged: (_) => setState(() {}),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _packPrice,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text('Pack price', 'প্যাকের দাম'),
                      prefixText: '৳ ',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: TextField(
                    controller: _unitsInPack,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text('Units in pack', 'প্যাকে কতটি'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          if (_resolvedUnitPrice > 0) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text(
                '${formatTaka(_resolvedUnitPrice)} per $_unit',
                'প্রতি $_unit ${formatTaka(_resolvedUnitPrice)}',
              ),
              style: type.caption,
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: GochanoSpacing.md),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: GochanoSizes.iconSm,
                    color: colors.error,
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      _error!,
                      style: type.bodySecondary.copyWith(color: colors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when the form was reached from a prescription scan (spec §58).
class _OcrReviewNotice extends StatelessWidget {
  const _OcrReviewNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warningSoft,
        borderRadius: GochanoRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GochanoIllustration(
            GochanoArt.featurePrescription,
            size: 32,
            accent: colors.warning,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Text(
              GochanoLanguage.text(
                'These values were read from your prescription image and may '
                'be wrong. Check the name, strength and dose, and set the '
                'reminder times yourself before saving.',
                'এই তথ্যগুলো আপনার প্রেসক্রিপশনের ছবি থেকে পড়া হয়েছে এবং ভুল হতে পারে। সংরক্ষণের আগে নাম, শক্তি ও ডোজ যাচাই করুন এবং রিমাইন্ডারের সময় নিজে নির্ধারণ করুন।',
              ),
              style: context.type.bodySecondary.copyWith(color: colors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: GochanoRadius.mdAll,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear == null
              ? null
              : IconActionButton(
                  icon: Icons.close_rounded,
                  label: GochanoLanguage.text('Clear', 'মুছুন'),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value,
          style: context.type.body,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

String _formatDate(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
