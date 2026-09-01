import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'medicine_form_screen.dart';

import '../../core/page_route.dart';
class MedicineOcrScreen extends StatefulWidget {
  const MedicineOcrScreen({super.key});

  @override
  State<MedicineOcrScreen> createState() => _MedicineOcrScreenState();
}

class _MedicineOcrScreenState extends State<MedicineOcrScreen> {
  bool busy = false;
  String fileName = '';
  String rawText = '';
  String warning = '';
  String errorMessage = '';
  Uint8List? lastBytes;
  List<Map<String, dynamic>> medicines = const [];

  Future<void> pickFile() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (result == null) return;
    // file_picker v12 dropped `withData` and the `bytes` getter on web;
    // always read from the platform file path, which works on Android too.
    final bytes = await result.readAsBytes();
    await runOcr(bytes, result.name);
  }

  Future<void> takePhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null) return;
    await runOcr(await image.readAsBytes(), image.name);
  }

  Future<void> runOcr(Uint8List bytes, String name) async {
    setState(() {
      busy = true;
      fileName = name;
      lastBytes = bytes;
      errorMessage = '';
      medicines = const [];
      rawText = '';
      warning = '';
    });
    try {
      final result = await ApiService.prescriptionOcr(
        bytes: bytes,
        fileName: name,
      );
      final list = <Map<String, dynamic>>[];
      for (final item in (result['medicines'] as List?) ?? const []) {
        if (item is Map) {
          list.add(Map<String, dynamic>.from(item));
        }
      }
      if (!mounted) return;
      setState(() {
        rawText = result['rawText']?.toString() ?? '';
        warning = result['warning']?.toString() ?? '';
        medicines = list;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString().replaceFirst('Exception: ', '').trim();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> retryOcr() async {
    if (lastBytes == null || fileName.isEmpty) return;
    await runOcr(lastBytes!, fileName);
  }

  Future<void> openCandidate(Map<String, dynamic> candidate) async {
    final instruction = [
      candidate['dose']?.toString() ?? '',
      candidate['instruction']?.toString() ?? '',
      ...((candidate['scheduleHints'] as List?) ?? const []).map((e) => e.toString()),
    ].where((e) => e.trim().isNotEmpty).toSet().join(' • ');

    await Navigator.push(
      context,
      GochanoRoute.to(
        builder: (_) => MedicineFormScreen(
          initialData: {
            'name': candidate['name']?.toString() ?? '',
            'instruction': instruction,
          },
          ocrSourceText: candidate['sourceText']?.toString() ?? '',
          ocrSuggested: true,
        ),
      ),
    );
  }

  Future<void> showRawText() async {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(EkLanguage.text('Detected Text', 'শনাক্ত করা লেখা')),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              rawText.isEmpty
                  ? EkLanguage.text('No text detected.', 'কোনো লেখা শনাক্ত হয়নি।')
                  : rawText,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: Text(EkLanguage.text('Close', 'বন্ধ')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('Scan Prescription', 'প্রেসক্রিপশন স্ক্যান')),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: LanguageToggle(),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
          children: [
            Text(
              EkLanguage.text('Upload Prescription', 'প্রেসক্রিপশন আপলোড করুন'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              EkLanguage.text(
                'Upload a clear image or PDF. OCR only suggests visible text.',
                'পরিষ্কার ছবি বা PDF দিন। OCR শুধু দৃশ্যমান লেখার পরামর্শ দেয়।',
              ),
              style: const TextStyle(color: EkColors.muted),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF9FF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: EkColors.purple.withValues(alpha: .35),
                  width: 1.4,
                ),
              ),
              child: Column(
                children: [
                  const Text('📄', style: TextStyle(fontSize: 54)),
                  const SizedBox(height: 8),
                  Text(
                    fileName.isEmpty
                        ? EkLanguage.text(
                            'Tap to upload or take photo',
                            'আপলোড করুন অথবা ছবি তুলুন',
                          )
                        : fileName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'JPG, PNG, PDF • Max 10 MB',
                    style: TextStyle(fontSize: 11, color: EkColors.muted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : pickFile,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(EkLanguage.text('Gallery / PDF', 'গ্যালারি / PDF')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: busy ? null : takePhoto,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(EkLanguage.text('Camera', 'ক্যামেরা')),
                        ),
                      ),
                    ],
                  ),
if (busy) ...[
                    const SizedBox(height: 18),
                    const LinearProgressIndicator(
                      minHeight: 6,
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                EkColors.purple),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          EkLanguage.text(
                            'Reading prescription…',
                            'প্রেসক্রি�শন পড়া হচ্ছে…',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: EkColors.purple,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF2DEB8)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFFC27812)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      EkLanguage.text(
                        'OCR may be inaccurate. Verify medicine information before saving. Gochano does not provide medical advice.',
                        'OCR ভুল হতে পারে। সংরক্ষণের আগে ওষুধের তথ্য যাচাই করুন। Gochano চিকিৎসা পরামর্শ দেয় না।',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDEDEE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF3C7CA)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFD84A4A)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EkLanguage.text(
                              'Could not read the prescription.',
                              'প্রেসক্রিপশন পড়া যায়নি।',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB23B3B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            errorMessage,
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: busy ? null : pickFile,
                                icon: const Icon(Icons.photo_library_outlined, size: 18),
                                label: Text(
                                  EkLanguage.text('Choose another', 'অন্য ছবি বাছুন'),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: busy ? null : retryOcr,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(
                                  EkLanguage.text('Retry', 'আবার চেষ্টা করুন'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (rawText.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      EkLanguage.text('OCR Results', 'OCR ফলাফল'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: showRawText,
                    child: Text(EkLanguage.text('Show full text', 'সম্পূর্ণ লেখা')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (medicines.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text(
                          EkLanguage.text(
                            'No confident medicine line was detected. You can still use the OCR text as a draft and enter medicine details manually.',
                            'নিশ্চিত ওষুধের লাইন পাওয়া যায়নি। OCR লেখা দেখে ম্যানুয়ালি তথ্য লিখতে পারেন।',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => Navigator.push(
                            context,
                            GochanoRoute.to(
                              builder: (_) => MedicineFormScreen(
                                initialData: {'instruction': rawText},
                                ocrSourceText: rawText,
                                ocrSuggested: true,
                              ),
                            ),
                          ),
                          child: Text(EkLanguage.text('Review Manually', 'ম্যানুয়ালি যাচাই')),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final candidate in medicines)
                  _CandidateCard(
                    candidate: candidate,
                    onReview: () => openCandidate(candidate),
                  ),
              if (warning.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    warning,
                    style: const TextStyle(fontSize: 10, color: EkColors.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.onReview,
  });

  final Map<String, dynamic> candidate;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final name = candidate['name']?.toString() ?? '';
    final dose = candidate['dose']?.toString() ?? '';
    final instruction = candidate['instruction']?.toString() ?? '';
    final scheduleHints = ((candidate['scheduleHints'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final confidenceRaw = candidate['confidence'];
    final confidence = confidenceRaw is num
        ? confidenceRaw.toDouble()
        : double.tryParse(confidenceRaw?.toString() ?? '');

    final chips = <Widget>[];
    if (dose.isNotEmpty) {
      chips.add(_chip(Icons.science_outlined, dose, const Color(0xFFEDE6FB), EkColors.purple));
    }
    for (final hint in scheduleHints) {
      chips.add(_chip(Icons.schedule, hint, const Color(0xFFEAF3FF), const Color(0xFF3D7BFF)));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F9F3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('💊', style: TextStyle(fontSize: 25)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (instruction.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          instruction,
                          style: const TextStyle(
                            fontSize: 12,
                            color: EkColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (confidence != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _confidenceColor(confidence).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(confidence * 100).round()}%',
                      style: TextStyle(
                        color: _confidenceColor(confidence),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onReview,
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(EkLanguage.text('Review', 'যাচাই')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Color _confidenceColor(double value) {
    if (value >= 0.75) return EkColors.green;
    if (value >= 0.5) return const Color(0xFFE19B22);
    return const Color(0xFFD84A4A);
  }
}
