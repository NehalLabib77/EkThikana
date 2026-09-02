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

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
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
  });

  final String question;
  final String answer;
  final String? usedMaterial;
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
    if (!_hasContext) {
      return GochanoLanguage.text('Preparing answer…', 'উত্তর তৈরি হচ্ছে…');
    }
    return GochanoLanguage.text(
      'Reading your material…',
      'আপনার উপকরণ পড়া হচ্ছে…',
    );
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

      if (materialId == null) {
        // General academic question. `explain` is the instruction that maps
        // to "answer this for a university student" on the backend.
        answer = await ApiService.aiNote('explain', question);
      } else if (_route == AiContextRoute.imageQuestion) {
        answer = await ApiService.askImage(
          materialId: materialId,
          question: question,
        );
      } else {
        answer = await ApiService.askPdf(
          materialId: materialId,
          question: question,
          page: widget.contextPage,
        );
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _question.clear();
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
      // Jump, not animate: this is a state change, not a decoration
      // (spec §11).
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
                SelectableText(turn.answer, style: context.type.body),
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
  });

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
                'Ask a question…',
                'একটি প্রশ্ন করুন…',
              ),
              isDense: true,
            ),
            onSubmitted: onSubmit,
          ),
        ),
        const SizedBox(width: GochanoSpacing.xs),
        // Disabled while a request is in flight, which is what prevents a
        // double submit burning two AI quota units (spec §12, §77).
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
    );
  }
}
