import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';

class MedicineFormScreen extends StatefulWidget {
  const MedicineFormScreen({
    super.key,
    this.medicineId,
    this.initialData,
    this.ocrSourceText = '',
    this.ocrSuggested = false,
  });

  final String? medicineId;
  final Map<String, dynamic>? initialData;
  final String ocrSourceText;
  final bool ocrSuggested;

  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  late final TextEditingController name;
  late final TextEditingController strength;
  late final TextEditingController instruction;
  late final TextEditingController quantity;
  late final TextEditingController unitPrice;
  late final TextEditingController packPrice;
  late final TextEditingController unitsInPack;
  late String unit;
  late String priceMode;
  late List<String> times;
  late DateTime startDate;
  DateTime? endDate;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData ?? const <String, dynamic>{};
    name = TextEditingController(text: d['name']?.toString() ?? '');
    strength = TextEditingController(
      text: d['strength']?.toString() ?? '',
    );
    instruction = TextEditingController(
      text: d['instruction']?.toString() ?? d['dose']?.toString() ?? '',
    );
    quantity = TextEditingController(
      text: ((d['quantityPerDose'] as num?)?.toDouble() ?? 1).toString(),
    );
    unitPrice = TextEditingController(
      text: ((d['unitPrice'] as num?)?.toDouble() ?? 0) == 0
          ? ''
          : (d['unitPrice'] as num).toString(),
    );
    packPrice = TextEditingController(
      text: ((d['packPrice'] as num?)?.toDouble() ?? 0) == 0
          ? ''
          : (d['packPrice'] as num).toString(),
    );
    unitsInPack = TextEditingController(
      text: ((d['unitsInPack'] as num?)?.toDouble() ?? 0) == 0
          ? ''
          : (d['unitsInPack'] as num).toString(),
    );
    unit = d['unit']?.toString() ?? 'tablet';
    priceMode = d['priceMode']?.toString() ?? 'unit';
    times = ((d['times'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final start = d['startDate'];
    startDate = start is Timestamp ? start.toDate() : DateTime.now();
    final end = d['endDate'];
    endDate = end is Timestamp ? end.toDate() : null;
  }

  @override
  void dispose() {
    name.dispose();
    strength.dispose();
    instruction.dispose();
    quantity.dispose();
    unitPrice.dispose();
    packPrice.dispose();
    unitsInPack.dispose();
    super.dispose();
  }

  double get calculatedUnitPrice {
    if (priceMode == 'unit') {
      return double.tryParse(unitPrice.text.trim()) ?? 0;
    }
    final price = double.tryParse(packPrice.text.trim()) ?? 0;
    final count = double.tryParse(unitsInPack.text.trim()) ?? 0;
    return count <= 0 ? 0 : price / count;
  }

  Future<void> _friendlyAlert(String message) async {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.checklist_rtl, color: EkColors.purple),
        title: Text(
          EkLanguage.text('Please review', 'দয়া করে যাচাই করুন'),
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: Text(EkLanguage.text('Got it', 'বুঝেছি')),
          ),
        ],
      ),
    );
  }

  Future<void> addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: EkLanguage.text('Add reminder time', 'রিমাইন্ডারের সময় যোগ করুন'),
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (!times.contains(value)) {
      setState(() {
        times.add(value);
        times.sort();
      });
    }
  }

  Future<void> save() async {
    final medName = name.text.trim();
    final qty = double.tryParse(quantity.text.trim()) ?? 0;
    final price = calculatedUnitPrice;

    if (medName.isEmpty) {
      await _friendlyAlert(
        EkLanguage.text('Medicine name is required.', 'ও�ুধের নাম প্রয়োজন।'),
      );
      return;
    }
    if (qty <= 0) {
      await _friendlyAlert(
        EkLanguage.text(
          'Quantity per dose must be greater than zero.',
          'প্রতি ডোজের পরিমাণ শূন্যের বেশি হতে হবে।',
        ),
      );
      return;
    }
    if (price < 0) {
      await _friendlyAlert(
        EkLanguage.text('Price cannot be negative.', 'দাম ঋণাত্মক হতে পারে না।'),
      );
      return;
    }
    if (times.isEmpty) {
      await _friendlyAlert(
        EkLanguage.text(
          'Confirm at least one reminder time. Gochano will not guess reminder times.',
          'অন্তত একটি রি�াইন্ডারের সময় নিশ্চিত করুন। Gochano সময় অনুমান করবে না।',
        ),
      );
      return;
    }

    setState(() => busy = true);
    try {
      final db = FirestoreService.db;
      final ref = widget.medicineId == null
          ? db.collection('medicines').doc()
          : db.collection('medicines').doc(widget.medicineId);

      List<String> oldTimes = const [];
      if (widget.medicineId != null) {
        final old = await ref.get();
        oldTimes = ((old.data()?['times'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        await NotificationService.cancelMedicineTimes(ref.id, oldTimes);
      }

      await ref.set(
        {
          'ownerId': FirestoreService.uid,
          'name': medName,
          'strength': strength.text.trim(),
          'instruction': instruction.text.trim(),
          'dose': instruction.text.trim(),
          'quantityPerDose': qty,
          'unit': unit,
          'priceMode': priceMode,
          'unitPrice': price,
          'packPrice': priceMode == 'pack'
              ? double.tryParse(packPrice.text.trim()) ?? 0
              : null,
          'unitsInPack': priceMode == 'pack'
              ? double.tryParse(unitsInPack.text.trim()) ?? 0
              : null,
          'times': times,
          'schedule': times.join(', '),
          'startDate': Timestamp.fromDate(startDate),
          'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
          'active': true,
          'paused': false,
          'confirmedByUser': true,
          'ocrSuggested': widget.ocrSuggested,
          'ocrSourceText': widget.ocrSourceText,
          if (widget.medicineId == null) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      for (final hhmm in times) {
        await NotificationService.scheduleDailyMedicine(
          medicineId: ref.id,
          medicineName: medName,
          hhmm: hhmm,
          instruction: instruction.text.trim(),
          quantityPerDose: qty,
          unitPrice: price,
          unit: unit,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.medicineId != null;
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Text(
            editing
                ? EkLanguage.text('Edit Medicine', 'ওষুধ সম্পাদনা')
                : EkLanguage.text('Add Medicine (Manual)', 'ওষুধ যোগ করুন (ম্যানুয়াল)'),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : save,
              child: Text(EkLanguage.text('Save', 'সংরক্ষণ')),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (widget.ocrSuggested)
              Container(
                padding: const EdgeInsets.all(13),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  EkLanguage.text(
                    'OCR suggestion only. Verify every field before saving. Gochano does not provide medical advice.',
                    'এটি শুধু OCR-এর পরামর্শ। সংরক্ষণের আগে সব তথ্য যাচাই করুন। Gochano চিকিৎসা পরামর্শ দেয় না।',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            SectionHeader(
              title: Text(EkLanguage.text('Medicine Info', 'ওষুধের তথ্য')),
              subtitle: Text(
                EkLanguage.text(
                  'Required fields are marked with *',
                  'আবশ্যক ক্ষেত্রগুলো * চিহ্নিত',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: EkLanguage.text('Medicine Name *', 'ওষুধের নাম *'),
                hintText: 'e.g. Napa',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: strength,
              decoration: InputDecoration(
                labelText: EkLanguage.text('Strength', 'ক্ষমতা'),
                hintText: EkLanguage.text('e.g. 500mg, 5mg/ml', 'যেমন: 500mg, 5mg/ml'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: instruction,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: EkLanguage.text('Dose / Instruction', 'ডোজ / নির্দেশনা'),
                hintText: EkLanguage.text('e.g. After food', 'যেমন: খাবার পরে'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: EkLanguage.text('Quantity per dose *', 'প্রতি ডোজের পরিমাণ *'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: unit,
                    decoration: InputDecoration(
                      labelText: EkLanguage.text('Unit', 'একক'),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'tablet', child: Text('Tablet')),
                      DropdownMenuItem(value: 'capsule', child: Text('Capsule')),
                      DropdownMenuItem(value: 'ml', child: Text('ml')),
                      DropdownMenuItem(value: 'spoon', child: Text('Spoon')),
                      DropdownMenuItem(value: 'drop', child: Text('Drop')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => unit = v ?? 'tablet'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SectionHeader(
              title: Text(EkLanguage.text('Price', 'দাম')),
              subtitle: Text(
                EkLanguage.text(
                  'Unit price is used for cost calculations.',
                  'ইউনিট দাম খরচ গণনায় ব্যবহৃত হয়।',
                ),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'unit',
                  label: Text(EkLanguage.text('Per Unit', 'প্রতি ইউনিট')),
                ),
                ButtonSegment(
                  value: 'pack',
                  label: Text(EkLanguage.text('Pack / Strip / Bottle', 'প্যাক / স্ট্রিপ / বোতল')),
                ),
              ],
              selected: {priceMode},
              onSelectionChanged: (value) => setState(() => priceMode = value.first),
            ),
            const SizedBox(height: 12),
            if (priceMode == 'unit')
              TextField(
                controller: unitPrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: EkLanguage.text('Unit price (৳)', 'প্রতি ইউনিট দাম (৳)'),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: packPrice,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: EkLanguage.text('Pack price (৳)', 'প্যাকের দাম (৳)'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: unitsInPack,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: EkLanguage.text('Units in pack', 'প্যাকে ইউনিট'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedBuilder(
                animation: Listenable.merge([packPrice, unitsInPack]),
                builder: (context, _) => Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBF4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${EkLanguage.text('Calculated unit price', 'গণনা করা ইউনিট দাম')}: ৳${calculatedUnitPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF16704A)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            SectionHeader(
              title: Text(EkLanguage.text('Schedule', 'সময়সূচী')),
              subtitle: Text(
                EkLanguage.text(
                  'Confirm at least one reminder time.',
                  'অন্তত একটি রিমাইন্ডারের সময় নিশ্চিত করুন।',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final time in times)
                  InputChip(
                    label: Text(time),
                    onDeleted: () => setState(() => times.remove(time)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_alarm, size: 18),
                  label: Text(EkLanguage.text('Add', 'যোগ')),
                  onPressed: addTime,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                        initialDate: startDate,
                      );
                      if (picked != null) setState(() => startDate = picked);
                    },
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(
                      '${EkLanguage.text('Start', 'শুরু')}: ${DateFormat('dd MMM yyyy').format(startDate)}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final initial = endDate ?? startDate.add(const Duration(days: 7));
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: startDate,
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                        initialDate: initial,
                      );
                      if (picked != null) setState(() => endDate = picked);
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      endDate == null
                          ? EkLanguage.text('No end date', 'শেষ তারিখ নেই')
                          : DateFormat('dd MMM yyyy').format(endDate!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: busy ? null : save,
              icon: const Icon(Icons.save_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  busy
                      ? EkLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…')
                      : EkLanguage.text('Save Medicine', 'ওষুধ সংরক্ষণ'),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: EkColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
