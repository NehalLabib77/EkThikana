// AI assistant (spec §34–§38).
//
// The distinction the spec cares about is General AI vs Material Context AI,
// so the screen makes it visible: when a material is in context there is a
// chip at the top saying "Using: Database_Normalization.pdf" with an X to
// remove it, and the suggested actions change to the ones that only make
// sense with a document (summarise, extract key points, explain this page).
//
// Which backend endpoint gets called follows from the context, not from a
// mode switch the student has to understand:
//
//   no context     → POST /api/ai/note            (general study question)
//   PDF context    → POST /api/ai/pdf-question    (text extract, OCR fallback)
//   image context  → POST /api/ai/image-question  (multimodal)
//
// The PDF path already handles scanned, image-only PDFs: the backend falls
// back to the shared OCR pipeline when digital text extraction yields almost
// nothing, so a photographed lecture handout still answers (spec §37).
//
// Nothing here animates. Processing is a static labelled progress bar with a
// sentence saying what is happening — no typing dots, no glowing orb
// (spec §35).
//
// ATTACHMENT SUPPORT:
// Users can now attach files (PDF, images, DOCX, TXT) to their questions.
// Attachments are uploaded to the backend, which extracts text and includes
// it in the AI prompt. Supported formats:
//   - PDF: text extraction via backend
//   - Images (JPG, JPEG, PNG, WEBP): OCR via backend
//   - DOCX: paragraph/table extraction via backend
//   - TXT: direct text inclusion
// Legacy .doc files are NOT supported (binary format unreliable for extraction).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'ai_context_routing.dart';

/// One exchange in the conversation.
class _Turn {
  const _Turn({
    required this.question,
    required this.answer,
    required this.usedMaterial,
    this.usedAttachment,
  });

  final String question;
  final String answer;
  final String? usedMaterial;
  final String? usedAttachment;
}

/// Represents an attached file pending upload.
class _Attachment {
  _Attachment({
    required this.file,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  final File file;
  final String name;
  final int size;
  final String? mimeType;

  /// Whether this attachment is currently being uploaded/processed.
  bool isUploading = false;

  /// Upload progress (0.0 to 1.0).
  double progress = 0.0;

  /// Error message if upload failed.
  String? error;

  /// Whether upload completed successfully.
  bool isComplete = false;

  /// The extracted text from the backend (if applicable).
  String? extractedText;
}

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({
    super.key,
    this.contextMaterialId,
    this.contextMaterialTitle,
    this.contextMimeType,
    this.contextFileName,
    this.contextPage,
  });

  /// When set, answers are grounded in this material.
  final String? contextMaterialId;
  final String? contextMaterialTitle;
  final String? contextMimeType;

  /// Original file name, used when [contextMimeType] is missing.
  final String? contextFileName;

  /// Current page, so "explain this page" can scope the question.
  final int? contextPage;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _question = TextEditingController();
  final _scroll = ScrollController();

  final List<_Turn> _turns = [];
  final List<_Attachment> _attachments = [];
  bool _busy = false;
  String _error = '';

  /// Null once the student removes the context (spec §34).
  String? _materialId;
  String? _materialTitle;
  String? _mimeType;
  String? _fileName;

  bool get _hasContext => _materialId != null;

  /// Which endpoint the current context routes to. Uses the MIME type and
  /// the file name together, so a material with a missing `mimeType` still
  /// reaches the right endpoint (see `ai_context_routing.dart`).
  AiContextRoute get _route => AiContextRouting.routeFor(
        mimeType: _mimeType,
        fileName: _fileName ?? _materialTitle,
      );

  /// Supported file extensions.
  static const Set<String> _supportedExtensions = {
    'pdf', 'jpg', 'jpeg', 'png', 'webp', 'docx', 'txt',
  };

  @override
  void initState() {
    super.initState();
    _materialId = widget.contextMaterialId;
    _materialTitle = widget.contextMaterialTitle;
    _mimeType = widget.contextMimeType;
    _fileName = widget.contextFileName;
  }

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The processing message, chosen to describe what is actually happening.
  String get _busyMessage {
    if (_attachments.isNotEmpty && _attachments.any((a) => a.isUploading)) {
      return GochanoLanguage.text('Processing attachment…', 'সংযুক্তি প্রক্রিয়াকরণ হচ্ছে…');
    }
    if (!_hasContext) {
      return GochanoLanguage.text('Preparing answer…', 'উত্তর তৈরি হচ্ছে…');
    }
    return GochanoLanguage.text(
      'Reading your material…',
      'আপনার উপকরণ পড়া হচ্ছে…',
    );
  }

  /// Pick files for attachment.
  Future<void> _pickAttachment() async {
    // Check connectivity
    if (!ConnectivityService.instance.online.value) {
      if (mounted) {
        setState(() {
          _error = GochanoLanguage.text(
            'This feature needs an internet connection.',
            'এই বৈশিষ্ট্যের জন্য ইন্টারনেট সংযোগ প্রয়োজন।',
          );
        });
      }
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedExtensions.toList(),
      );

      if (result.isEmpty) return;

      final file = result.first;
      if (file.path == null) return;

      // Validate file extension
      final ext = file.name.split('.').last.toLowerCase();
      if (!_supportedExtensions.contains(ext)) {
        if (mounted) {
          setState(() {
            _error = GochanoLanguage.text(
              'Unsupported file type. Please use PDF, JPG, PNG, WEBP, DOCX, or TXT.',
              'অসমর্থিত ফাইল ধরন। PDF, JPG, PNG, WEBP, DOCX, বা TXT ব্যবহার করুন।',
            );
          });
        }
        return;
      }

      // Check for duplicate
      if (_attachments.any((a) => a.name == file.name)) {
        if (mounted) {
          setState(() {
            _error = GochanoLanguage.text(
              'This file is already attached.',
              'এই ফাইলটি ইতিমধ্যে সংযুক্ত আছে।',
            );
          });
        }
        return;
      }

      // Determine MIME type
      String? mimeType;
      if (ext == 'pdf') {
        mimeType = 'application/pdf';
      } else if (ext == 'jpg' || ext == 'jpeg') {
        mimeType = 'image/jpeg';
      } else if (ext == 'png') {
        mimeType = 'image/png';
      } else if (ext == 'webp') {
        mimeType = 'image/webp';
      } else if (ext == 'docx') {
        mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      } else if (ext == 'txt') {
        mimeType = 'text/plain';
      }

      final attachment = _Attachment(
        file: File(file.path!),
        name: file.name,
        size: 0, // Size not available in file_picker v12
        mimeType: mimeType,
      );

      if (mounted) {
        setState(() {
          _attachments.add(attachment);
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = GochanoLanguage.text(
            'Could not pick file. Please try again.',
            'ফাইল নির্বাচন করা যায়নি। আবার চেষ্টা করুন।',
          );
        });
      }
    }
  }

