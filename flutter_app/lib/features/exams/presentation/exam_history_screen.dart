// Phase 6 — "My Exams": the student's own exam history.
//
// Spec 6.9 in one list: every finished paper with its score, plus the
// improvement line ("+8%" versus the previous sitting). Everything shown is
// read from the caller's own results — there is no cross-user query here and
// nothing this screen can show about anyone else (spec 6.10's privacy rule
// is enforced at the data layer, so the UI never has to filter).
//
// Spec 6.10 also reaches the phone: the row menu hands out the paper's
// share code, and the copy says exactly what travels with it — the paper,
// never your marks.
//
// Tapping a row opens [ExamResultScreen] for that attempt: the full result
// payload when the network answers, otherwise the row's own numbers while
// the screen retries the analysis call itself.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
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

class ExamHistoryScreen extends StatefulWidget {
  const ExamHistoryScreen({
    super.key,
    this.historyFn,
    this.resultFn,
    this.analysisFn,
    this.shareFn,
  });

  final ExamHistoryFn? historyFn;
  final ExamResultFn? resultFn;
  final ExamAnalysisFn? analysisFn;
  final ExamShareFn? shareFn;

  @override
  State<ExamHistoryScreen> createState() => _ExamHistoryScreenState();
}

class _ExamHistoryScreenState extends State<ExamHistoryScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const <String, dynamic>{};

  ExamHistoryFn get _history => widget.historyFn ?? ApiService.examHistory;

  ExamResultFn get _result => widget.resultFn ?? ApiService.getExamResult;

  ExamShareFn get _share => widget.shareFn ?? ApiService.shareExam;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await _history(limit: 20);
      if (!mounted) return;
      setState(() {
        _data = body;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  List<Map<String, dynamic>> get _rows {
    final rows = _data['exams'];
    if (rows is! List) return const <Map<String, dynamic>>[];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final examId = '${row['examId'] ?? ''}';
    if (examId.isEmpty) return;
    final attemptId = '${row['attemptId'] ?? ''}';
    Map<String, dynamic>? payload;
    try {
      payload = await _result(
        examId,
        attemptId: attemptId.isEmpty ? null : attemptId,
      );
    } catch (_) {
      // Offline: fall through with the row's own numbers - the result
      // screen keeps them on screen while its own analysis call retries.
      payload = null;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => ExamResultScreen(
          examId: examId,
          attemptId: attemptId,
          result: payload ?? row,
          analysisFn: widget.analysisFn,
        ),
      ),
    );
  }

  /// Spec 6.10 — turn on link-sharing for this paper and show the code.
  /// The dialog states the privacy contract out loud: the code opens the
  /// paper, never the sender's marks.
  Future<void> _sharePaper(String examId) async {
    if (examId.isEmpty) return;
    try {
      final payload = await _share(examId, share: true);
      if (!mounted) return;
      final code = '${payload['shareCode'] ?? ''}';
      await _showShareDialog(
        title: GochanoLanguage.text(
          'Share this paper',
          'প্রশ্নপত্র শেয়ার করুন',
        ),
        code: code,
        body: GochanoLanguage.text(
          'Anyone with this code can read the paper. Your scores stay with you.',
          'কোডটি যার কাছে, সে শুধু প্রশ্ন দেখবে। আপনার নম্বর আপনার কাছেই থাকবে।',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await _showShareDialog(
        title: GochanoLanguage.text(
          'Could not share',
          'শেয়ার করা যায়নি',
        ),
        body: friendlyErrorMessage(error),
      );
    }
  }

  Future<void> _showShareDialog({
    required String title,
    required String body,
    String code = '',
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final type = dialogContext.type;
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (code.isNotEmpty) ...[
                SelectableText(code, style: type.statistic),
                const SizedBox(height: GochanoSpacing.sm),
              ],
              Text(body, style: dialogContext.type.caption),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(GochanoLanguage.text('Close', 'বন্ধ')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('My Exams', 'আমার পরীক্ষা'),
        subtitle: GochanoLanguage.text(
          'Past papers, scores and how you improved.',
          'আগের প্রশ্নপত্র, নম্বর আর উন্নতি।',
        ),
      ),
      body: _loading
          ? examLoading(
              GochanoLanguage.text('Loading your exams…', 'পরীক্ষা লোড হচ্ছে…'),
            )
          : _error != null
              ? ErrorState(
                  message: _error!,
                  onRetry: _load,
                  retryLabel: GochanoLanguage.text('Try again', 'আবার চেষ্টা'),
                )
              : _rows.isEmpty
                  ? EmptyState(
                      illustration: GochanoArt.emptyMaterials,
                      title: GochanoLanguage.text(
                        'No exams yet',
                        'এখনো কোনো পরীক্ষা নেই',
                      ),
                      message: GochanoLanguage.text(
                        'Finish a paper and it will show up here with its score.',
                        'একটি পরীক্ষা দিন - নম্বরসহ এখানে দেখা যাবে।',
                      ),
                      actionLabel: GochanoLanguage.text(
                        'Start an exam',
                        'পরীক্ষা শুরু করুন',
                      ),
                      onAction: () => Navigator.of(context).pop(),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: GochanoSpacing.xl),
                      children: [
                        _summary(),
                        SectionHeader(
                          title: GochanoLanguage.text(
                            'Past papers',
                            'পুরোনো প্রশ্নপত্র',
                          ),
                        ),
                        CardGroup(
                          children: [
                            for (final row in _rows)
                              GochanoListRow(
                                illustration: GochanoArt.featurePlanner,
                                title: '${row['title'] ?? ''}',
                                subtitle: '${row['subject'] ?? ''}',
                                metadata: [
                                  _dateOf(row),
                                  GochanoLanguage.text(
                                    '${row['correctCount'] ?? 0} of ${row['totalQuestions'] ?? 0} correct',
                                    '${row['totalQuestions'] ?? 0} টির মধ্যে ${row['correctCount'] ?? 0} সঠিক',
                                  ),
                                  '${row['timeManagementLabel'] ?? ''}',
                                ],
                                badge: GochanoBadge(
                                  label: '${_percentOf(row['percentage'])}%',
                                  tone: _scoreTone(
                                    _percentOf(row['percentage']),
                                  ),
                                ),
                                menuItems: [
                                  GochanoMenuAction(
                                    label: GochanoLanguage.text(
                                      'Share paper',
                                      'প্রশ্নপত্র শেয়ার',
                                    ),
                                    icon: Icons.share_rounded,
                                    onSelected: () => unawaited(
                                      _sharePaper('${row['examId'] ?? ''}'),
                                    ),
                                  ),
                                ],
                                onTap: () => _open(row),
                              ),
                          ],
                        ),
                      ],
                    ),
    );
  }

  /// The spec 6.9 improvement card ("Improvement: +8%"), with the average
  /// beside it. Both numbers come from the history payload — never
  /// re-derived on the phone.
  Widget _summary() {
    final improvement = _data['improvement'];
    final average = _percentOf(_data['averagePercentage']);
    final best = _percentOf(_data['bestPercentage']);

    return Padding(
      padding: const EdgeInsets.only(top: GochanoSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: StatCard(
              label: GochanoLanguage.text('Improvement', 'উন্নতি'),
              value: improvement is num
                  ? '${improvement >= 0 ? '+' : ''}${_trim(improvement.toDouble())}%'
                  : '—',
              caption: improvement is num
                  ? GochanoLanguage.text(
                      'vs your previous paper',
                      'আগের প্রশ্নপত্রের তুলনায়',
                    )
                  : GochanoLanguage.text(
                      'sit one more to compare',
                      'তুলনা করতে আরেকটি দিন',
                    ),
              icon: const Icon(Icons.trending_up_rounded),
              accent: improvement is num && improvement < 0
                  ? context.colors.warning
                  : context.colors.success,
              compact: true,
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: StatCard(
              label: GochanoLanguage.text('Average', 'গড়'),
              value: '$average%',
              caption: GochanoLanguage.text('best $best%', 'সেরা $best%'),
              icon: const Icon(Icons.insights_rounded),
              accent: context.colors.study,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  String _dateOf(Map<String, dynamic> row) {
    final day = '${row['dayKey'] ?? ''}';
    if (day.isNotEmpty) return day;
    final raw = row['createdAt'];
    if (raw is String) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
    if (raw is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(raw);
      return _ymd(dt);
    }
    if (raw is DateTime) return _ymd(raw);
    return '';
  }

  String _ymd(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day';
  }

  int _percentOf(Object? value) {
    final number = value is num ? value.toDouble() : 0.0;
    return number.round();
  }

  GochanoBadgeTone _scoreTone(int percent) {
    if (percent >= 75) return GochanoBadgeTone.success;
    if (percent >= 50) return GochanoBadgeTone.warning;
    return GochanoBadgeTone.error;
  }

  String _trim(double value) {
    final rounded = (value * 10).roundToDouble() / 10;
    if (rounded == rounded.roundToDouble()) return '${rounded.round()}';
    return '$rounded';
  }
}
