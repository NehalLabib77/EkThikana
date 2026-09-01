// Prescription scanning (spec §54–§58).
//
// What this screen actually is
// ----------------------------
// The backend runs **Tesseract OCR** over an uploaded image or PDF, with
// Pillow preprocessing (upscale, grayscale, autocontrast, sharpen) and
// pdf2image page rendering when a PDF has no extractable text layer. A
// regex/keyword parser then picks out lines that look like a medicine, a
// dose, a frequency shorthand or a meal instruction.
//
// There is **no custom machine-learning model** behind this feature, and no
// Gemini call in this path. The UI therefore says "read from your
// prescription", never "AI detected", and shows no confidence percentage —
// spec §54 is explicit that confidence must not be fabricated, and a
// rule-based parser has no calibrated confidence to report.
//
// The flow is suggestion → review → student confirmation → save. Nothing on
// this screen writes a medicine, a dose, a schedule or a reminder (spec §57).

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'medicine_form_screen.dart';

class PrescriptionScanScreen extends StatefulWidget {
  const PrescriptionScanScreen({super.key});

  @override
  State<PrescriptionScanScreen> createState() => _PrescriptionScanScreenState();
}

class _PrescriptionScanScreenState extends State<PrescriptionScanScreen> {
  bool _busy = false;
  String _fileName = '';
  String _rawText = '';
  String _warning = '';

  /// How well the page was actually read, straight from Tesseract's own
  /// per-word confidence. Empty until a scan has run.
  Map<String, dynamic> _quality = const {};

  /// What the server's recogniser can do — notably whether Bengali is
  /// installed, because without it Bengali instructions are missed.
  Map<String, dynamic> _engine = const {};
  String _error = '';
  Uint8List? _lastBytes;
  List<Map<String, dynamic>> _candidates = const [];

  bool get _hasResult => _rawText.isNotEmpty || _candidates.isNotEmpty;

