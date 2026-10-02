// Phase 3/6 — upload a paper, or type one in, and check every question.
//
// The rule this screen exists for: nothing enters an exam hall without the
// student having seen it. The parser (line-splitter for plain text, AI for
// everything else) hands back draft questions *with* answers; this screen
// lets the student correct the question, the options and the answer key
// before [ExamSetupScreen] creates the paper.
//
// Three ways in: pick a file, paste the questions as text, or (spec 6.1
// "manual input") start from blank rows and write the paper yourself. All
// three funnel into the same editor and the same "Use N questions" button.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../exam_models.dart';
import '../exam_ui.dart';

class ExamUploadScreen extends StatefulWidget {
  const ExamUploadScreen({
    super.key,
    this.uploadFn,
    this.pickFn,
    this.initialSubject = '',
    this.initialCount = 15,
    this.initialDrafts,
    this.manual = false,
  });

  final ExamUploadFn? uploadFn;
  final ExamPickFn? pickFn;
  final String initialSubject;
  final int initialCount;

  /// Pre-filled rows: the "write your own" path seeds blank questions so
  /// the editor opens ready for typing instead of waiting for a file.
  final List<ExamDraftQuestion>? initialDrafts;

  /// True when the student came to type the paper in, not to extract one.
  final bool manual;

  @override
  State<ExamUploadScreen> createState() => _ExamUploadScreenState();
}

