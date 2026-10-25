import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'content_api_service.dart';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({
    super.key,
    this.initialTopic,
    this.initialSource,
    this.initialRequest,
    this.cardGenerator,
  });

  final String? initialTopic;
  final String? initialSource;
  final Future<Map<String, dynamic>>? initialRequest;
  final Future<Map<String, dynamic>> Function({
    required String topic,
    String sourceText,
  })? cardGenerator;

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  late final TextEditingController _topic;
  late final TextEditingController _source;
  Future<Map<String, dynamic>>? _request;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _topic = TextEditingController(text: widget.initialTopic ?? '');
    _source = TextEditingController(text: widget.initialSource ?? '');
    _request = widget.initialRequest;
  }

  @override
  void dispose() {
    _topic.dispose();
    _source.dispose();
    super.dispose();
  }

  void _generate() {
    final isBengali = GochanoLanguage.isBangla ||
        Localizations.maybeLocaleOf(context)?.languageCode == 'bn';
    final topic = _topic.text.trim();
    if (topic.isEmpty) {
      setState(() {
        _validationError = isBengali
            ? 'অনুগ্রহ করে একটি টপিক লিখুন'
            : 'Please enter a topic';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBengali ? 'অনুগ্রহ করে একটি টপিক লিখুন' : 'Please enter a topic',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _validationError = null;
      _request = widget.cardGenerator != null
          ? widget.cardGenerator!(
              topic: topic,
              sourceText: _source.text.trim(),
            )
          : ContentApiService.flashcards(
              topic: topic,
              sourceText: _source.text.trim(),
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBengali = GochanoLanguage.isBangla ||
        Localizations.maybeLocaleOf(context)?.languageCode == 'bn';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: GochanoAppBar(
        title: isBengali ? 'ফ্ল্যাশকার্ড' : 'Flashcards',
        subtitle: isBengali
            ? 'স্মার্ট এআই ফ্ল্যাশকার্ড তৈরি ও অনুশীলন'
            : 'AI-powered concept cards & recall',
      ),
      body: AppPageBackground(
        height: 240,
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.brand.withValues(alpha: 0.12),
                  colors.background,
                ],
              )
            : AppGradients.toolFlashcards,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: GochanoRadius.lgAll,
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: colors.brand.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.brandSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.style_rounded,
                          size: 20,
                          color: colors.brand,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isBengali
                                  ? 'স্মার্ট ফ্ল্যাশকার্ড তৈরি করুন'
                                  : 'Generate Smart Flashcards',
                              style: type.cardHeading.copyWith(fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isBengali
                                  ? 'টপিক বা নোট পেস্ট করে কার্ড বানান'
                                  : 'Create recall cards from any topic or notes',
                              style: type.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_validationError != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.1),
                        borderRadius: GochanoRadius.smAll,
                        border: Border.all(
                          color: colors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: colors.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _validationError!,
                              style: type.caption.copyWith(
                                color: colors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _topic,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (_validationError != null) {
                        setState(() => _validationError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: isBengali ? 'টপিক বা কনসেপ্ট' : 'Topic or Concept',
                      hintText: isBengali
                          ? 'যেমন: মাইটোসিস, নিউটনের গতিসূত্র'
                          : 'e.g. Mitosis, Newton\'s Laws, Macroeconomics',
                      filled: true,
                      fillColor: colors.surfaceVariant.withValues(alpha: 0.45),
                      border: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.brand, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _source,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: isBengali
                          ? 'নোট বা পাঠ্যবইয়ের অংশ (ঐচ্ছিক)'
                          : 'Notes or Textbook excerpt (optional)',
                      hintText: isBengali
                          ? 'লেকচার নোট বা অনুচ্ছেদ পেস্ট করুন...'
                          : 'Paste lecture notes or paragraphs to extract cards from...',
                      filled: true,
                      fillColor: colors.surfaceVariant.withValues(alpha: 0.45),
                      border: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.brand, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.brand,
                        shape: RoundedRectangleBorder(
                          borderRadius: GochanoRadius.mdAll,
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(
                        isBengali ? 'কার্ড তৈরি করুন' : 'Generate Cards',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      onPressed: _generate,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_request != null)
              FutureBuilder<Map<String, dynamic>>(
                future: _request,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 36,
                        horizontal: 16,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.brand,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              isBengali
                                  ? 'জিকু এআই আপনার ফ্ল্যাশকার্ড তৈরি করছে…'
                                  : 'Crafting your flashcards with Ziku AI…',
                              style: type.bodySecondary.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: GochanoRadius.lgAll,
                        border: Border.all(
                          color: colors.error.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: colors.error,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              snapshot.error.toString(),
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final cards =
                      (snapshot.data?['generatedContent'] as Map?)?['flashcards']
                          as List? ??
                      (snapshot.data?['flashcards'] as List?) ??
                      const [];

                  if (cards.isEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: GochanoRadius.lgAll,
                        border: Border.all(color: colors.border),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.style_outlined,
                              size: 36,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isBengali
                                  ? 'কোনো ফ্ল্যাশকার্ড তৈরি করা যায়নি। অন্য কোনো টপিক চেষ্টা করুন।'
                                  : 'No flashcards generated. Try another topic.',
                              style: type.bodySecondary,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final cardCountText = isBengali
                      ? 'তৈরি করা ফ্ল্যাশকার্ড (${GochanoLanguage.toBanglaDigits(cards.length)})'
                      : 'Generated Flashcards (${cards.length})';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.style_rounded,
                                  size: 18,
                                  color: colors.brand,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    cardCountText,
                                    style: type.cardHeading.copyWith(fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isBengali
                                ? 'কার্ড উল্টাতে ট্যাপ করুন'
                                : 'Tap card to reveal',
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < cards.length; i++)
                        _FlashcardTile(
                          index: i + 1,
                          card: cards[i] as Map,
                          isBengali: isBengali,
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FlashcardTile extends StatefulWidget {
  const _FlashcardTile({
    required this.index,
    required this.card,
    this.isBengali = false,
  });

  final int index;
  final Map card;
  final bool isBengali;

  @override
  State<_FlashcardTile> createState() => _FlashcardTileState();
}

class _FlashcardTileState extends State<_FlashcardTile> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final question = widget.card['question']?.toString() ?? '';
    final answer = widget.card['answer']?.toString() ?? '';
    final reviewDate = widget.card['reviewDate']?.toString() ?? '';
    final difficulty =
        widget.card['difficulty']?.toString().toLowerCase().trim() ?? '';

    final flipDuration = context.motionDuration(AppMotion.cardFlip);
    final flipCurve = context.motionCurve(AppMotion.easeInOut);

    Widget? difficultyWidget;
    if (difficulty.isNotEmpty) {
      Color bg = colors.surfaceVariant;
      Color fg = colors.textSecondary;
      String label = widget.card['difficulty']?.toString() ?? '';
      if (difficulty == 'easy' || difficulty == 'সহজ') {
        bg = colors.successSoft;
        fg = colors.success;
        label = widget.isBengali ? 'সহজ' : 'Easy';
      } else if (difficulty == 'medium' ||
          difficulty == 'মাঝারি' ||
          difficulty == 'med') {
        bg = colors.warningSoft;
        fg = colors.warning;
        label = widget.isBengali ? 'মাঝারি' : 'Medium';
      } else if (difficulty == 'hard' || difficulty == 'কঠিন') {
        bg = colors.errorSoft;
        fg = colors.error;
        label = widget.isBengali ? 'কঠিন' : 'Hard';
      }
      difficultyWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final cardIndexText = widget.isBengali
        ? 'কার্ড ${GochanoLanguage.toBanglaDigits(widget.index)}'
        : 'Card ${widget.index}';

    return Semantics(
      label:
          '$cardIndexText. ${widget.isBengali ? "প্রশ্ন:" : "Question:"} $question. '
          '${_revealed ? "${widget.isBengali ? 'উত্তর:' : 'Answer:'} $answer" : (widget.isBengali ? "উত্তর দেখতে ডাবল ট্যাপ করুন" : "Double tap to reveal answer.")}',
      button: true,
      child: AnimatedContainer(
        duration: flipDuration,
        curve: flipCurve,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _revealed
              ? colors.surfaceVariant.withValues(alpha: 0.35)
              : colors.surface,
          borderRadius: GochanoRadius.lgAll,
          border: Border.all(
            color: _revealed
                ? colors.brand.withValues(alpha: 0.5)
                : colors.border,
            width: _revealed ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: GochanoRadius.lgAll,
            onTap: () => setState(() => _revealed = !_revealed),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.brandSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              cardIndexText,
                              style: TextStyle(
                                color: colors.brand,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (difficultyWidget != null) ...[
                            const SizedBox(width: 8),
                            difficultyWidget,
                          ],
                        ],
                      ),
                      if (reviewDate.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.isBengali
                                  ? GochanoLanguage.toBanglaDigits(reviewDate)
                                  : reviewDate,
                              style: type.caption,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    question,
                    style: type.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_revealed)
                    Row(
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: colors.brand,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isBengali
                              ? 'উত্তর দেখতে ট্যাপ করুন'
                              : 'Tap to reveal answer',
                          style: type.caption.copyWith(
                            color: colors.brand,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.brandSoft.withValues(alpha: 0.5),
                        borderRadius: GochanoRadius.mdAll,
                        border: Border.all(
                          color: colors.brand.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 14,
                                color: colors.brand,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.isBengali ? 'উত্তর:' : 'Answer:',
                                style: TextStyle(
                                  color: colors.brand,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            answer,
                            style: type.body,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
