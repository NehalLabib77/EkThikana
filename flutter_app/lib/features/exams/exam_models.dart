// Phase 3 — Real Exam Simulator models and the function seams the screens
// inject.
//
// Two question shapes on purpose:
//   * [ExamQuestion] is what the hall is allowed to see — index, text,
//     options, topic, marks. The answer key and the explanation never leave
//     the server during an attempt, so this model has nowhere to put them.
//   * [ExamDraftQuestion] is what the upload/correction step works with —
//     the same paper *with* the answer, because a student has to be able to
//     fix what the AI inferred before the exam starts.

/// POST /api/exams/create body. Built by the setup screen so tests can hand
/// a canned function the exact map they want to assert against.
typedef ExamCreateFn = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> body,
);

/// GET /api/exams — the "saved questions" picker.
typedef ExamListFn = Future<Map<String, dynamic>> Function();

/// POST /api/exams/upload — extract questions from a paper.
typedef ExamUploadFn = Future<Map<String, dynamic>> Function({
  required List<int> bytes,
  required String filename,
  required String mimeType,
  String subject,
  int questionCount,
});

/// POST /api/exams/{id}/start — opens the hall.
typedef ExamStartFn = Future<Map<String, dynamic>> Function(String examId);

/// POST /api/exams/{id}/submit — server-side grading.
typedef ExamSubmitFn = Future<Map<String, dynamic>> Function(
  String examId, {
  required String attemptId,
  required List<String> answers,
  int? timeSpentSeconds,
  List<int> markedForReview,
  bool withAiAnalysis,
});

/// GET /api/exams/{id}/analysis — score, weak topics, Ziku's plan.
typedef ExamAnalysisFn = Future<Map<String, dynamic>> Function(
  String examId, {
  String? attemptId,
  bool withAi,
});

/// POST /api/exams/{id}/resume — reopen the unfinished attempt (Phase 6).
/// The server answers 404 when nothing is open, which is the signal to call
/// [ExamStartFn] instead.
typedef ExamResumeFn = Future<Map<String, dynamic>> Function(
  String examId, {
  String? attemptId,
});

/// POST /api/exams/{id}/save — spec 6.4: keep the selected answers, the
/// review flags and the remaining time on the server while the paper runs.
  typedef ExamSaveFn = Future<Map<String, dynamic>> Function(
    String examId, {
    required String attemptId,
    required List<String> answers,
    List<int> markedForReview,
    int? remainingSeconds,
  });

/// POST /api/exams/{id}/pause — freeze the clock (papers with pause on).
typedef ExamPauseFn = Future<Map<String, dynamic>> Function(
  String examId, {
  required String attemptId,
  int? remainingSeconds,
});

/// GET /api/exams/history — spec 6.9, the "My Exams" list.
typedef ExamHistoryFn = Future<Map<String, dynamic>> Function({int limit});

/// GET /api/exams/{id}/result — one finished attempt, for the history list.
typedef ExamResultFn = Future<Map<String, dynamic>> Function(
  String examId, {
  String? attemptId,
});

/// POST /api/exams/{id}/share - spec 6.10: hand out a read-only code for
/// one of your own papers. Nothing about your scores travels with it.
typedef ExamShareFn = Future<Map<String, dynamic>> Function(
  String examId, {
  required bool share,
});

/// What the file picker hands back before anything is uploaded. Tests inject
/// this instead of opening the platform picker.
class ExamPickResult {
  const ExamPickResult({
    required this.name,
    required this.bytes,
    this.mime = '',
  });

  final String name;
  final List<int> bytes;
  final String mime;
}

typedef ExamPickFn = Future<ExamPickResult?> Function();

class ExamPaper {
  const ExamPaper({
    required this.examId,
    required this.title,
    required this.subject,
    required this.topic,
    required this.source,
    required this.difficulty,
    required this.questionCount,
    required this.totalMarks,
    required this.timeLimitMinutes,
    required this.negativeMarking,
    required this.correctMarks,
    required this.penalty,
    required this.attemptCount,
  });

  final String examId;
  final String title;
  final String subject;
  final String topic;
  final String source;
  final String difficulty;
  final int questionCount;
  final double totalMarks;
  final int timeLimitMinutes;
  final bool negativeMarking;
  final double correctMarks;
  final double penalty;
  final int attemptCount;

  factory ExamPaper.fromJson(Map<String, dynamic> json) => ExamPaper(
        examId: '${json['examId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        subject: '${json['subject'] ?? ''}',
        topic: '${json['topic'] ?? ''}',
        source: '${json['source'] ?? 'ai'}',
        difficulty: '${json['difficulty'] ?? 'medium'}',
        questionCount: _asInt(json['questionCount']),
        totalMarks: _asDouble(json['totalMarks']),
        timeLimitMinutes: _asInt(json['timeLimitMinutes']),
        negativeMarking: json['negativeMarking'] == true,
        correctMarks: _asDouble(json['correctMarks']),
        penalty: _asDouble(json['penalty']),
        attemptCount: _asInt(json['attemptCount']),
      );
}

/// A question as the hall sees it — never carrying `correct` or
/// `explanation`, because a hint during the paper would defeat the point.
class ExamQuestion {
  const ExamQuestion({
    required this.index,
    required this.question,
    required this.type,
    required this.options,
    required this.topic,
    required this.marks,
    required this.needsReview,
  });

