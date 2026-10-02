// Phase 3/6 — Real Exam Simulator setup.
//
// One screen decides how the paper is built (AI, an uploaded paper, questions
// the student already has, or questions typed in by hand), what it is called,
// how long it runs, how it is marked and whether the clock may be paused.
// It owns nothing about the exam itself: once the paper exists it hands the
// exam id to [RealExamScreen] and gets out of the way. "My Exams" (the spec
// 6.9 history) hangs off the app bar.
//
// Every backend call is injectable so widget tests can drive the flow
// without a network.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../exam_models.dart';
import 'exam_history_screen.dart';
import 'exam_upload_screen.dart';
import 'real_exam_screen.dart';
import '../exam_ui.dart';

class ExamSetupScreen extends StatefulWidget {
  const ExamSetupScreen({
    super.key,
    this.createFn,
    this.listFn,
    this.uploadFn,
    this.startFn,
    this.submitFn,
    this.analysisFn,
    this.pickFn,
    this.resumeFn,
    this.saveFn,
    this.pauseFn,
    this.historyFn,
  });

  final ExamCreateFn? createFn;
  final ExamListFn? listFn;
  final ExamUploadFn? uploadFn;
  final ExamStartFn? startFn;
  final ExamSubmitFn? submitFn;
  final ExamAnalysisFn? analysisFn;
  final ExamPickFn? pickFn;

  /// Phase 6 seams, handed straight to [RealExamScreen] / the history list.
  final ExamResumeFn? resumeFn;
  final ExamSaveFn? saveFn;
  final ExamPauseFn? pauseFn;
  final ExamHistoryFn? historyFn;

  @override
  State<ExamSetupScreen> createState() => _ExamSetupScreenState();
}

class _ExamSetupScreenState extends State<ExamSetupScreen> {
  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _topic = TextEditingController();
  final _count = TextEditingController(text: '15');
  final _marks = TextEditingController(text: '60');
  final _minutes = TextEditingController(text: '45');
  final _penalty = TextEditingController(text: '0.25');

  String _source = 'ai';
  String _difficulty = 'medium';
  bool _negative = true;
  bool _allowPause = true;
  bool _busy = false;
  String? _error;
  List<ExamDraftQuestion>? _drafts;
  ExamPaper? _saved;
  bool _useQuizQuestions = true;

