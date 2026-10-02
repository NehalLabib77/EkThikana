// Phase 6 — Ziku Real Exam Simulator Pro, client side.
//
// What the client owes Phase 6 on top of Phase 3:
//   * the builder takes a title, a "write your own" source and a pause
//     setting (spec 6.1);
//   * the hall saves answers, flags and remaining time while the paper
//     runs, pauses and resumes against the server deadline, and shows the
//     marks for a right and a wrong answer (spec 6.3/6.4);
//   * "My Exams" lists the student's own papers with the improvement line
//     and opens a result (spec 6.9);
//   * the result screen rebuilds the coach caches after a real submit
//     (spec 6.8).
//
// Everything networked is injected, so no test here opens a socket.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/exams/exam_models.dart';
import 'package:gochano/features/exams/presentation/exam_history_screen.dart';
import 'package:gochano/features/exams/presentation/exam_setup_screen.dart';
import 'package:gochano/features/exams/presentation/real_exam_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The screens are long lists; a default 800x600 test surface only builds
/// the first screenful, so content tests open a taller one.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Type into the field labelled [label] (the label renders inside the
/// TextField, so it can be found even while the field is empty).
Future<void> _type(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextField, label).first, value);
  await tester.pump();
}

/// A start/resume payload shaped like the backend's `start_attempt`, with
/// the Phase 6 control fields on top.
Map<String, dynamic> _hall({
  int questionCount = 4,
  Duration runFor = const Duration(minutes: 45),
  bool allowPause = true,
  bool resumed = false,
  DateTime? deadlineAt,
  List<String> savedAnswers = const <String>[],
  List<int> markedForReview = const <int>[],
}) =>
    {
      'attemptId': 'att_1',
      'examId': 'exam_1',
      'title': 'Physics mock',
      'subject': 'Physics',
      'startedAt': DateTime.now().toIso8601String(),
      'deadlineAt': (deadlineAt ?? DateTime.now().add(runFor))
          .toIso8601String(),
      'timeLimitSeconds': runFor.inSeconds,
      'allowPause': allowPause,
      'status': resumed ? 'paused' : 'running',
      'resumed': resumed,
      'remainingSeconds': runFor.inSeconds,
      'savedAnswers': savedAnswers,
      'markedForReview': markedForReview,
      'totalMarks': 4.0,
      'negativeMarking': true,
      'correctMarks': 1.0,
      'penalty': 0.25,
      'questions': [
        for (var i = 0; i < questionCount; i++)
          {
            'index': i,
            'question': 'Question ${i + 1}?',
            'type': 'mcq',
            'options': ['Alpha', 'Beta', 'Gamma', 'Delta'],
            'topic': 'Optics',
            'marks': 1.0,
            'needsReview': false,
          },
      ],
    };

/// A result payload shaped like `_result_payload`.
Map<String, dynamic> _result() => {
      'resultId': 'res_1',
      'examId': 'exam_1',
      'attemptId': 'att_1',
      'score': 9.0,
      'totalMarks': 15.0,
      'percentage': 60.0,
      'accuracy': 75.0,
      'correctCount': 2,
      'wrongCount': 1,
      'skippedCount': 0,
      'totalQuestions': 3,
      'timeManagement': 'good',
      'timeManagementLabel': 'Good',
      'timeManagementDetail': 'Used 22% of the time - 0 unanswered',
      'topicScores': {'Optics': 66},
      'weakTopics': ['Optics'],
      'mistakeCount': 1,
      'mistakes': <Map<String, dynamic>>[],
      'newMistakes': 1,
      'repeatedMistakes': 0,
      'pendingAnalysis': 1,
      'health': {'status': 'healthy', 'score': 82},
    };

/// A "My Exams" payload: two papers, newest first, +8% apart.
Map<String, dynamic> _history() => {
      'exams': [
        {
          'resultId': 'res_2',
          'examId': 'exam_1',
          'attemptId': 'att_2',
          'title': 'Physics Model Test',
          'subject': 'Physics',
          'score': 9.0,
          'totalMarks': 15.0,
          'percentage': 60.0,
          'accuracy': 75.0,
          'correctCount': 2,
          'wrongCount': 1,
          'skippedCount': 0,
          'totalQuestions': 3,
          'timeManagementLabel': 'Good',
          'mistakeCount': 1,
          'weakTopics': ['Optics'],
          'createdAt': '2026-09-30T10:00:00.000',
          'dayKey': '2026-09-30',
        },
        {
          'resultId': 'res_1',
          'examId': 'exam_0',
          'attemptId': 'att_1',
          'title': 'Chemistry Drill',
          'subject': 'Chemistry',
          'score': 7.8,
          'totalMarks': 15.0,
          'percentage': 52.0,
          'accuracy': 60.0,
          'correctCount': 2,
          'wrongCount': 2,
          'skippedCount': 1,
          'totalQuestions': 5,
          'timeManagementLabel': 'Rushed',
          'mistakeCount': 3,
          'weakTopics': ['Stoichiometry'],
          'createdAt': '2026-09-20T09:00:00.000',
          'dayKey': '2026-09-20',
        },
      ],
      'count': 2,
      'improvement': 8.0,
      'bestPercentage': 60.0,
      'averagePercentage': 56.0,
    };

