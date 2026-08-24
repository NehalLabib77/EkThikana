import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';

class MedicineOcrScreen extends StatefulWidget {
  const MedicineOcrScreen({super.key});

  @override
  State<MedicineOcrScreen> createState() => _MedicineOcrScreenState();
}

class _MedicineOcrScreenState extends State<MedicineOcrScreen> {
  int step = 1;
  bool busy = false;
  String fileName = '';
  String rawText = '';
  String warning = '';
  final drafts = <_MedicineDraft>[];

  Future<void> _pickGallery() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null) return;
    final bytes = result.bytes ?? await result.readAsBytes();
    await _runOcr(bytes, result.name);
  }

  Future<void> _takePhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null) return;
    await _runOcr(await image.readAsBytes(), image.name);
  }

  String _normalizeTime(String value) {
    final source = value.trim().toLowerCase().replaceAll('.', ':');
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)?$').firstMatch(source);
    if (match == null) return '';
    var hour = int.tryParse(match.group(1)!) ?? -1;
    final minute = int.tryParse(match.group(2)!) ?? -1;
    final suffix = match.group(3);
    if (minute < 0 || minute > 59) return '';
    if (suffix != null) {
      if (hour < 1 || hour > 12) return '';
      if (suffix == 'pm' && hour != 12) hour += 12;
      if (suffix == 'am' && hour == 12) hour = 0;
    }
    if (hour < 0 || hour > 23) return '';
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Future<void> _runOcr(Uint8List bytes, String name) async {
    setState(() {
      busy = true;
      fileName = name;
    });
    try {
      final result = await ApiService.prescriptionOcr(bytes: bytes, fileName: name);
      final meds = (result['medicines'] as List?) ?? const [];
      final parsed = <_MedicineDraft>[];
      for (final item in meds) {
        if (item is! Map) continue;
        final draft = _MedicineDraft(
          name: item['name']?.toString() ?? '',
          dose: item['dose']?.toString() ?? '',
          instruction: item['instruction']?.toString() ?? '',
          hint: ((item['scheduleHints'] as List?) ?? const []).join(' • '),
          source: item['sourceText']?.toString() ?? '',
        );
        for (final t in (item['explicitTimes'] as List?) ?? const []) {
          final normalized = _normalizeTime(t.toString());
          if (normalized.isNotEmpty && !draft.times.contains(normalized)) {
            draft.times.add(normalized);
          }
        }
        parsed.add(draft);
      }
      if (parsed.isEmpty) {
        parsed.add(_MedicineDraft(instruction: result['rawText']?.toString() ?? ''));
      }
      if (!mounted) return;
      setState(() {
        rawText = result['rawText']?.toString() ?? '';
        warning = result['warning']?.toString() ?? '';
        drafts
          ..clear()
          ..addAll(parsed);
        step = 2;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addTime(_MedicineDraft draft) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: EkLanguage.text('Confirm reminder time', 'রিমাইন্ডারের সময় নিশ্চিত করুন'),
    );
    if (selected == null) return;
    final time = '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    if (!draft.times.contains(time)) setState(() => draft.times.add(time));
  }

  Future<void> _save() async {
    final valid = drafts.where((d) => d.name.text.trim().isNotEmpty).toList();
    if (valid.isEmpty) {
      showError(context, Exception(EkLanguage.text('Enter at least one medicine name.', 'কমপক্ষে একটি ওষুধের নাম লিখুন।')));
      return;
    }
    if (valid.any((d) => d.times.isEmpty)) {
      showError(
        context,
        Exception(
          EkLanguage.text(
            'Confirm at least one actual reminder time for every medicine. EkThikana will not guess it from OCR.',
            'প্রতিটি ওষুধের জন্য অন্তত একটি সঠিক সময় নিজে নিশ্চিত করুন। EkThikana OCR থেকে সময় অনুমান করবে না।',
          ),
        ),
      );
      return;
    }

    setState(() => busy = true);
    try {
      for (final draft in valid) {
        final ref = await FirestoreService.addOwnerRecord('medicines', {
          'name': draft.name.text.trim(),
          'dose': draft.dose.text.trim(),
          'instruction': draft.instruction.text.trim(),
          'times': List<String>.from(draft.times)..sort(),
          'schedule': (List<String>.from(draft.times)..sort()).join(', '),
          'scheduleHint': draft.hint,
          'ocrSourceText': draft.source,
          'ocrConfirmed': true,
          'confirmedByUser': true,
          'active': true,
        });
        for (final time in draft.times) {
          await NotificationService.scheduleDailyMedicine(
            medicineId: ref.id,
            medicineName: draft.name.text.trim(),
            hhmm: time,
            instruction: [draft.dose.text.trim(), draft.instruction.text.trim()]
                .where((e) => e.isNotEmpty)
                .join(' • '),
          );
        }
      }
      if (!mounted) return;
      setState(() => step = 3);
      showSuccess(context, EkLanguage.text('Medicine reminders saved.', 'ওষুধের রিমাইন্ডার সংরক্ষিত হয়েছে।'));
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final d in drafts) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('Add Medicine (OCR)', 'ওষুধ যোগ করুন (OCR)')),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _StepBar(step: step),
              Expanded(
                child: step == 1 ? _uploadStep() : step == 2 ? _reviewStep() : _doneStep(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadStep() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 6),
        Text(
          EkLanguage.text('Upload Prescription', 'প্রেসক্রিপশন আপলোড করুন'),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          EkLanguage.text('Use a clear photo or PDF. Maximum 10 MB.', 'পরিষ্কার ছবি বা PDF ব্যবহার করুন। সর্বোচ্চ ১০ MB।'),
          style: const TextStyle(color: EkColors.muted),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9FF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: EkColors.purple.withValues(alpha: .42), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(color: EkColors.lavender, shape: BoxShape.circle),
                child: const Icon(Icons.cloud_upload_outlined, color: EkColors.purple, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                EkLanguage.text('Tap to upload or take a photo', 'ছবি তুলুন অথবা আপলোড করুন'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 5),
              const Text('JPG, PNG, PDF • Max 10MB', style: TextStyle(color: EkColors.muted, fontSize: 12)),
              if (fileName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _pickGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(EkLanguage.text('Gallery / PDF', 'গ্যালারি / PDF')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: busy ? null : _takePhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(EkLanguage.text('Camera', 'ক্যামেরা')),
                    ),
                  ),
                ],
              ),
              if (busy) ...[
                const SizedBox(height: 20),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(EkLanguage.text('Reading prescription…', 'প্রেসক্রিপশন পড়া হচ্ছে…')),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: EkColors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  EkLanguage.text(
                    'OCR extracts visible prescription text. It can be wrong. Review medicine name, dose/instructions and choose the real reminder time yourself before saving.',
                    'OCR প্রেসক্রিপশনের দৃশ্যমান লেখা বের করে। ভুল হতে পারে। সংরক্ষণের আগে ওষুধের নাম, ডোজ/নির্দেশনা এবং আসল সময় নিজে যাচাই করুন।',
                  ),
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewStep() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          EkLanguage.text('Review extracted medicines', 'বের করা ওষুধগুলো যাচাই করুন'),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          warning.isEmpty
              ? EkLanguage.text('Nothing is activated until you confirm it.', 'আপনি নিশ্চিত না করা পর্যন্ত কিছুই সক্রিয় হবে না।')
              : warning,
          style: const TextStyle(color: EkColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < drafts.length; i++) ...[
          _draftCard(drafts[i], i),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () => setState(() => drafts.add(_MedicineDraft())),
          icon: const Icon(Icons.add),
          label: Text(EkLanguage.text('Add another medicine', 'আরেকটি ওষুধ যোগ করুন')),
        ),
        const SizedBox(height: 10),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(EkLanguage.text('Show raw OCR text', 'মূল OCR লেখা দেখুন')),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: SelectableText(rawText.isEmpty ? '—' : rawText),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy ? null : _save,
          icon: const Icon(Icons.notifications_active_outlined),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(busy
                ? EkLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…')
                : EkLanguage.text('Confirm & Save Reminders', 'নিশ্চিত করে রিমাইন্ডার সংরক্ষণ করুন')),
          ),
        ),
      ],
    );
  }

  Widget _draftCard(_MedicineDraft draft, int index) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: const Color(0xFFEAFBF3), borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.medication_outlined, color: EkColors.green),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${EkLanguage.text('Medicine', 'ওষুধ')} ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (drafts.length > 1)
                  IconButton(
                    onPressed: () => setState(() {
                      drafts.removeAt(index).dispose();
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(controller: draft.name, decoration: InputDecoration(labelText: EkLanguage.text('Medicine name', 'ওষুধের নাম'))),
            const SizedBox(height: 10),
            TextField(controller: draft.dose, decoration: InputDecoration(labelText: EkLanguage.text('Dose as written', 'লেখা ডোজ'))),
            const SizedBox(height: 10),
            TextField(
              controller: draft.instruction,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: EkLanguage.text('Instruction as written', 'লেখা নির্দেশনা')),
            ),
            if (draft.hint.trim().isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                '${EkLanguage.text('OCR schedule hint', 'OCR সময়ের ইঙ্গিত')}: ${draft.hint}',
                style: const TextStyle(color: EkColors.orange, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text(EkLanguage.text('Confirmed reminder times', 'নিশ্চিত রিমাইন্ডারের সময়'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final time in draft.times)
                  InputChip(
                    label: Text(time),
                    onDeleted: () => setState(() => draft.times.remove(time)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_alarm, size: 18),
                  label: Text(EkLanguage.text('Add time', 'সময় যোগ করুন')),
                  onPressed: () => _addTime(draft),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneStep() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 72, color: EkColors.green),
            const SizedBox(height: 12),
            Text(EkLanguage.text('Saved', 'সংরক্ষিত'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    Widget item(int n, String en, String bn) {
      final active = n <= step;
      return Expanded(
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: active ? EkColors.purple : const Color(0xFFE8E9F0),
              child: Text('$n', style: TextStyle(fontSize: 11, color: active ? Colors.white : EkColors.muted)),
            ),
            const SizedBox(width: 5),
            Flexible(child: Text(EkLanguage.text(en, bn), style: TextStyle(fontSize: 11, color: active ? EkColors.purple : EkColors.muted))),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      color: Colors.white,
      child: Row(
        children: [
          item(1, 'Upload', 'আপলোড'),
          const Icon(Icons.chevron_right, size: 16, color: EkColors.line),
          item(2, 'Review', 'যাচাই'),
          const Icon(Icons.chevron_right, size: 16, color: EkColors.line),
          item(3, 'Save', 'সংরক্ষণ'),
        ],
      ),
    );
  }
}

class _MedicineDraft {
  _MedicineDraft({
    String name = '',
    String dose = '',
    String instruction = '',
    this.hint = '',
    this.source = '',
  })  : name = TextEditingController(text: name),
        dose = TextEditingController(text: dose),
        instruction = TextEditingController(text: instruction);

  final TextEditingController name;
  final TextEditingController dose;
  final TextEditingController instruction;
  final String hint;
  final String source;
  final List<String> times = [];

  void dispose() {
    name.dispose();
    dose.dispose();
    instruction.dispose();
  }
}