  /// Remove an attachment.
  void _removeAttachment(int index) {
    if (mounted) {
      setState(() {
        _attachments.removeAt(index);
      });
    }
  }

  Future<void> _ask(String rawQuestion) async {
    final question = rawQuestion.trim();
    if (question.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = '';
    });

    try {
      final String answer;
      final materialId = _materialId;

      if (materialId == null && _attachments.isEmpty) {
        // General academic question
        answer = await ApiService.aiNote('explain', question);
      } else if (_attachments.isNotEmpty) {
        // Has attachments — upload and get answer
        answer = await _askWithAttachment(question);
      } else if (_route == AiContextRoute.imageQuestion) {
        answer = await ApiService.askImage(
          materialId: materialId!,
          question: question,
        );
      } else {
        answer = await ApiService.askPdf(
          materialId: materialId!,
          question: question,
          page: widget.contextPage,
        );
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _question.clear();
        _attachments.clear();
        _turns.add(
          _Turn(
            question: question,
            answer: answer.trim().isEmpty
                ? GochanoLanguage.text(
                    'The AI service returned an empty answer. Try rephrasing '
                    'your question.',
                    'এআই সার্ভিস কোনো উত্তর দেয়নি। প্রশ্নটি অন্যভাবে লিখে দেখুন।',
                  )
                : answer,
            usedMaterial: _materialTitle,
            usedAttachment: _attachments.isNotEmpty ? _attachments.first.name : null,
          ),
        );
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _aiErrorMessage(error);
      });
    }
  }

  /// Upload attachment and get AI answer.
  Future<String> _askWithAttachment(String question) async {
    if (_attachments.isEmpty) {
      throw Exception('No attachment to process');
    }

    final attachment = _attachments.first;
    attachment.isUploading = true;
    if (mounted) setState(() {});

    try {
      // Upload file to backend
      final result = await ApiService.uploadAiAttachment(
        file: attachment.file.path,
        fileName: attachment.name,
        mimeType: attachment.mimeType ?? 'application/octet-stream',
        question: question,
      );

      attachment.isUploading = false;
      attachment.isComplete = true;
      attachment.extractedText = result['extractedText'];
      if (mounted) setState(() {});

      return result['answer'] ?? '';
    } catch (e) {
      attachment.isUploading = false;
      attachment.error = e.toString();
      if (mounted) setState(() {});
      rethrow;
    }
  }

  /// Maps the AI-specific failures the backend can return onto sentences a
  /// student can act on (spec §38). Everything else goes through the shared
  /// mapper, which never leaks internals.
  String _aiErrorMessage(Object error) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('daily ai limit') || raw.contains('quota')) {
      return GochanoLanguage.text(
        'AI usage limit reached for today. Try again tomorrow.',
        'আজকের এআই ব্যবহারের সীমা শেষ। আগামীকাল আবার চেষ্টা করুন।',
      );
    }
    if (raw.contains('no extractable pdf text')) {
      return GochanoLanguage.text(
        'This appears to be a scanned PDF and OCR could not extract enough '
        'text to answer from.',
        'এটি সম্ভবত স্ক্যান করা পিডিএফ এবং ওসিআর যথেষ্ট লেখা বের করতে পারেনি।',
      );
    }
    if (raw.contains('not a pdf')) {
      return GochanoLanguage.text(
        'This material is not a PDF, so it cannot be read this way.',
        'এই উপকরণটি পিডিএফ নয়, তাই এভাবে পড়া যাবে না।',
      );
    }
    if (raw.contains('material') && raw.contains('not found')) {
      return GochanoLanguage.text(
        'The selected material is no longer available.',
        'নির্বাচিত উপকরণটি আর নেই।',
      );
    }
    if (raw.contains('unsupported') || raw.contains('not supported')) {
      return GochanoLanguage.text(
        'This file type is not supported. Please use PDF, JPG, PNG, WEBP, DOCX, or TXT.',
        'এই ফাইল ধরন সমর্থিত নয়। PDF, JPG, PNG, WEBP, DOCX, বা TXT ব্যবহার করুন।',
      );
    }
    if (raw.contains('.doc') && !raw.contains('.docx')) {
      return GochanoLanguage.text(
        'Legacy .doc files are not supported yet. Please use .docx.',
        'পুরাতন .doc ফাইল এখনো সমর্থিত নয়। .docx ব্যবহার করুন।',
      );
    }
    if (raw.contains('ai service configuration') ||
        raw.contains('model configuration') ||
        raw.contains('provider temporarily unavailable') ||
        raw.contains('returned no text')) {
      return GochanoLanguage.text(
        'Unable to connect to the AI service. Try again.',
        'এআই সার্ভিসে সংযোগ করা যায়নি। আবার চেষ্টা করুন।',
      );
    }
    return friendlyErrorMessage(error);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Study AI', 'স্টাডি এআই'),
        subtitle: _hasContext
            ? GochanoLanguage.text('Answering from your material', 'আপনার উপকরণ থেকে উত্তর')
            : GochanoLanguage.text('General academic questions', 'সাধারণ একাডেমিক প্রশ্ন'),
      ),
      bottomBar: _Composer(
        controller: _question,
        busy: _busy,
        onSubmit: _ask,
        onAttach: _pickAttachment,
        attachments: _attachments,
        onRemoveAttachment: _removeAttachment,
      ),
      body: Column(
        children: [
          if (_hasContext) _ContextChip(
            title: _materialTitle ?? '',
            onRemove: () => setState(() {
              _materialId = null;
              _materialTitle = null;
              _mimeType = null;
              _fileName = null;
            }),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                GochanoSpacing.md,
                GochanoSpacing.sm,
                GochanoSpacing.md,
                120,
              ),
              children: [
                if (_turns.isEmpty && !_busy && _error.isEmpty)
                  _Suggestions(
                    hasContext: _hasContext,
                    hasPage: widget.contextPage != null,
                    onPick: _ask,
                  ),
                for (final turn in _turns) _TurnCard(turn: turn),
                if (_busy) ...[
                  const SizedBox(height: GochanoSpacing.lg),
                  StaticLoadingState(message: _busyMessage),
                ],
                if (_error.isNotEmpty) ...[
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
                            _error,
                            style: context.type.bodySecondary
                                .copyWith(color: colors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Using: `<material>`" with a remove control (spec §34).
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.title, required this.onRemove});

  final String title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        GochanoSpacing.md,
        GochanoSpacing.xs,
        GochanoSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.sm,
        vertical: GochanoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.ai.withValues(alpha: context.isDark ? 0.18 : 0.10),
        borderRadius: GochanoRadius.mdAll,
      ),
      child: Row(
        children: [
          GochanoIllustration(
            GochanoArt.featureAi,
            size: 22,
            accent: colors.ai,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  GochanoLanguage.text('Using', 'ব্যবহার করছে'),
                  style: context.type.caption,
                ),
                Text(
                  title,
                  style: context.type.cardHeading.copyWith(color: colors.ai),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconActionButton(
            icon: Icons.close_rounded,
            label: GochanoLanguage.text(
              'Ask without this material',
              'এই উপকরণ ছাড়া জিজ্ঞাসা',
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// The contextual actions from spec §34.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.hasContext,
    required this.hasPage,
    required this.onPick,
  });

  final bool hasContext;
  final bool hasPage;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final suggestions = hasContext
        ? [
            GochanoLanguage.text(
              'Summarise this material',
              'এই উপকরণের সারাংশ দাও',
            ),
            GochanoLanguage.text(
              'Extract the key points',
              'মূল পয়েন্টগুলো বের করো',
            ),
            GochanoLanguage.text(
              'Explain this simply',
              'সহজ করে ব্যাখ্যা করো',
            ),
            if (hasPage)
              GochanoLanguage.text(
                'Explain what is on this page',
                'এই পৃষ্ঠায় যা আছে ব্যাখ্যা করো',
              ),
          ]
        : [
            GochanoLanguage.text(
              'Explain database normalization',
              'ডাটাবেজ নরমালাইজেশন ব্যাখ্যা করো',
            ),
            GochanoLanguage.text(
              'What is the difference between TCP and UDP?',
              'টিসিপি ও ইউডিপির পার্থক্য কী?',
            ),
            GochanoLanguage.text(
              'Help me understand recursion',
              'রিকার্শন বুঝতে সাহায্য করো',
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: GochanoSpacing.lg),
        Center(
          child: GochanoIllustration(
            GochanoArt.featureAi,
            size: 88,
            accent: colors.ai,
          ),
        ),
        const SizedBox(height: GochanoSpacing.md),
        Text(
          hasContext
              ? GochanoLanguage.text(
                  'Ask about this material',
                  'এই উপকরণ নিয়ে জিজ্ঞাসা করুন',
                )
              : GochanoLanguage.text(
                  'Ask an academic question',
                  'একটি একাডেমিক প্রশ্ন করুন',
                ),
          style: context.type.sectionHeading,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Text(
          hasContext
              ? GochanoLanguage.text(
                  'Answers come from the text of your document.',
                  'উত্তর আসবে আপনার ডকুমেন্টের লেখা থেকে।',
                )
              : GochanoLanguage.text(
                  'Open a material first to ask about its content.',
                  'কোনো উপকরণের বিষয়বস্তু নিয়ে জানতে আগে সেটি খুলুন।',
                ),
          style: context.type.bodySecondary,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GochanoSpacing.lg),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
            child: AppCard(
              onTap: () => onPick(suggestion),
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.md,
                vertical: GochanoSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(suggestion, style: context.type.body),
                  ),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: GochanoSizes.iconSm,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TurnCard extends StatelessWidget {
  const _TurnCard({required this.turn});

  final _Turn turn;

  /// Strips common Markdown control characters while preserving code blocks.
  static String _stripMarkdown(String text) {
    var result = text;
    // Remove fenced code blocks (```...```) — keep content
    result = result.replaceAllMapped(
      RegExp(r'```[\s\S]*?```', multiLine: true),
      (m) => m.group(0)!.replaceFirst(RegExp(r'^```\w*\n?'), '').replaceFirst(RegExp(r'\n?```$'), ''),
    );
    // Remove inline code backticks
    result = result.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (m) => m.group(1)!,
    );
    // Remove heading markers (### Heading)
    result = result.replaceAllMapped(
      RegExp(r'^#{1,6}\s+', multiLine: true),
      (m) => '',
    );
    // Remove bold/italic markers
    result = result.replaceAll(RegExp(r'\*\*\*'), '');
    result = result.replaceAll(RegExp(r'___'), '');
    result = result.replaceAll(RegExp(r'\*\*'), '');
    result = result.replaceAll(RegExp(r'__'), '');
    result = result.replaceAll(RegExp(r'(?<!\w)\*(?!\*)'), '');
    result = result.replaceAll(RegExp(r'(?<!\w)_(?!_)'), '');
    // Remove blockquote markers
    result = result.replaceAllMapped(
      RegExp(r'^>\s+', multiLine: true),
      (m) => '',
    );
    // Remove horizontal rules
    result = result.replaceAll(RegExp(r'^-{3,}$', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^\*{3,}$', multiLine: true), '');
    // Remove link syntax [text](url) → text
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1)!,
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The question, right-aligned and tinted so the thread reads as a
          // conversation without needing chat bubbles.
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.sm,
                vertical: GochanoSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.brandSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Text(turn.question, style: context.type.body),
            ),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          AppCard(
            padding: const EdgeInsets.all(GochanoSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (turn.usedMaterial != null) ...[
                  Row(
                    children: [
                      GochanoIllustration(
                        GochanoArt.featureAi,
                        size: 16,
                        accent: colors.ai,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          GochanoLanguage.text(
                            'From ${turn.usedMaterial}',
                            '${turn.usedMaterial} থেকে',
                          ),
                          style: context.type.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                ],
                SelectableText(
                  _stripMarkdown(turn.answer),
                  style: context.type.body,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: turn.answer));
                      showGochanoMessage(
                        context,
                        GochanoLanguage.text('Copied', 'কপি হয়েছে'),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          GochanoLanguage.text('Copy', 'কপি'),
                          style: context.type.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSubmit,
    required this.onAttach,
    required this.attachments,
    required this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSubmit;
  final VoidCallback onAttach;
  final List<_Attachment> attachments;
  final void Function(int index) onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        GochanoSpacing.md,
        GochanoSpacing.xs,
        GochanoSpacing.md,
        GochanoSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Attachment chips
            if (attachments.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachments.length,
                  separatorBuilder: (ctx, idx) => const SizedBox(width: GochanoSpacing.xs),
                  itemBuilder: (context, index) {
                    final att = attachments[index];
                    return _AttachmentChip(
                      attachment: att,
                      onRemove: () => onRemoveAttachment(index),
                    );
                  },
                ),
              ),
            if (attachments.isNotEmpty)
              const SizedBox(height: GochanoSpacing.xs),
            // Composer row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment button
                IconButton(
                  onPressed: busy ? null : onAttach,
                  icon: Icon(
                    Icons.attach_file_rounded,
                    color: busy ? colors.disabled : colors.textSecondary,
                    size: 22,
                  ),
                  tooltip: GochanoLanguage.text(
                    'Attach file',
                    'ফাইল সংযুক্ত করুন',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: GochanoLanguage.text(
                        'Ask something…',
                        'কিছু জিজ্ঞাসা করুন…',
                      ),
                      isDense: true,
                    ),
                    onSubmitted: onSubmit,
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                FilledButton(
                  onPressed: busy ? null : () => onSubmit(controller.text),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(
                      GochanoSizes.buttonHeight,
                      GochanoSizes.buttonHeight,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: Icon(
                    busy ? Icons.hourglass_empty_rounded : Icons.send_rounded,
                    size: GochanoSizes.iconMd,
                    semanticLabel: GochanoLanguage.text('Send', 'পাঠান'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact chip showing an attached file with remove button.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final _Attachment attachment;
  final VoidCallback onRemove;

  IconData _fileIcon() {
    final name = attachment.name.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (name.endsWith('.jpg') || name.endsWith('.jpeg') ||
        name.endsWith('.png') || name.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    if (name.endsWith('.docx')) return Icons.description_rounded;
    if (name.endsWith('.txt')) return Icons.text_snippet_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _fileColor(BuildContext context) {
    final name = attachment.name.toLowerCase();
    if (name.endsWith('.pdf')) return context.colors.error;
    if (name.endsWith('.jpg') || name.endsWith('.jpeg') ||
        name.endsWith('.png') || name.endsWith('.webp')) {
      return context.colors.study;
    }
    if (name.endsWith('.docx')) return context.colors.brand;
    return context.colors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.sm,
        vertical: GochanoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.smAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _fileIcon(),
            size: 16,
            color: _fileColor(context),
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          Flexible(
            child: Text(
              attachment.name,
              style: context.type.caption.copyWith(
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (attachment.isUploading) ...[
            const SizedBox(width: GochanoSpacing.xs),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
              ),
            ),
          ] else if (attachment.error != null) ...[
            const SizedBox(width: GochanoSpacing.xs),
            Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: colors.error,
            ),
          ],
          const SizedBox(width: GochanoSpacing.xxs),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