ExamHistoryFn _historyFn() => ({int limit = 20}) async => _history();

void main() {
  group('Setup — Pro builder (spec 6.1)', () {
    testWidgets('titles a hand-written paper and sends title + pause',
        (tester) async {
      await _tallSurface(tester);
      Map<String, dynamic>? sent;
      final started = <String>[];

      await tester.pumpWidget(
        _app(
          ExamSetupScreen(
            createFn: (body) async {
              sent = body;
              return {'examId': 'exam_1', 'title': 'Physics mock'};
            },
            startFn: (examId) async {
              started.add(examId);
              return _hall();
            },
          ),
        ),
      );

      await _type(tester, 'Exam title (optional)', 'Physics Model Test');
      await _type(tester, 'Questions', '2');

      await tester.tap(find.text('Write your own'));
      await tester.pumpAndSettle();
      expect(find.text('Write the questions'), findsOneWidget);

      await tester.tap(find.text('Start exam'));
      await tester.pumpAndSettle();

      // The manual editor opens seeded with blank rows, not a file picker.
      expect(find.text('Write your own'), findsOneWidget);
      expect(find.text('2 questions found'), findsOneWidget);
      expect(find.text('0 ready'), findsOneWidget);

      await _type(tester, 'Question', 'What is 2 + 2?');
      await _type(tester, 'A. Option', 'Three');
      await _type(tester, 'B. Option', 'Four');
      await _type(tester, 'Answer key (A, B, C… or the answer)', 'B');

      await tester.tap(find.text('Empty question'));
      await tester.pumpAndSettle();
      await _type(tester, 'Question', 'Speed of light?');
      await _type(tester, 'A. Option', '3 x 10^8 m/s');
      await _type(tester, 'B. Option', '3 x 10^6 m/s');
      await _type(tester, 'Answer key (A, B, C… or the answer)', 'A');
      expect(find.text('2 ready'), findsOneWidget);

      await tester.tap(find.text('Use 2 questions'));
      await tester.pumpAndSettle();
      expect(find.text('Edit my 2 questions'), findsOneWidget);

      await tester.tap(find.text('Start exam'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!['title'], 'Physics Model Test');
      expect(sent!['allowPause'], true);
      expect(sent!['source'], 'manual');
      final questions = (sent!['questions'] as List).cast<Map>();
      expect(questions, hasLength(2));
      expect(questions.first['question'], 'What is 2 + 2?');
      expect(questions.first['correct'], 'B');
      expect(started, ['exam_1']);

      // The Pro hall opens for the new paper.
      expect(find.text('Physics mock'), findsOneWidget);
      expect(find.text('Question 1'), findsOneWidget);
      expect(find.text('Marks: +1'), findsOneWidget);
      expect(find.text('Wrong: -0.25'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // cancel the hall timer
    });

    testWidgets('turning pause off builds a one-sitting paper',
        (tester) async {
      await _tallSurface(tester);
      Map<String, dynamic>? sent;

      await tester.pumpWidget(
        _app(
          ExamSetupScreen(
            createFn: (body) async {
              sent = body;
              return {'examId': 'exam_1', 'title': 'Physics mock'};
            },
            startFn: (examId) async => _hall(allowPause: false),
          ),
        ),
      );

      await tester.ensureVisible(find.text('Not allowed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not allowed'));
      await tester.pump();

      await tester.tap(find.text('Start exam'));
      await tester.pumpAndSettle();

      expect(sent!['allowPause'], false);
      // A paper without pause offers exactly one way out: submit.
      expect(find.text('Pause exam'), findsNothing);
      expect(find.text('Submit exam'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // cancel the hall timer
    });

    testWidgets('the app bar opens My Exams', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(ExamSetupScreen(historyFn: _historyFn())),
      );

      await tester.tap(find.byTooltip('My exams'));
      await tester.pumpAndSettle();

      expect(find.text('My Exams'), findsOneWidget);
      expect(find.text('Physics Model Test'), findsOneWidget);
      expect(find.text('+8%'), findsOneWidget);
    });
  });

  group('Exam hall — Pro controls (spec 6.3/6.4)', () {
    testWidgets('saves answers, flags and remaining time while it runs',
        (tester) async {
      await _tallSurface(tester);
      final saved = <Map<String, dynamic>>[];

      await tester.pumpWidget(
        _app(
          RealExamScreen(
            examId: 'exam_1',
            title: 'Physics mock',
            startFn: (examId) async => _hall(questionCount: 4),
            saveFn: (
              String examId, {
              required String attemptId,
              required List<String> answers,
              List<int> markedForReview = const <int>[],
              int? remainingSeconds,
            }) async {
              saved.add({
                'attemptId': attemptId,
                'answers': answers,
                'markedForReview': markedForReview,
                'remainingSeconds': remainingSeconds,
              });
              return {'saved': true};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Spec 6.3: marks on screen, position on screen, no answer key.
      expect(find.text('Marks: +1'), findsOneWidget);
      expect(find.text('Wrong: -0.25'), findsOneWidget);
      expect(find.text('Question 1 / 4'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsOneWidget);
      expect(find.text('0 of 4 answered'), findsOneWidget);
      expect(find.text('Correct answer'), findsNothing);

      await tester.tap(find.text('A. Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 4 answered'), findsOneWidget);
      expect(saved, isNotEmpty);
      expect(saved.last['attemptId'], 'att_1');
      expect(saved.last['answers'], ['A', '', '', '']);
      final remaining = saved.last['remainingSeconds'] as int;
      expect(remaining, inInclusiveRange(2600, 2700));

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark for review'));
      await tester.pumpAndSettle();
      expect(find.text('1 marked'), findsOneWidget);
      expect(saved.last['markedForReview'], [1]);

      await tester.pumpWidget(const SizedBox()); // cancel the hall timer
    });

    testWidgets('pauses the clock and resumes from the server deadline',
        (tester) async {
      await _tallSurface(tester);
      final paused = <int>[];
      final resumed = <String?>[];
      var resumeCalls = 0;

      await tester.pumpWidget(
        _app(
          RealExamScreen(
            examId: 'exam_1',
            title: 'Physics mock',
            startFn: (examId) async => _hall(),
            saveFn: (
              String examId, {
              required String attemptId,
              required List<String> answers,
              List<int> markedForReview = const <int>[],
              int? remainingSeconds,
            }) async =>
                {'saved': true},
            pauseFn: (
              String examId, {
              required String attemptId,
              int? remainingSeconds,
            }) async {
              paused.add(remainingSeconds ?? -1);
              return {'status': 'paused'};
            },
            resumeFn: (String examId, {String? attemptId}) async {
              resumeCalls += 1;
              resumed.add(attemptId);
              return attemptId == null
                  // Nothing to resume on the first open: fall through to a
                  // fresh start (the 404 contract, expressed with a payload).
                  ? _hall()
                  : _hall(
                      runFor: const Duration(minutes: 30),
                      resumed: true,
                    );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(resumeCalls, 1, reason: 'the first open asks for a resume');
      expect(resumed, [null], reason: 'with no attempt to resume yet');

      final before = find.textContaining(RegExp(r'^\d\d:\d\d$'));
      expect(before, findsOneWidget);

      await tester.tap(find.text('Pause exam'));
      await tester.pumpAndSettle();

      expect(paused, hasLength(1));
      expect(paused.single, inInclusiveRange(2600, 2700));
      expect(
        find.text('Exam paused - the clock is stopped.'),
        findsOneWidget,
      );
      expect(find.text('Resume exam'), findsOneWidget);
      expect(find.text('Pause exam'), findsNothing);

      // The clock is frozen while paused.
      final frozen =
          tester.widget<Text>(before).data;
      await tester.pump(const Duration(seconds: 3));
      expect(tester.widget<Text>(before).data, frozen);

      await tester.tap(find.text('Resume exam'));
      await tester.pumpAndSettle();

      expect(resumeCalls, 2);
      expect(resumed, [null, 'att_1']);
      expect(find.text('Exam paused - the clock is stopped.'), findsNothing);
      expect(find.text('Resume exam'), findsNothing);
      expect(find.text('Pause exam'), findsOneWidget);
      // The server rewrote the deadline to ~30 minutes from now.
      expect(
        find.textContaining(RegExp(r'^(29:5\d|30:00)$')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox()); // cancel the hall timer
    });

    testWidgets('the redacted start payload still hides every answer',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          RealExamScreen(
            examId: 'exam_1',
            title: 'Physics mock',
            startFn: (examId) async => _hall(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Because Beta is the answer.'), findsNothing);
      expect(find.text('Correct answer'), findsNothing);
      expect(find.textContaining('explanation'), findsNothing);

      await tester.pumpWidget(const SizedBox()); // cancel the hall timer
    });
  });

  group('My Exams (spec 6.9)', () {
    testWidgets('lists the student\'s papers with the improvement line',
        (tester) async {
      await _tallSurface(tester);

      await tester.pumpWidget(
        _app(
          ExamHistoryScreen(
            historyFn: _historyFn(),
            resultFn: (String examId, {String? attemptId}) async =>
                _result(),
            analysisFn: (
              String examId, {
              String? attemptId,
              bool withAi = false,
            }) async =>
                _result(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Exams'), findsOneWidget);
      expect(find.text('Physics Model Test'), findsOneWidget);
      expect(find.text('Chemistry Drill'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('52%'), findsOneWidget);
      expect(find.textContaining('2026-09-30'), findsOneWidget);
      expect(find.text('+8%'), findsOneWidget);
      expect(find.text('56%'), findsOneWidget);

      // A paper opens its result.
      await tester.tap(find.text('Physics Model Test'));
      await tester.pumpAndSettle();
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('9 / 15'), findsOneWidget);
    });

    testWidgets('shares a paper by code without sharing any marks',
        (tester) async {
      await _tallSurface(tester);
      String? sharedExamId;
      bool? sharedFlag;

      await tester.pumpWidget(
        _app(
          ExamHistoryScreen(
            historyFn: _historyFn(),
            shareFn: (String examId, {required bool share}) async {
              sharedExamId = examId;
              sharedFlag = share;
              return {
                'examId': examId,
                'shareCode': 'X7K9P2mQ',
                'shared': true,
                'visibility': 'link',
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share paper'));
      await tester.pumpAndSettle();

      expect(sharedExamId, 'exam_1');
      expect(sharedFlag, isTrue);
      expect(find.text('X7K9P2mQ'), findsOneWidget);
      expect(
        find.textContaining('Your scores stay with you'),
        findsOneWidget,
        reason: 'the privacy contract is stated next to the code',
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('an empty history explains itself instead of showing nothing',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          ExamHistoryScreen(
            historyFn: ({int limit = 20}) async => {
              'exams': <Map<String, dynamic>>[],
              'count': 0,
              'improvement': null,
              'bestPercentage': 0.0,
              'averagePercentage': 0.0,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No exams yet'), findsOneWidget);
      expect(find.text('Start an exam'), findsOneWidget);
    });
  });

  group('Source contracts (Phase 6)', () {
    test('the result screen rebuilds the coach caches after a real submit',
        () {
      final source =
          _read('lib/features/exams/presentation/exam_result_screen.dart');
      expect(source, contains('coachRecalculate'));
      expect(source, contains('_recalcCoach'));
      // Real backend only: an injected analysis seam means a test or an
      // offline replay, never a fresh coaching payload.
      expect(source, contains('widget.analysisFn != null'));
    });

    test('the Pro hall shows marks but never carries an answer key', () {
      final source =
          _read('lib/features/exams/presentation/real_exam_screen.dart');
      expect(source, contains('Marks: +'));
      expect(source, contains('Wrong: -'));
      expect(source, contains('ApiService.saveExamProgress'));
      expect(source, contains('ApiService.pauseExam'));
      expect(source, isNot(contains('.explanation')));
      expect(source, isNot(contains('zikuPrompt')));
      expect(source, isNot(contains('withAi:')));
    });

    test('the Phase 6 client routes keep the no-query-string discipline',
        () {
      final api = _read('lib/services/api_service.dart');
      expect(api, contains("'/api/exams/history'"));
      expect(api, contains("'/api/exams/\$examId/save'"));
      expect(api, contains("'/api/exams/\$examId/pause'"));
      expect(api, contains("'/api/exams/\$examId/resume'"));
      expect(api, contains("'/api/exams/\$examId/share'"));
      expect(api, contains("'/api/exams/\$examId/result'"));
      for (final line in const LineSplitter().convert(api)) {
        if (line.contains('_get(') || line.contains('_post(')) {
          expect(
            line.contains('?'),
            isFalse,
            reason: 'a query string on a request line: $line',
          );
        }
      }
    });
  });
}
