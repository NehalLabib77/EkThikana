// Phase 6 — the Pro exam hall: the timed room where the paper is written,
// now with the spec's exam controls on top of Phase 3's room.
//
// The contract with the student is deliberately strict:
//   * the clock runs down from the server's deadline, not from a local
//     timer that could be paused — and pausing is only offered when the
//     paper's builder allowed it;
//   * there is no hint, no explanation and no answer key anywhere on this
//     screen - the redacted start payload is all it ever holds;
//   * an expired clock submits whatever has been answered, because losing
//     an hour of work to a dialog would be worse than a low score;
//   * progress is saved back to the server (answers, flags and the
//     remaining time) while the paper runs, so closing the app never costs
//     an hour of work — reopening resumes the same attempt.
//
// Answers are held as option indices for MCQs (and typed text for short
// answers) and converted to bare letters on submit, which is what the
// server grades.
//
// The Phase 3 screen name, `ExamHallScreen`, is kept as an alias of this
// widget in `exam_hall_screen.dart`, so every existing route and test keeps
// working against one implementation.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../exam_models.dart';
import 'exam_result_screen.dart';
import '../exam_ui.dart';

class RealExamScreen extends StatefulWidget {
  const RealExamScreen({
    super.key,
    required this.examId,
    this.title = '',
    this.startFn,
    this.submitFn,
    this.analysisFn,
    this.resumeFn,
    this.saveFn,
    this.pauseFn,
  });

  final String examId;
  final String title;
  final ExamStartFn? startFn;
  final ExamSubmitFn? submitFn;
  final ExamAnalysisFn? analysisFn;

  /// Phase 6 seams. Null means "talk to the real backend".
  final ExamResumeFn? resumeFn;
  final ExamSaveFn? saveFn;
  final ExamPauseFn? pauseFn;

  @override
  State<RealExamScreen> createState() => _RealExamScreenState();
}

class _RealExamScreenState extends State<RealExamScreen> {
  static const int _saveEverySeconds = 15;