  ExamCreateFn get _create => widget.createFn ?? ApiService.createExam;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _topic.dispose();
    _count.dispose();
    _marks.dispose();
    _minutes.dispose();
    _penalty.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if ((_source == 'upload' || _source == 'manual') &&
        (_drafts == null || _drafts!.isEmpty)) {
      if (_source == 'manual') {
        await _openManual();
      } else {
        await _openUpload();
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final body = <String, dynamic>{
      'subject': _subject.text.trim(),
      'source': _source,
      'questionCount': examInt(int.tryParse(_count.text)),
      'totalMarks': examDouble(double.tryParse(_marks.text)),
      'timeLimitMinutes': examInt(int.tryParse(_minutes.text)),
      'negativeMarking': {
        'enabled': _negative,
        'penalty': _negative ? examDouble(double.tryParse(_penalty.text)) : 0.0,
      },
      'difficulty': _difficulty,
      'allowPause': _allowPause,
      if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
      if (_topic.text.trim().isNotEmpty) 'topic': _topic.text.trim(),
      if ((_source == 'upload' || _source == 'manual') && _drafts != null)
        'questions': _drafts!.map((q) => q.toJson()).toList(),
      if (_source == 'saved' && _saved != null) 'sourceExamId': _saved!.examId,
    };

    try {
      final created = await _create(body);
      final examId = '${created['examId'] ?? ''}';
      if (examId.isEmpty) {
        throw GochanoLanguage.text(
          'The paper could not be created.',
          'প্রশ্নপত্র তৈরি করা যায়নি।',
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        GochanoRoute.to(
          builder: (_) => RealExamScreen(
            examId: examId,
            title: '${created['title'] ?? ''}',
            startFn: widget.startFn,
            submitFn: widget.submitFn,
            analysisFn: widget.analysisFn,
            resumeFn: widget.resumeFn,
            saveFn: widget.saveFn,
            pauseFn: widget.pauseFn,
          ),
        ),
      );
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _openUpload() async {
    final picked = await Navigator.of(context).push<List<ExamDraftQuestion>>(
      GochanoRoute.to(
        builder: (_) => ExamUploadScreen(
          uploadFn: widget.uploadFn,
          pickFn: widget.pickFn,
          initialSubject: _subject.text.trim(),
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _drafts = picked;
      _source = 'upload';
      _error = null;
      if (_subject.text.trim().isEmpty) _subject.text = 'Uploaded paper';
      _count.text = '${picked.length}';
    });
  }

  /// Spec 6.1/6.2 — "manual input": seed the correction editor with blank
  /// rows so the student can type a paper in instead of uploading one.
  Future<void> _openManual() async {
    final wanted = examInt(int.tryParse(_count.text));
    final rows = wanted < 1 ? 1 : (wanted > 50 ? 50 : wanted);
    final picked = await Navigator.of(context).push<List<ExamDraftQuestion>>(
      GochanoRoute.to(
        builder: (_) => ExamUploadScreen(
          uploadFn: widget.uploadFn,
          pickFn: widget.pickFn,
          initialSubject: _subject.text.trim(),
          manual: true,
          initialDrafts: List<ExamDraftQuestion>.generate(
            rows,
            (_) => ExamDraftQuestion.empty(),
            growable: true,
          ),
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _drafts = picked;
      _source = 'manual';
      _error = null;
      if (_subject.text.trim().isEmpty) _subject.text = 'My questions';
      _count.text = '${picked.length}';
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => ExamHistoryScreen(historyFn: widget.historyFn),
      ),
    );
  }

  Future<void> _pickSaved() async {
    final listFn = widget.listFn ?? ApiService.listExams;
    Map<String, dynamic> body;
    setState(() => _busy = true);
    try {
      body = await listFn();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final exams = examMapList(body['exams']).map(ExamPaper.fromJson).toList();
    final chosen = await showModalBottomSheet<ExamPaper?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GochanoSpacing.md),
          children: [
            Text(
              GochanoLanguage.text(
                'Saved questions',
                'সংরক্ষিত প্রশ্ন',
              ),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            ExamChoiceTile(
              title: GochanoLanguage.text(
                'Use my quiz questions',
                'আমার কুইজের প্রশ্ন ব্যবহার করুন',
              ),
              subtitle: GochanoLanguage.text(
                'Builds a paper from what you have already answered.',
                'আপনার আগের উত্তরগুলো থেকে প্রশ্নপত্র তৈরি হবে।',
              ),
              selected: true,
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            for (final paper in exams) ...[
              const SizedBox(height: GochanoSpacing.xs),
              ExamChoiceTile(
                title: paper.title.isEmpty ? paper.subject : paper.title,
                subtitle:
                    '${paper.subject} · ${paper.questionCount} Q · ${paper.totalMarks.round()} marks',
                selected: false,
                onTap: () => Navigator.of(sheetContext).pop(paper),
              ),
            ],
            if (exams.isEmpty) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Text(
                GochanoLanguage.text(
                  'No previous papers yet - your quiz questions work best.',
                  'আগের প্রশ্নপত্র নেই - কুইজের প্রশ্নগুলোই ব্যবহার করুন।',
                ),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _saved = chosen;
      _useQuizQuestions = chosen == null;
      _source = 'saved';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          'Real Exam Simulator',
          'পরীক্ষা হল সিমুলেটর',
        ),
        subtitle: GochanoLanguage.text(
          'A full paper under exam conditions.',
          'পরীক্ষার চাপে সম্পূর্ণ প্রশ্নপত্র।',
        ),
        actions: [
          IconActionButton(
            icon: Icons.history_rounded,
            label: GochanoLanguage.text('My exams', 'আমার পরীক্ষা'),
            onPressed: _openHistory,
          ),
        ],
      ),
      bottomBar: PrimaryButton(
        label: GochanoLanguage.text('Start exam', 'পরীক্ষা শুরু করুন'),
        busy: _busy,
        busyLabel: GochanoLanguage.text('Building paper…', 'তৈরি হচ্ছে…'),
        onPressed: _start,
      ),
      body: ListView(
        children: [
          SectionHeader(
            title: GochanoLanguage.text('Question source', 'প্রশ্নের উৎস'),
          ),
          ExamChoiceTile(
            title: GochanoLanguage.text('Generate with AI', 'এআই দিয়ে তৈরি'),
            subtitle: GochanoLanguage.text(
              'Ziku writes a fresh paper for this subject.',
              'জিকু বিষয় অনুযায়ী নতুন প্রশ্নপত্র বানাবে।',
            ),
            selected: _source == 'ai',
            onTap: () => setState(() => _source = 'ai'),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          ExamChoiceTile(
            title: GochanoLanguage.text('Upload a paper', 'প্রশ্নপত্র আপলোড'),
            subtitle: _drafts == null
                ? GochanoLanguage.text(
                    'PDF, image or pasted text - you fix the answers.',
                    'পিডিএফ, ছবি বা লেখা - উত্তর ঠিক করে নিন।',
                  )
                : GochanoLanguage.text(
                    '${_drafts!.length} questions ready.',
                    '${_drafts!.length} টি প্রশ্ন প্রস্তুত।',
                  ),
            selected: _source == 'upload',
            onTap: () {
              if (_source == 'upload' && (_drafts?.isEmpty ?? true)) {
                _openUpload();
                return;
              }
              setState(() => _source = 'upload');
            },
          ),
          const SizedBox(height: GochanoSpacing.xs),
          ExamChoiceTile(
            title: GochanoLanguage.text('Write your own', 'নিজে লিখুন'),
            subtitle: _source == 'manual'
                ? (_drafts == null || _drafts!.isEmpty
                    ? GochanoLanguage.text(
                        'Type each question and its answer.',
                        'প্রতিটি প্রশ্ন ও উত্তর টাইপ করুন।',
                      )
                    : GochanoLanguage.text(
                        '${_drafts!.length} questions written.',
                        '${_drafts!.length} টি প্রশ্ন লেখা হয়েছে।',
                      ))
                : GochanoLanguage.text(
                    'Type the paper in yourself.',
                    'প্রশ্নপত্র নিজে টাইপ করুন।',
                  ),
            selected: _source == 'manual',
            onTap: () {
              if (_source == 'manual' && (_drafts?.isEmpty ?? true)) {
                _openManual();
                return;
              }
              setState(() => _source = 'manual');
            },
          ),
          const SizedBox(height: GochanoSpacing.xs),
          ExamChoiceTile(
            title: GochanoLanguage.text('Saved questions', 'সংরক্ষিত প্রশ্ন'),
            subtitle: _source == 'saved'
                ? _saved == null
                    ? GochanoLanguage.text(
                        'From my quiz questions',
                        'কুইজের প্রশ্ন থেকে',
                      )
                    : _saved!.title
                : GochanoLanguage.text(
                    'Reuse a paper you already finished.',
                    'আগের প্রশ্নপত্র নতুন করে দিন।',
                  ),
            selected: _source == 'saved',
            onTap: () {
              if (_source == 'saved') {
                _pickSaved();
                return;
              }
              setState(() => _source = 'saved');
              _pickSaved();
            },
          ),
          if (_source == 'upload') ...[
            const SizedBox(height: GochanoSpacing.xs),
            SecondaryButton(
              label: _drafts == null
                  ? GochanoLanguage.text(
                      'Choose or paste a paper',
                      'প্রশ্নপত্র বাছুন বা লিখুন',
                    )
                  : GochanoLanguage.text(
                      'Edit questions',
                      'প্রশ্ন সম্পাদনা',
                    ),
              icon: Icons.upload_file_rounded,
              onPressed: _openUpload,
            ),
          ],
          if (_source == 'manual') ...[
            const SizedBox(height: GochanoSpacing.xs),
            SecondaryButton(
              label: _drafts == null
                  ? GochanoLanguage.text(
                      'Write the questions',
                      'প্রশ্নগুলো লিখুন',
                    )
                  : GochanoLanguage.text(
                      'Edit my ${_drafts!.length} questions',
                      'আমার ${_drafts!.length} টি প্রশ্ন সম্পাদনা',
                    ),
              icon: Icons.edit_note_rounded,
              onPressed: _openManual,
            ),
          ],
          if (_source == 'saved' && _saved == null && _useQuizQuestions) ...[
            const SizedBox(height: GochanoSpacing.xs),
            SecondaryButton(
              label: GochanoLanguage.text(
                'Choose saved paper',
                'সংরক্ষিত প্রশ্নপত্র বাছুন',
              ),
              icon: Icons.folder_open_rounded,
              onPressed: _pickSaved,
            ),
          ],
          const SizedBox(height: GochanoSpacing.md),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text(
                'Exam title (optional)',
                'পরীক্ষার নাম (ঐচ্ছিক)',
              ),
              hintText: GochanoLanguage.text(
                'Physics Model Test',
                'পদার্থবিজ্ঞান মডেল টেস্ট',
              ),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _subject,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Subject', 'বিষয়'),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _topic,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Topic (optional)', 'টপিক (ঐচ্ছিক)'),
            ),
          ),
          SectionHeader(
            title: GochanoLanguage.text('Paper settings', 'প্রশ্নপত্র সেটিংস'),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _count,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: GochanoLanguage.text(
                            'Questions',
                            'প্রশ্ন',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _marks,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: GochanoLanguage.text(
                            'Total marks',
                            'মোট নম্বর',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Time limit (minutes)',
                      'সময় (মিনিট)',
                    ),
                  ),
                ),
                const SizedBox(height: GochanoSpacing.md),
                Text(
                  GochanoLanguage.text(
                    'Negative marking',
                    'নেগেটিভ মার্কিং',
                  ),
                  style: type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                ExamChoiceTile(
                  title: GochanoLanguage.text('On', 'চালু'),
                  subtitle: GochanoLanguage.text(
                    'A wrong answer costs marks.',
                    'ভুল উত্তরে নম্বর কাটা হবে।',
                  ),
                  selected: _negative,
                  onTap: () => setState(() => _negative = true),
                ),
                const SizedBox(height: GochanoSpacing.xs),
                ExamChoiceTile(
                  title: GochanoLanguage.text('Off', 'বন্ধ'),
                  subtitle: GochanoLanguage.text(
                    'Blank and wrong both score zero.',
                    'খালি ও ভুল উত্তরে শূন্য।',
                  ),
                  selected: !_negative,
                  onTap: () => setState(() => _negative = false),
                ),
                if (_negative) ...[
                  const SizedBox(height: GochanoSpacing.sm),
                  TextField(
                    controller: _penalty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text(
                        'Marks cut per wrong answer',
                        'প্রতিটি ভুলের জন্য কাটা নম্বর',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: GochanoSpacing.md),
                Text(
                  GochanoLanguage.text('Pause exam', 'পরীক্ষা থামানো'),
                  style: type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                ExamChoiceTile(
                  title: GochanoLanguage.text('Allowed', 'অনুমোদিত'),
                  subtitle: GochanoLanguage.text(
                    'Step away - the clock stops and your answers are kept.',
                    'একটু থামুন - ঘড়ি থেমে থাকবে, উত্তর থাকবে।',
                  ),
                  selected: _allowPause,
                  onTap: () => setState(() => _allowPause = true),
                ),
                const SizedBox(height: GochanoSpacing.xs),
                ExamChoiceTile(
                  title: GochanoLanguage.text('Not allowed', 'অনুমোদিত নয়'),
                  subtitle: GochanoLanguage.text(
                    'Real exam conditions - one sitting, no stops.',
                    'আসল পরীক্ষার মতো - একবারে, থামা ছাড়া।',
                  ),
                  selected: !_allowPause,
                  onTap: () => setState(() => _allowPause = false),
                ),
              ],
            ),
          ),
          SectionHeader(
            title: GochanoLanguage.text('Difficulty', 'কঠিনতা'),
          ),
          FilterChipBar<String>(
            options: const ['easy', 'medium', 'hard', 'real_exam'],
            selected: _difficulty,
            onSelected: (value) => setState(() => _difficulty = value),
            labelOf: _difficultyLabel,
          ),
          if (_error != null) ...[
            const SizedBox(height: GochanoSpacing.md),
            examErrorBox(context, _error!),
          ],
          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }

  String _difficultyLabel(String value) {
    switch (value) {
      case 'easy':
        return GochanoLanguage.text('Easy', 'সহজ');
      case 'hard':
        return GochanoLanguage.text('Hard', 'কঠিন');
      case 'real_exam':
        return GochanoLanguage.text('Real exam', 'আসল পরীক্ষা');
      default:
        return GochanoLanguage.text('Medium', 'মাঝারি');
    }
  }
}