  final int index;
  final String question;
  final String type;
  final List<String> options;
  final String topic;
  final double marks;
  final bool needsReview;

  bool get isChoice => options.length >= 2;

  factory ExamQuestion.fromJson(Map<String, dynamic> json) => ExamQuestion(
        index: _asInt(json['index']),
        question: '${json['question'] ?? ''}',
        type: '${json['type'] ?? 'mcq'}',
        options: _asStringList(json['options']),
        topic: '${json['topic'] ?? ''}',
        marks: _asDouble(json['marks']),
        needsReview: json['needsReview'] == true,
      );
}

/// One editable row of the upload-correction step.
class ExamDraftQuestion {
  ExamDraftQuestion({
    required this.question,
    required this.type,
    required List<String> options,
    required this.correct,
    required this.explanation,
    required this.topic,
    required this.needsReview,
  }) : options = List<String>.from(options);

  String question;
  String type;
  List<String> options;
  String correct;
  String explanation;
  String topic;
  bool needsReview;

  factory ExamDraftQuestion.fromJson(Map<String, dynamic> json) =>
      ExamDraftQuestion(
        question: '${json['question'] ?? ''}',
        type: '${json['type'] ?? 'mcq'}',
        options: _asStringList(json['options']),
        correct: '${json['correct'] ?? ''}',
        explanation: '${json['explanation'] ?? ''}',
        topic: '${json['topic'] ?? ''}',
        needsReview: json['needsReview'] == true,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question': question.trim(),
        'type': type,
        'options': options.map((option) => option.trim()).toList(),
        'correct': correct.trim(),
        'explanation': explanation.trim(),
        'topic': topic.trim(),
        'needsReview': needsReview,
      };

  /// Ready to be graded: text, an answer, and (for MCQs) two-plus options.
  bool get isComplete {
    final answer = correct.trim();
    if (question.trim().length < 4 || answer.isEmpty) return false;
    if (type == 'mcq') return options.where((o) => o.trim().isNotEmpty).length >= 2;
    return true;
  }

  /// A blank row of the spec 6.1 "manual input" editor — four option lines
  /// so the student can start typing straight away.
  factory ExamDraftQuestion.empty() => ExamDraftQuestion(
        question: '',
        type: 'mcq',
        options: <String>['', '', '', ''],
        correct: '',
        explanation: '',
        topic: '',
        needsReview: false,
      );
}

/// POST /api/exams/{id}/start response — everything the hall renders and
/// nothing it should not have (no answers, no explanations).
class ExamHall {
  const ExamHall({
    required this.attemptId,
    required this.examId,
    required this.title,
    required this.subject,
    required this.startedAt,
    required this.deadlineAt,
    required this.timeLimitSeconds,
    required this.totalMarks,
    required this.negativeMarking,
    required this.correctMarks,
    required this.penalty,
    required this.questions,
    this.allowPause = true,
    this.status = 'running',
    this.resumed = false,
    this.remainingSeconds = 0,
    this.savedAnswers = const <String>[],
    this.markedForReview = const <int>[],
  });

  final String attemptId;
  final String examId;
  final String title;
  final String subject;
  final DateTime startedAt;
  final DateTime deadlineAt;
  final int timeLimitSeconds;
  final double totalMarks;
  final bool negativeMarking;
  final double correctMarks;
  final double penalty;
  final List<ExamQuestion> questions;

  /// Phase 6 — the paper's optional pause setting (spec 6.4).
  final bool allowPause;

  /// "running" or "paused"; a resumed attempt also carries the answers the
  /// server kept for it, so a closed app never costs an hour of work.
  final String status;
  final bool resumed;
  final int remainingSeconds;
  final List<String> savedAnswers;
  final List<int> markedForReview;

  factory ExamHall.fromJson(Map<String, dynamic> json) => ExamHall(
        attemptId: '${json['attemptId'] ?? ''}',
        examId: '${json['examId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        subject: '${json['subject'] ?? ''}',
        startedAt: _asDateTime(json['startedAt']) ?? DateTime.now(),
        deadlineAt: _asDateTime(json['deadlineAt']) ?? DateTime.now(),
        timeLimitSeconds: _asInt(json['timeLimitSeconds']),
        totalMarks: _asDouble(json['totalMarks']),
        negativeMarking: json['negativeMarking'] == true,
        correctMarks: _asDouble(json['correctMarks']),
        penalty: _asDouble(json['penalty']),
        questions: _asMapList(json['questions'])
            .map(ExamQuestion.fromJson)
            .toList(),
        allowPause: json['allowPause'] != false,
        status: '${json['status'] ?? 'running'}',
        resumed: json['resumed'] == true,
        remainingSeconds: _asInt(json['remainingSeconds']),
        savedAnswers: _asStringList(json['answers']),
        markedForReview: _asIntList(json['markedForReview']),
      );
}

int _asInt(dynamic value) => value is num ? value.toInt() : 0;

double _asDouble(dynamic value) =>
    value is num ? value.toDouble() : (double.tryParse('$value') ?? 0);

List<String> _asStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value.map((item) => '$item').toList();
}

List<int> _asIntList(dynamic value) {
  if (value is! List) return const <int>[];
  return value
      .map((item) => item is num ? item.toInt() : int.tryParse('$item') ?? -1)
      .where((item) => item >= 0)
      .toList();
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

DateTime? _asDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