class _ExamUploadScreenState extends State<ExamUploadScreen> {
  static const _allowedExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'txt', 'md'];

  final _subject = TextEditingController();
  final _count = TextEditingController();
  final _pasted = TextEditingController();

  ExamPickResult? _file;
  List<ExamDraftQuestion>? _drafts;
  bool _busy = false;
  String? _error;
  int _expanded = -1;

  ExamUploadFn get _upload => widget.uploadFn ?? ApiService.uploadExamPaper;

  @override
  void initState() {
    super.initState();
    _subject.text = widget.initialSubject;
    _count.text = '${widget.initialCount}';
    final seeded = widget.initialDrafts;
    if (seeded != null && seeded.isNotEmpty) {
      _drafts = List<ExamDraftQuestion>.from(seeded, growable: true);
      _expanded = 0;
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _count.dispose();
    _pasted.dispose();
    super.dispose();
  }

  bool get _hasBytes => _file != null || _pasted.text.trim().isNotEmpty;

  Future<void> _pickFile() async {
    try {
      final ExamPickResult? picked;
      if (widget.pickFn != null) {
        picked = await widget.pickFn!();
      } else {
        final selected = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: _allowedExtensions,
        );
        picked = selected == null
            ? null
            : ExamPickResult(
                name: selected.name,
                bytes: await selected.readAsBytes(),
              );
      }
      if (picked == null || !mounted) return;
      setState(() {
        _file = picked;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _extract() async {
    if (!_hasBytes) {
      setState(() => _error = GochanoLanguage.text(
            'Choose a file or paste the questions first.',
            'আগে ফাইল বাছুন বা প্রশ্নগুলো লিখুন।',
          ));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final List<int> bytes;
      final String name;
      if (_file != null) {
        bytes = _file!.bytes;
        name = _file!.name;
      } else {
        bytes = utf8.encode(_pasted.text);
        name = 'pasted.txt';
      }

      final body = await _upload(
        bytes: bytes,
        filename: name,
        mimeType: _file?.mime ?? '',
        subject: _subject.text.trim(),
        questionCount: examInt(int.tryParse(_count.text)),
      );

      final drafts = examMapList(body['questions'])
          .map(ExamDraftQuestion.fromJson)
          .toList();
      if (drafts.isEmpty) {
        throw GochanoLanguage.text(
          'No questions could be read from that. Try pasting the text instead.',
          'কোনো প্রশ্ন পাওয়া যায়নি। লেখাটি পেস্ট করে দেখুন।',
        );
      }
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _expanded = -1;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  void _accept() {
    final drafts = _drafts;
    if (drafts == null) return;
    final ready = drafts.where((q) => q.isComplete).toList();
    if (ready.length != drafts.length) {
      setState(() => _error = GochanoLanguage.text(
            '${drafts.length - ready.length} questions still need an answer.',
            '${drafts.length - ready.length} টি প্রশ্নের উত্তর দেওয়া হয়নি।',
          ));
      return;
    }
    Navigator.of(context).pop(ready);
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final drafts = _drafts;
    final questionCount =
        drafts == null ? 0 : drafts.where((q) => q.isComplete).length;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: widget.manual
            ? GochanoLanguage.text('Write your own', 'নিজে লিখুন')
            : GochanoLanguage.text('Upload a paper', 'প্রশ্নপত্র আপলোড'),
        subtitle: widget.manual
            ? GochanoLanguage.text(
                'One question at a time - type the question and its answer.',
                'একটার পর একটা - প্রশ্ন ও উত্তর টাইপ করুন।',
              )
            : GochanoLanguage.text(
                'Check every answer before the exam starts.',
                'পরীক্ষা শুরুর আগে প্রতিটি উত্তর দেখে নিন।',
              ),
      ),
      bottomBar: drafts == null
          ? PrimaryButton(
              label: GochanoLanguage.text('Extract questions', 'প্রশ্ন বের করুন'),
              busy: _busy,
              busyLabel: GochanoLanguage.text('Reading…', 'পড়া হচ্ছে…'),
              onPressed: _hasBytes ? _extract : null,
            )
          : PrimaryButton(
              label: GochanoLanguage.text(
                'Use ${drafts.length} questions',
                '${drafts.length} টি প্রশ্ন ব্যবহার করুন',
              ),
              onPressed: _accept,
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (drafts == null) ...[
            AppCard(
              onTap: _busy ? null : _pickFile,
              child: Row(
                children: [
                  GochanoIllustration(
                    _file == null
                        ? GochanoArt.filePdf
                        : GochanoArt.fileIdFor(fileName: _file!.name),
                    size: 44,
                    accent: context.colors.study,
                  ),
                  const SizedBox(width: GochanoSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _file?.name ??
                              GochanoLanguage.text(
                                'Choose a file',
                                'একটি ফাইল বাছুন',
                              ),
                          style: type.cardHeading,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          GochanoLanguage.text(
                            'PDF, JPG or PNG - or paste the text below',
                            'পিডিএফ, জেপিইজি বা পিএনজি - অথবা নিচে লেখা পেস্ট করুন',
                          ),
                          style: type.caption,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.upload_file_rounded,
                    color: context.colors.textSecondary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),
            TextField(
              controller: _subject,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Subject', 'বিষয়'),
              ),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text(
                  'How many questions to read',
                  'কয়টি প্রশ্ন তুলবেন',
                ),
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),
            TextField(
              controller: _pasted,
              maxLines: 8,
              minLines: 5,
              // Typing is what arms the extract button - without a rebuild
              // it would stay disabled under the student's fingers.
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: GochanoLanguage.text(
                  'Or paste the questions',
                  'অথবা প্রশ্নগুলো পেস্ট করুন',
                ),
                hintText: GochanoLanguage.text(
                  '1. What is the speed of light?\nA. 3 x 10^8 m/s\nB. 3 x 10^6 m/s',
                  '১. আলোর গতি কত?\nক. 3 x 10^8 মি/সে\nখ. 3 x 10^6 মি/সে',
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: GochanoSpacing.lg),
              examLoading(
                GochanoLanguage.text(
                  'Reading your paper…',
                  'আপনার প্রশ্নপত্র পড়া হচ্ছে…',
                ),
              ),
            ],
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      '${drafts.length} questions found',
                      '${drafts.length} টি প্রশ্ন পাওয়া গেছে',
                    ),
                    style: type.sectionHeading,
                  ),
                ),
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '$questionCount ready',
                    '$questionCount টি প্রস্তুত',
                  ),
                  tone: questionCount == drafts.length
                      ? GochanoBadgeTone.success
                      : GochanoBadgeTone.warning,
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            for (var i = 0; i < drafts.length; i++) ...[
              _draftCard(context, drafts[i], i),
              const SizedBox(height: GochanoSpacing.sm),
            ],
            SecondaryButton(
              label: GochanoLanguage.text('Add question', 'আরেকটি প্রশ্ন'),
              icon: Icons.add_rounded,
              onPressed: () => setState(() {
                _drafts!.add(ExamDraftQuestion.empty());
                _expanded = drafts.length;
              }),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: GochanoSpacing.md),
            examErrorBox(context, _error!),
          ],
          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }

  Widget _draftCard(BuildContext context, ExamDraftQuestion draft, int index) {
    final colors = context.colors;
    final type = context.type;
    final open = _expanded == index;

    return AppCard(
      onTap: () => setState(() => _expanded = open ? -1 : index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GochanoBadge(
                label: 'Q${index + 1}',
                tone: draft.isComplete
                    ? GochanoBadgeTone.success
                    : GochanoBadgeTone.warning,
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  draft.question.isEmpty
                      ? GochanoLanguage.text('Empty question', 'খালি প্রশ্ন')
                      : draft.question,
                  style: type.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: colors.textSecondary,
              ),
            ],
          ),
          if (open) ...[
            const SizedBox(height: GochanoSpacing.sm),
            TextFormField(
              initialValue: draft.question,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Question', 'প্রশ্ন'),
              ),
              onChanged: (value) => draft.question = value,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            ExamChoiceTile(
              title: GochanoLanguage.text('Multiple choice', 'একাধিক নির্বাচন'),
              selected: draft.type == 'mcq',
              onTap: () => setState(() => draft.type = 'mcq'),
            ),
            const SizedBox(height: GochanoSpacing.xs),
            ExamChoiceTile(
              title: GochanoLanguage.text('Short answer', 'সংক্ষিপ্ত উত্তর'),
              selected: draft.type != 'mcq',
              onTap: () => setState(() => draft.type = 'short'),
            ),
            if (draft.type == 'mcq') ...[
              const SizedBox(height: GochanoSpacing.sm),
              for (var o = 0; o < draft.options.length; o++)
                Padding(
                  padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
                  child: TextFormField(
                    initialValue: draft.options[o],
                    decoration: InputDecoration(
                      labelText:
                          '${examLetter(o)}. ${GochanoLanguage.text('Option', 'বিকল্প')}',
                    ),
                    onChanged: (value) => draft.options[o] = value,
                  ),
                ),
              SecondaryButton(
                label: GochanoLanguage.text('Add option', 'আরেকটি বিকল্প'),
                icon: Icons.add_rounded,
                onPressed: draft.options.length >= 6
                    ? null
                    : () => setState(
                          () => draft.options.add(''),
                        ),
              ),
            ],
            const SizedBox(height: GochanoSpacing.sm),
            TextFormField(
              initialValue: draft.correct,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text(
                  'Answer key (A, B, C… or the answer)',
                  'উত্তর (ক, খ, গ… বা উত্তরটি)',
                ),
              ),
              onChanged: (value) => setState(() => draft.correct = value),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            TextFormField(
              initialValue: draft.topic,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Topic', 'টপিক'),
              ),
              onChanged: (value) => draft.topic = value,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            TextFormField(
              initialValue: draft.explanation,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text(
                  'Why is it correct?',
                  'সঠিক কেন?',
                ),
              ),
              onChanged: (value) => draft.explanation = value,
            ),
          ],
        ],
      ),
    );
  }
}
