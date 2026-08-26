import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';
import 'medicine_form_screen.dart';

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
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openCandidate(Map<String, dynamic> candidate) async {
    final instruction = [
      candidate['dose']?.toString() ?? '',
      candidate['instruction']?.toString() ?? '',
      ...((candidate['scheduleHints'] as List?) ?? const []).map((e) => e.toString()),
    ].where((e) => e.trim().isNotEmpty).toSet().join(' • ');

    await Navigator.push(
      context,
      MaterialPageRoute(
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
      builder: (context, _, __) => Scaffold(
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
                    const LinearProgressIndicator(),
                    const SizedBox(height: 7),
                    Text(EkLanguage.text('Reading prescription…', 'প্রেসক্রিপশন পড়া হচ্ছে…')),
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
                            MaterialPageRoute(
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
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9F9F3),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text('💊', style: TextStyle(fontSize: 25)),
                      ),
                      title: Text(
                        candidate['name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          candidate['dose']?.toString() ?? '',
                          candidate['instruction']?.toString() ?? '',
                          ((candidate['scheduleHints'] as List?) ?? const []).join(' • '),
                        ].where((e) => e.trim().isNotEmpty).join('\n'),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () => openCandidate(candidate),
                        child: Text(EkLanguage.text('Review', 'যাচাই')),
                      ),
                    ),
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