  ExamHall? _hall;
  List<String> _answers = const <String>[];
  final _flagged = <int>{};
  int _current = 0;
  int _remaining = 0;
  Timer? _timer;
  bool _submitting = false;
  bool _paused = false;
  bool _controlBusy = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Resume the unfinished attempt, or open a fresh one when the server
  /// says there is nothing to resume (404).
  ///
  /// A failure *without* a status code (no backend URL, no session) never
  /// reached the server, so we fall through to [start] which will surface
  /// the real problem; any other server verdict is shown as-is, because
  /// starting again over an attempt the server still holds would orphan the
  /// saved answers.
  Future<void> _open() async {
    setState(() {
      _hall = null;
      _error = null;
      _paused = false;
    });
    try {
      final resume = widget.resumeFn ?? ApiService.resumeExam;
      final start = widget.startFn ?? ApiService.startExam;

      Map<String, dynamic> payload;
      try {
        payload = await resume(widget.examId);
      } on ApiException catch (error) {
        final status = error.statusCode;
        if (status != null && status != 404) rethrow;
        payload = await start(widget.examId);
      }

      if (!mounted) return;
      final hall = ExamHall.fromJson(payload);
      var remaining = hall.deadlineAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        // Out of time: keep whatever the server saved and submit it now.
        remaining = hall.resumed ? 0 : hall.timeLimitSeconds;
      }
      final answers = List<String>.filled(hall.questions.length, '');
      for (var i = 0; i < answers.length && i < hall.savedAnswers.length; i++) {
        answers[i] = hall.savedAnswers[i];
      }
      setState(() {
        _hall = hall;
        _answers = answers;
        _flagged
          ..clear()
          ..addAll(hall.markedForReview.where((i) => i >= 0 && i < answers.length));
        _remaining = remaining;
        _current = _firstUnanswered(answers);
      });
      if (_remaining <= 0) {
        _submit(auto: true);
        return;
      }
      _startClock();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    }
  }

  int _firstUnanswered(List<String> answers) {
    final index = answers.indexWhere((answer) => answer.trim().isEmpty);
    return index < 0 ? 0 : index;
  }

  void _startClock() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
  }

  void _onSecond() {
    if (!mounted || _submitting || _paused) return;
    setState(() => _remaining -= 1);
    if (_remaining <= 0) {
      _timer?.cancel();
      _submit(auto: true);
      return;
    }
    if (_remaining % _saveEverySeconds == 0) {
      unawaited(_saveProgress());
    }
  }

  /// Spec 6.4 — the server keeps the answers, the flags and the remaining
  /// time while the paper runs. Best effort: a failed save never interrupts
  /// the exam (the submit still carries everything).
  Future<void> _saveProgress() async {
    final hall = _hall;
    if (hall == null || _submitting || _saving) return;
    _saving = true;
    try {
      final save = widget.saveFn ?? ApiService.saveExamProgress;
      await save(
        widget.examId,
        attemptId: hall.attemptId,
        answers: [
          for (var i = 0; i < hall.questions.length; i++) _answerFor(i),
        ],
        markedForReview: _flagged.toList()..sort(),
        remainingSeconds: _remaining < 0 ? 0 : _remaining,
      );
    } catch (_) {
      // Progress saving is a safety net, never a blocker.
    } finally {
      _saving = false;
    }
  }

  String _answerFor(int index) {
    final hall = _hall;
    if (hall == null || index >= hall.questions.length) return '';
    final question = hall.questions[index];
    final raw = index < _answers.length ? _answers[index] : '';
    if (!question.isChoice) return raw.trim();
    final option = int.tryParse(raw);
    return option == null ? '' : examLetter(option);
  }

  int _answeredCount() =>
      _answers.where((answer) => answer.trim().isNotEmpty).length;

  Future<void> _confirmAndSubmit() async {
    final hall = _hall;
    if (hall == null || _submitting) return;
    final answered = _answeredCount();
    final total = hall.questions.length;

    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.colors;
        return AlertDialog(
          title: Text(
            GochanoLanguage.text('Submit the paper?', 'প্রশ্নপত্র জমা দেবেন?'),
          ),
          content: Text(
            answered == total
                ? GochanoLanguage.text(
                    'All $total questions answered. Submit now?',
                    'সব $total টি প্রশ্নের উত্তর দেওয়া হয়েছে। এখনই জমা দেবেন?',
                  )
                : GochanoLanguage.text(
                    '$answered of $total answered. Blank answers score zero.',
                    '$total টির মধ্যে $answered এর উত্তর দেওয়া হয়েছে। খালি উত্তরে শূন্য।',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                GochanoLanguage.text('Keep writing', 'লিখতে থাকুন'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: Text(GochanoLanguage.text('Submit', 'জমা দিন')),
            ),
          ],
        );
      },
    );
    if (go == true) await _submit();
  }

  Future<void> _submit({bool auto = false}) async {
    final hall = _hall;
    if (hall == null || _submitting) return;

    setState(() => _submitting = true);
    try {
      final spent = (hall.timeLimitSeconds - _remaining)
          .clamp(0, hall.timeLimitSeconds);
      final submit = widget.submitFn ?? ApiService.submitExam;
      final result = await submit(
        widget.examId,
        attemptId: hall.attemptId,
        answers: [for (var i = 0; i < hall.questions.length; i++) _answerFor(i)],
        timeSpentSeconds: spent,
        markedForReview: _flagged.toList()..sort(),
        withAiAnalysis: true,
      );
      _timer?.cancel();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        GochanoRoute.to(
          builder: (_) => ExamResultScreen(
            examId: widget.examId,
            attemptId: hall.attemptId,
            result: result,
            analysisFn: widget.analysisFn,
            autoSubmitted: auto,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  /// Spec 6.4 — pause: save first, then freeze the clock on the server.
  Future<void> _pause() async {
    final hall = _hall;
    if (hall == null || _paused || _controlBusy || _submitting) return;
    setState(() => _controlBusy = true);
    await _saveProgress();
    try {
      final pause = widget.pauseFn ?? ApiService.pauseExam;
      await pause(
        widget.examId,
        attemptId: hall.attemptId,
        remainingSeconds: _remaining < 0 ? 0 : _remaining,
      );
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _paused = true;
        _controlBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _controlBusy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  /// Resume a paused paper: the server rewrites the deadline, the local
  /// clock restarts from what the server says is left.
  Future<void> _resume() async {
    final hall = _hall;
    if (hall == null || _controlBusy) return;
    setState(() {
      _controlBusy = true;
      _error = null;
    });
    try {
      final resume = widget.resumeFn ?? ApiService.resumeExam;
      final payload = await resume(widget.examId, attemptId: hall.attemptId);
      if (!mounted) return;
      final fresh = ExamHall.fromJson(payload);
      var remaining = fresh.deadlineAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) remaining = fresh.remainingSeconds;
      setState(() {
        _paused = false;
        _controlBusy = false;
        _remaining = remaining;
      });
      if (_remaining <= 0) {
        _submit(auto: true);
        return;
      }
      _startClock();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _controlBusy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  void _selectAnswer(String value) {
    setState(() {
      if (_current < _answers.length) _answers[_current] = value;
    });
    unawaited(_saveProgress());
  }

  void _toggleFlag() {
    setState(() {
      if (!_flagged.remove(_current)) _flagged.add(_current);
    });
    unawaited(_saveProgress());
  }

  void _move(int step) {
    setState(() => _current += step);
    unawaited(_saveProgress());
  }

  @override
  Widget build(BuildContext context) {
    final hall = _hall;
    final colors = context.colors;
    final type = context.type;

    if (hall == null) {
      return GochanoScaffold(
        appBar: GochanoAppBar(title: GochanoLanguage.text('Exam', 'পরীক্ষা')),
        body: _error == null
            ? examLoading(
                GochanoLanguage.text(
                  'Opening your paper…',
                  'প্রশ্নপত্র খোলা হচ্ছে…',
                ),
              )
            : Column(
                children: [
                  examErrorBox(context, _error!),
                  const SizedBox(height: GochanoSpacing.md),
                  SecondaryButton(
                    label: GochanoLanguage.text('Try again', 'আবার চেষ্টা করুন'),
                    onPressed: _open,
                  ),
                ],
              ),
      );
    }

    final question = hall.questions[_current];
    final urgent = !_paused && _remaining <= 60;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: widget.title.isEmpty
            ? GochanoLanguage.text('Exam in progress', 'পরীক্ষা চলছে')
            : widget.title,
        subtitle: hall.subject,
        automaticallyImplyLeading: !_submitting,
      ),
      bottomBar: _bottomBar(hall),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (_paused) ...[
            AppCard(
              accent: colors.info,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.pause_circle_outline_rounded,
                        color: colors.info,
                        size: GochanoSizes.iconLg,
                      ),
                      const SizedBox(width: GochanoSpacing.sm),
                      Expanded(
                        child: Text(
                          GochanoLanguage.text(
                            'Exam paused - the clock is stopped.',
                            'পরীক্ষা থামানো - ঘড়ি বন্ধ।',
                          ),
                          style: type.cardHeading,
                        ),
                      ),
                      GochanoBadge(
                        label: GochanoLanguage.text(
                          '${examClock(_remaining)} left',
                          '${examClock(_remaining)} বাকি',
                        ),
                        tone: GochanoBadgeTone.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    GochanoLanguage.text(
                      'Your answers are saved. Resume when you are ready.',
                      'আপনার উত্তর সংরক্ষিত হয়েছে। প্রস্তুত হলে আবার শুরু করুন।',
                    ),
                    style: context.type.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: GochanoSpacing.sm),
          ],
          AppCard(
            accent: urgent ? colors.error : colors.brand,
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  color: urgent ? colors.error : colors.brand,
                  size: GochanoSizes.iconLg,
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GochanoLanguage.text(
                          'Time remaining',
                          'বাকি সময়',
                        ),
                        style: context.type.caption,
                      ),
                      Semantics(
                        liveRegion: true,
                        label: GochanoLanguage.text(
                          'Time remaining ${examClock(_remaining)}',
                          'বাকি সময় ${examClock(_remaining)}',
                        ),
                        child: Text(
                          examClock(_remaining),
                          style: type.statistic.copyWith(
                            color: urgent ? colors.error : null,
                          ),
                        ),
                      ),
                      Text(
                        GochanoLanguage.text(
                          '${_answeredCount()} of ${hall.questions.length} answered',
                          '${hall.questions.length} টির মধ্যে ${_answeredCount()} এর উত্তর',
                        ),
                        style: context.type.caption,
                      ),
                    ],
                  ),
                ),
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Question ${_current + 1} / ${hall.questions.length}',
                    'প্রশ্ন ${_current + 1} / ${hall.questions.length}',
                  ),
                  tone: GochanoBadgeTone.brand,
                ),
                if (_flagged.isNotEmpty) ...[
                  const SizedBox(width: GochanoSpacing.xs),
                  GochanoBadge(
                    label: GochanoLanguage.text(
                      '${_flagged.length} marked',
                      '${_flagged.length} চিহ্নিত',
                    ),
                    tone: GochanoBadgeTone.warning,
                    icon: Icons.flag_rounded,
                  ),
                ],
              ],
            ),
          ),
          SectionHeader(
            title: GochanoLanguage.text('Questions', 'প্রশ্ন'),
          ),
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xs,
            children: [
              for (var i = 0; i < hall.questions.length; i++)
                _navigatorTile(i),
            ],
          ),
          SectionHeader(
            title: GochanoLanguage.text('Question ${_current + 1}', 'প্রশ্ন ${_current + 1}'),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Spec 6.3 — the marks are on screen before the answer:
                    // what a right one is worth, what a wrong one costs.
                    GochanoBadge(
                      label: GochanoLanguage.text(
                        'Marks: +${_trimMarks(hall.correctMarks)}',
                        'নম্বর: +${_trimMarks(hall.correctMarks)}',
                      ),
                      tone: GochanoBadgeTone.success,
                    ),
                    if (hall.negativeMarking && hall.penalty > 0) ...[
                      const SizedBox(width: GochanoSpacing.xs),
                      GochanoBadge(
                        label: GochanoLanguage.text(
                          'Wrong: -${_trimMarks(hall.penalty)}',
                          'ভুল: -${_trimMarks(hall.penalty)}',
                        ),
                        tone: GochanoBadgeTone.error,
                      ),
                    ],
                    if (question.topic.isNotEmpty) ...[
                      const SizedBox(width: GochanoSpacing.xs),
                      GochanoBadge(
                        label: question.topic,
                        tone: GochanoBadgeTone.neutral,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(question.question, style: type.body),
                const SizedBox(height: GochanoSpacing.md),
                if (question.isChoice) ...[
                  for (var o = 0; o < question.options.length; o++) ...[
                    if (o > 0) const SizedBox(height: GochanoSpacing.xs),
                    ExamChoiceTile(
                      title: '${examLetter(o)}. ${question.options[o]}',
                      selected: _answers[_current] == '$o',
                      onTap: () => _selectAnswer('$o'),
                    ),
                  ],
                ] else
                  TextFormField(
                    key: ValueKey<int>(_current),
                    initialValue: _current < _answers.length
                        ? _answers[_current]
                        : '',
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text(
                        'Your answer',
                        'আপনার উত্তর',
                      ),
                    ),
                    onChanged: (value) {
                      if (_current < _answers.length) {
                        _answers[_current] = value;
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: GochanoLanguage.text('Previous', 'আগের'),
                  icon: Icons.chevron_left_rounded,
                  onPressed: _current == 0 ? null : () => _move(-1),
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: GochanoLanguage.text('Next', 'পেরের'),
                  icon: Icons.chevron_right_rounded,
                  onPressed: _current >= hall.questions.length - 1
                      ? null
                      : () => _move(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          SecondaryButton(
            label: _flagged.contains(_current)
                ? GochanoLanguage.text(
                    'Remove the flag',
                    'চিহ্ন মুছুন',
                  )
                : GochanoLanguage.text(
                    'Mark for review',
                    'পরে দেখার জন্য চিহ্নিত',
                  ),
            icon: Icons.flag_rounded,
            onPressed: _toggleFlag,
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

  Widget _bottomBar(ExamHall hall) {
    if (_paused) {
      return PrimaryButton(
        label: GochanoLanguage.text('Resume exam', 'পরীক্ষা চালিয়ে যান'),
        busy: _controlBusy,
        busyLabel: GochanoLanguage.text('Resuming…', 'শুরু হচ্ছে…'),
        icon: Icons.play_arrow_rounded,
        onPressed: _controlBusy ? null : _resume,
      );
    }
    if (!hall.allowPause) {
      return PrimaryButton(
        label: GochanoLanguage.text('Submit exam', 'প্রশ্নপত্র জমা দিন'),
        busy: _submitting,
        busyLabel: GochanoLanguage.text('Scoring…', 'মূল্যায়ন হচ্ছে…'),
        onPressed: _submitting ? null : _confirmAndSubmit,
      );
    }
    return Row(
      children: [
        Expanded(
          child: SecondaryButton(
            label: GochanoLanguage.text('Pause exam', 'পরীক্ষা থামান'),
            icon: Icons.pause_rounded,
            expand: false,
            onPressed:
                _controlBusy || _submitting ? null : _pause,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: PrimaryButton(
            label: GochanoLanguage.text('Submit exam', 'প্রশ্নপত্র জমা দিন'),
            busy: _submitting,
            busyLabel: GochanoLanguage.text('Scoring…', 'মূল্যায়ন হচ্ছে…'),
            onPressed: _submitting ? null : _confirmAndSubmit,
          ),
        ),
      ],
    );
  }

  String _trimMarks(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  Widget _navigatorTile(int index) {
    final colors = context.colors;
    final isCurrent = index == _current;
    final answered = index < _answers.length && _answers[index].isNotEmpty;
    final flagged = _flagged.contains(index);

    final Color fill;
    final Color text;
    if (isCurrent) {
      fill = colors.brand;
      text = colors.surface;
    } else if (flagged) {
      fill = colors.warningSoft;
      text = colors.warning;
    } else if (answered) {
      fill = colors.successSoft;
      text = colors.success;
    } else {
      fill = colors.surfaceVariant;
      text = colors.textSecondary;
    }

    final label = GochanoLanguage.text(
      'Question ${index + 1}${flagged ? ', flagged' : ''}${answered ? ', answered' : ', not answered'}',
      'প্রশ্ন ${index + 1}',
    );

    return Semantics(
      button: true,
      selected: isCurrent,
      label: label,
      child: InkWell(
        onTap: () => setState(() => _current = index),
        borderRadius: GochanoRadius.mdAll,
        child: Container(
          width: GochanoSizes.minTouchTarget,
          height: GochanoSizes.minTouchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: GochanoRadius.mdAll,
            border: Border.all(
              color: isCurrent ? colors.brand : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            '${index + 1}',
            style: context.type.body.copyWith(
              color: text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