  Future<void> _pickFile() async {
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (selected == null) return;
      // file_picker v12 dropped the `bytes` getter; read from the platform
      // file, which is the path that works on Android.
      await _runOcr(await selected.readAsBytes(), selected.name);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _takePhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        // A prescription is small print. Keep resolution high enough for
        // OCR while staying under the backend's 10 MB cap.
        imageQuality: 92,
        maxWidth: 2400,
      );
      if (image == null) return;
      await _runOcr(await image.readAsBytes(), image.name);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _runOcr(Uint8List bytes, String name) async {
    setState(() {
      _busy = true;
      _fileName = name;
      _lastBytes = bytes;
      _error = '';
      _rawText = '';
      _warning = '';
      _quality = const {};
      _engine = const {};
      _candidates = const [];
    });

    try {
      final result = await ApiService.prescriptionOcr(
        bytes: bytes,
        fileName: name,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _rawText = result['rawText']?.toString() ?? '';
        _warning = result['warning']?.toString() ?? '';
        _quality = (result['quality'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v)) ??
            const {};
        _engine = (result['engine'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v)) ??
            const {};
        _candidates = ((result['medicines'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(
          error,
          fallback: GochanoLanguage.text(
            'Could not read this prescription. Try a clearer, well-lit photo.',
            'এই প্রেসক্রিপশনটি পড়া যায়নি। আরও পরিষ্কার, ভালো আলোয় তোলা ছবি চেষ্টা করুন।',
          ),
        );
      });
    }
  }

  void _retry() {
    final bytes = _lastBytes;
    if (bytes == null || _fileName.isEmpty) return;
    _runOcr(bytes, _fileName);
  }

  /// Opens the medicine form with the read values pre-filled.
  ///
  /// Reminder times are deliberately **not** pre-filled, even when the
  /// prescription contained a frequency shorthand like "1+0+1": that is a
  /// medical instruction the student must turn into actual clock times
  /// themselves (spec §57). Any shorthand found is passed through as text in
  /// the instruction field so they can see it while choosing.
  Future<void> _review(Map<String, dynamic> candidate, {String? useName}) async {
    final instruction = <String>{
      candidate['dose']?.toString() ?? '',
      candidate['instruction']?.toString() ?? '',
      ...((candidate['scheduleHints'] as List?) ?? const [])
          .map((e) => e.toString()),
    }.where((e) => e.trim().isNotEmpty).join(' • ');

    await Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => MedicineFormScreen(
          initialData: {
            // Whatever is used here was either read from the page or
            // explicitly chosen by the reader. Nothing is substituted for
            // them.
            'name': useName ?? candidate['name']?.toString() ?? '',
            'instruction': instruction,
          },
          ocrSourceText: candidate['sourceText']?.toString() ?? '',
          ocrSuggested: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Scan prescription', 'প্রেসক্রিপশন স্ক্যান'),
        subtitle: GochanoLanguage.text(
          'Read the text, then confirm each medicine',
          'লেখা পড়ুন, তারপর প্রতিটি ওষুধ নিশ্চিত করুন',
        ),
      ),
      body: _busy ? _buildBusy(context) : _buildBody(context),
    );
  }

  Widget _buildBusy(BuildContext context) {
    return StaticLoadingState(
      message: GochanoLanguage.text(
        'Reading your prescription…',
        'আপনার প্রেসক্রিপশন পড়া হচ্ছে…',
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.colors;

    if (_error.isNotEmpty) {
      return ErrorState(
        message: _error,
        title: GochanoLanguage.text(
          'Could not read this prescription',
          'প্রেসক্রিপশনটি পড়া যায়নি',
        ),
        onRetry: _lastBytes == null ? null : _retry,
      );
    }

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        if (!_hasResult) ...[
          Center(
            child: GochanoIllustration(
              GochanoArt.featurePrescription,
              size: 96,
              accent: colors.medicine,
            ),
          ),
          const SizedBox(height: GochanoSpacing.md),
          Text(
            GochanoLanguage.text(
              'Photograph or upload your prescription and Gochano will read the '
              'printed text from it.',
              'আপনার প্রেসক্রিপশনের ছবি তুলুন বা আপলোড করুন, গোছানো এর লেখা পড়ে নেবে।',
            ),
            style: context.type.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.lg),
        ],

        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: GochanoLanguage.text('Take photo', 'ছবি তুলুন'),
                icon: Icons.photo_camera_outlined,
                onPressed: _takePhoto,
              ),
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(
              child: SecondaryButton(
                label: GochanoLanguage.text('Upload file', 'ফাইল আপলোড'),
                icon: Icons.upload_file_outlined,
                onPressed: _pickFile,
              ),
            ),
          ],
        ),

        const SizedBox(height: GochanoSpacing.md),
        const _HowThisWorksNotice(),

        if (_hasResult) ...[
          const SizedBox(height: GochanoSpacing.md),
          _ReadQuality(quality: _quality, engine: _engine),

          SectionHeader(
            title: GochanoLanguage.text(
              'Possible medicines',
              'সম্ভাব্য ওষুধ',
            ),
            subtitle: GochanoLanguage.text(
              'Tap one to check it and set your own reminder times.',
              'যাচাই করতে ও নিজের রিমাইন্ডার সময় দিতে যেকোনো একটিতে চাপ দিন।',
            ),
          ),
          if (_candidates.isEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    GochanoLanguage.text(
                      'No medicine lines were recognised',
                      'কোনো ওষুধের লাইন শনাক্ত হয়নি',
                    ),
                    style: context.type.cardHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.xxs),
                  Text(
                    GochanoLanguage.text(
                      'The text below is what was read. You can still add the '
                      'medicine yourself.',
                      'নিচে যা পড়া গেছে তা দেখানো হলো। আপনি চাইলে নিজেই ওষুধ যোগ করতে পারেন।',
                    ),
                    style: context.type.bodySecondary,
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  SecondaryButton(
                    label: GochanoLanguage.text(
                      'Add medicine manually',
                      'নিজে ওষুধ যোগ করুন',
                    ),
                    onPressed: () => Navigator.of(context).push(
                      GochanoRoute.to(
                        builder: (_) => MedicineFormScreen(
                          initialData: {'instruction': ''},
                          ocrSourceText: _rawText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            CardGroup(
              children: [
                for (final candidate in _candidates)
                  _CandidateRow(
                    candidate: candidate,
                    onReview: () => _review(candidate),
                    onUseSuggestion: (name) =>
                        _review(candidate, useName: name),
                  ),
              ],
            ),

          if (_rawText.isNotEmpty) ...[
            SectionHeader(
              title: GochanoLanguage.text('Text that was read', 'যা পড়া হয়েছে'),
              subtitle: GochanoLanguage.text(
                'Shown in full so you can see exactly what OCR produced.',
                'ওসিআর ঠিক কী পড়েছে তা দেখতে পুরোটা দেখানো হলো।',
              ),
            ),
            AppCard(
              child: SelectableText(
                _rawText,
                style: context.type.bodySecondary,
              ),
            ),
          ],

          if (_warning.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.warningSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: GochanoSizes.iconSm,
                    color: colors.warning,
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      _warning,
                      style: context.type.bodySecondary
                          .copyWith(color: colors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// States plainly what the feature is, so nothing here reads as a claim the
/// implementation cannot support (spec §55, §100).
class _HowThisWorksNotice extends StatelessWidget {
  const _HowThisWorksNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: GochanoSizes.iconSm,
            color: colors.textSecondary,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Text(
              GochanoLanguage.text(
                'Gochano reads printed text with OCR and looks for lines that '
                'resemble a medicine. It can be wrong, and it never decides '
                'your dose or schedule — you confirm every medicine before it '
                'is saved.',
                'গোছানো ওসিআর দিয়ে ছাপা লেখা পড়ে এবং ওষুধের মতো দেখতে লাইন খোঁজে। এটি ভুল হতে পারে, এবং এটি কখনো আপনার ডোজ বা সময়সূচি ঠিক করে না — সংরক্ষণের আগে আপনি প্রতিটি ওষুধ নিশ্চিত করবেন।',
              ),
              style: context.type.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.onReview,
    required this.onUseSuggestion,
  });

  final Map<String, dynamic> candidate;
  final VoidCallback onReview;

  /// Opens the review form with the suggested spelling instead of the one
  /// that was read. Only ever runs because the reader tapped it.
  final ValueChanged<String> onUseSuggestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = candidate['name']?.toString() ?? '';
    final dose = candidate['dose']?.toString() ?? '';
    final hints = ((candidate['scheduleHints'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final explicitTimes = ((candidate['explicitTimes'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();

    final band = (candidate['nameConfidence'] as Map?)?['band']?.toString();
    final suggestion = (candidate['suggestion'] as Map?)
        ?.map((k, v) => MapEntry(k.toString(), v));
    final knownGeneric = candidate['recognisedAsKnownGeneric'] == true;

    return AppCard(
      onTap: onReview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureMedicine,
                accent: colors.medicine,
                plateSize: 40,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Always the text that was actually read. A silently
                    // corrected medicine name is the one mistake this screen
                    // must never make.
                    Text(
                      name.isEmpty
                          ? GochanoLanguage.text('Unnamed line', 'নামহীন লাইন')
                          : name,
                      style: context.type.cardHeading,
                    ),
                    if (dose.isNotEmpty)
                      Text(dose, style: context.type.bodySecondary),
                  ],
                ),
              ),
              TextButton(
                onPressed: onReview,
                child: Text(GochanoLanguage.text('Review', 'যাচাই')),
              ),
            ],
          ),

          if (hints.isNotEmpty || explicitTimes.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xxs),
            Text(
              // Explicit clock values are shown as read and are still not
              // pre-filled as reminders — the student sets those.
              [...hints, ...explicitTimes].join(' · '),
              style: context.type.caption,
            ),
          ],

          const SizedBox(height: GochanoSpacing.xs),
          Wrap(
            spacing: GochanoSpacing.xxs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              if (band != null) _ConfidenceBadge(band: band),
              if (knownGeneric)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Known generic name',
                    'পরিচিত জেনেরিক নাম',
                  ),
                  tone: GochanoBadgeTone.info,
                ),
            ],
          ),

          // A question, never a correction. Tapping is the only thing that
          // changes the name, and the reader does the tapping.
          if (suggestion != null) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    GochanoLanguage.text(
                      'Did you mean "${suggestion['suggested']}"?',
                      '"${suggestion['suggested']}" বোঝাতে চেয়েছেন?',
                    ),
                    style: context.type.body,
                  ),
                  Text(
                    GochanoLanguage.text(
                      'Only you can decide. Check the prescription itself '
                      'before changing a medicine name.',
                      'সিদ্ধান্ত শুধু আপনার। ওষুধের নাম বদলানোর আগে '
                      'প্রেসক্রিপশনটি নিজে দেখে নিন।',
                    ),
                    style: context.type.caption,
                  ),
                  const SizedBox(height: GochanoSpacing.xxs),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => onUseSuggestion(
                          suggestion['suggested'].toString(),
                        ),
                        child: Text(
                          GochanoLanguage.text(
                            'Use this spelling',
                            'এই বানানটি ব্যবহার করুন',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onReview,
                        child: Text(
                          GochanoLanguage.text(
                            'Keep as read',
                            'যেমন পড়া হয়েছে রাখুন',
                          ),
                        ),
                      ),
                    ],
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

/// How confidently *this name* was read, from Tesseract's own per-word
/// confidence.
///
/// Deliberately a phrase rather than a percentage: the underlying score is an
/// ordering, not a calibrated probability, and "87%" on a misread medicine
/// name would imply a precision it does not have.
class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.band});

  final String band;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (band) {
      'high' => (
          GochanoLanguage.text('Read clearly', 'স্পষ্ট পড়া গেছে'),
          GochanoBadgeTone.success,
        ),
      'medium' => (
          GochanoLanguage.text('Check this one', 'এটি যাচাই করুন'),
          GochanoBadgeTone.warning,
        ),
      'low' => (
          GochanoLanguage.text('Hard to read', 'পড়তে কষ্ট হয়েছে'),
          GochanoBadgeTone.error,
        ),
      _ => (
          GochanoLanguage.text('Not measured', 'মাপা হয়নি'),
          GochanoBadgeTone.neutral,
        ),
    };
    return GochanoBadge(label: label, tone: tone);
  }
}

/// How well the whole page was read, and what the engine could actually do.
///
/// Shown above the medicine list because it changes how much of that list to
/// trust. A page read badly is not a page with fewer medicines on it.
class _ReadQuality extends StatelessWidget {
  const _ReadQuality({required this.quality, required this.engine});

  final Map<String, dynamic> quality;
  final Map<String, dynamic> engine;

  @override
  Widget build(BuildContext context) {
    if (quality.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final band = quality['band']?.toString() ?? 'unknown';
    final fromPdfText = quality['source']?.toString() == 'pdf_text';
    final bengaliMissing =
        engine.isNotEmpty && engine['bengaliSupported'] != true;

    final (message, tone) = fromPdfText
        ? (
            GochanoLanguage.text(
              'Read from the text inside the PDF, so the words below are '
              'exact.',
              'পিডিএফের ভেতরের লেখা থেকে পড়া, তাই নিচের শব্দগুলো হুবহু।',
            ),
            GochanoBadgeTone.success,
          )
        : switch (band) {
            'high' => (
                GochanoLanguage.text(
                  'This page was read clearly. Still check each medicine '
                  'against the prescription.',
                  'পাতাটি স্পষ্ট পড়া গেছে। তবুও প্রতিটি ওষুধ প্রেসক্রিপশনের '
                  'সঙ্গে মিলিয়ে নিন।',
                ),
                GochanoBadgeTone.success,
              ),
            'medium' => (
                GochanoLanguage.text(
                  'Parts of this page were hard to read. Check every medicine '
                  'and dose carefully.',
                  'পাতার কিছু অংশ পড়তে কষ্ট হয়েছে। প্রতিটি ওষুধ ও ডোজ ভালো করে '
                  'যাচাই করুন।',
                ),
                GochanoBadgeTone.warning,
              ),
            'low' => (
                GochanoLanguage.text(
                  'This page was hard to read, so medicines may be wrong or '
                  'missing. A clearer, well-lit photo usually helps.',
                  'পাতাটি পড়তে কষ্ট হয়েছে, তাই ওষুধ ভুল বা বাদ পড়তে পারে। আরও '
                  'পরিষ্কার, ভালো আলোয় তোলা ছবি সাধারণত কাজে দেয়।',
                ),
                GochanoBadgeTone.error,
              ),
            _ => (
                GochanoLanguage.text(
                  'How clearly this page was read could not be measured.',
                  'পাতাটি কতটা স্পষ্ট পড়া গেছে তা মাপা যায়নি।',
                ),
                GochanoBadgeTone.neutral,
              ),
          };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                GochanoLanguage.text('Read quality', 'পড়ার মান'),
                style: context.type.label,
              ),
              const SizedBox(width: GochanoSpacing.xxs),
              GochanoBadge(label: _bandLabel(band, fromPdfText), tone: tone),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(message, style: context.type.bodySecondary),

          // Without the Bengali pack, Bengali instructions are not misread —
          // they are simply not read at all. Saying so beats dropping them
          // silently.
          if (bengaliMissing) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.translate_rounded,
                  size: GochanoSizes.iconSm,
                  color: colors.warning,
                ),
                const SizedBox(width: GochanoSpacing.xxs),
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'Bengali text recognition is unavailable on the server, '
                      'so Bengali instructions were not read.',
                      'সার্ভারে বাংলা লেখা শনাক্তকরণ নেই, তাই বাংলায় লেখা '
                      'নির্দেশনা পড়া হয়নি।',
                    ),
                    style: context.type.caption.copyWith(color: colors.warning),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _bandLabel(String band, bool fromPdfText) {
    if (fromPdfText) return GochanoLanguage.text('Exact text', 'হুবহু লেখা');
    return switch (band) {
      'high' => GochanoLanguage.text('Clear', 'স্পষ্ট'),
      'medium' => GochanoLanguage.text('Mixed', 'মিশ্র'),
      'low' => GochanoLanguage.text('Poor', 'দুর্বল'),
      _ => GochanoLanguage.text('Unknown', 'অজানা'),
    };
  }
}
