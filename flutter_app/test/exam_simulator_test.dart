// Phase 3 - AI Real Exam Simulator, client side.
//
// What the client owes Phase 3:
//   * setup builds the paper (AI / uploaded / saved) and hands the exam id
//     to the hall;
//   * upload shows every extracted question so nothing enters a paper
//     unseen;
//   * the hall runs the clock, collects answers as option letters, and
//     submits (or auto-submits when time runs out);
//   * the result renders exactly what the server scored: score, weak
//     topics, mistakes with review dates, Ziku's plan, Academic Health.
//
// Everything networked is injected, so no test here opens a socket.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/exams/exam_models.dart';
import 'package:gochano/features/exams/exam_simulator_card.dart';
import 'package:gochano/features/exams/exam_ui.dart';
import 'package:gochano/features/exams/presentation/exam_hall_screen.dart';
import 'package:gochano/features/exams/presentation/exam_result_screen.dart';
import 'package:gochano/features/exams/presentation/exam_setup_screen.dart';
import 'package:gochano/features/exams/presentation/exam_upload_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The screens are long lists; a default 800x600 test surface only builds
/// the first screenful, so content tests open a taller one.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// A start payload shaped like the backend's `start_attempt`.
Map<String, dynamic> _hall({
  int questionCount = 3,
  Duration runFor = const Duration(minutes: 45),
  String attemptId = 'att_1',
}) =>
    {
      'attemptId': attemptId,
      'examId': 'exam_1',
      'title': 'Physics mock',
      'subject': 'Physics',
      'startedAt': DateTime.now().toIso8601String(),
      'deadlineAt': DateTime.now().add(runFor).toIso8601String(),
      'timeLimitSeconds': runFor.inSeconds,
      'totalMarks': 3.0,
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

/// The submit response (`_result_payload`).
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
      'timeSpentSeconds': 600,
      'timeLimitSeconds': 2700,
      'timeManagement': 'good',
      'timeManagementLabel': 'Good',
      'timeManagementDetail': 'Used 22% of the time - 0 unanswered',
      'topicScores': {'Optics': 66},
      'weakTopics': ['Optics'],
      'mistakeCount': 1,
      'mistakes': [
        {
          'index': 1,
          'topic': 'Optics',
          'question': 'Question 2?',
          'userAnswer': 'C',
          'correctAnswer': 'B',
          'type': 'concept',
          'explanation': 'Because Beta is the answer.',
          'reviewDates': [
            '2026-10-03',
            '2026-10-09',
            '2026-11-01',
          ],
        },
      ],
      'newMistakes': 1,
      'repeatedMistakes': 0,
      'pendingAnalysis': 1,
      'zikuPlan': {
        'subject': 'Physics',
        'headline': 'Three days to a clean paper',
        'days': [
          {'day': 1, 'focus': 'Review Optics', 'kind': 'review'},
          {'day': 2, 'focus': '20 MCQ on Optics', 'kind': 'practice'},
          {'day': 3, 'focus': 'Full mock', 'kind': 'test'},
        ],
        'daysRemaining': 5,
        'text': 'Three days to a clean paper.',
      },
      'zikuAnalysis': '',
      'quizId': 'quiz_1',
      'createdAt': null,
    };

/// The analysis payload: the result plus weak-topic actions, mistake types,
/// the live health read and Ziku's prompt.
Map<String, dynamic> _analysis({bool hasAi = false}) => {
      ..._result(),
      'weakTopicDetails': [
        {
          'topic': 'Optics',
          'accuracy': 66,
          'action': 'Solve 20 MCQ on Optics',
        },
      ],
      'mistakeTypes': [
        {'type': 'concept', 'label': 'Concept error', 'count': 1},
      ],
      'mistakesSaved': {
        'saved': 1,
        'new': 1,
        'repeated': 0,
        'pendingAnalysis': 1,
        'reviewDates': ['2026-10-03'],
      },
      'health': {
        'score': 76,
        'understandingDetail': '4 quizzes averaged 82%',
        'examReadinessDetail': '61% - 5 days out',
        'headline': 'Good - steady and in control.',
      },
      'rescue': null,
      'zikuPrompt': 'Analyse my Physics mock exam',
      'zikuAnalysis': hasAi ? 'Day 1: fix Optics. Day 2: practise.' : '',
      'hasAiAnalysis': hasAi,
    };

ExamSubmitFn _recordSubmit(
  void Function(
    String examId, {
    required String attemptId,
    required List<String> answers,
    int? timeSpentSeconds,
    List<int> markedForReview,
    bool withAiAnalysis,
  }) onCall,
) {
  return (
    String examId, {
    required String attemptId,
    required List<String> answers,
    int? timeSpentSeconds,
    List<int> markedForReview = const <int>[],
    bool withAiAnalysis = true,
  }) async {
    onCall(
      examId,
      attemptId: attemptId,
      answers: answers,
      timeSpentSeconds: timeSpentSeconds,
      markedForReview: markedForReview,
      withAiAnalysis: withAiAnalysis,
    );
    return _result();
  };
}

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Exam models and helpers', () {
    test('the clock never shows a negative time', () {
      expect(examClock(0), '00:00');
      expect(examClock(90), '01:30');
      expect(examClock(2700), '45:00');
      expect(examClock(3725), '1:02:05');
      expect(examClock(-5), '00:00');
      expect(examDurationLabel(600), '10 min');
      expect(examDurationLabel(3725), '1 h 2 min');
    });

    test('MCQ answers travel as bare letters', () {
      expect(examLetter(0), 'A');
      expect(examLetter(2), 'C');
      expect(examLetter(25), 'Z');
      expect(examLetter(40), 'Z'); // clamped, never past Z
    });

    test('a draft question is only complete with an answer', () {
      final draft = ExamDraftQuestion.fromJson(const {
        'question': 'What is light?',
        'type': 'mcq',
        'options': ['Wave', 'Particle', 'Sound', 'Heat'],
        'correct': 'A',
        'topic': 'Optics',
        'explanation': '',
        'needsReview': true,
      });
      expect(draft.isComplete, isTrue);
      expect(draft.toJson()['correct'], 'A');
      expect(draft.toJson()['type'], 'mcq');

      draft.correct = ' ';
      expect(draft.isComplete, isFalse, reason: 'no answer key, no exam');

      draft.type = 'short';
      draft.correct = 'A wave';
      expect(draft.isComplete, isTrue);
    });

    test('the hall model parses the deadline and the redacted questions', () {
      final hall = ExamHall.fromJson(_hall());
      expect(hall.attemptId, 'att_1');
      expect(hall.questions, hasLength(3));
      expect(hall.questions.first.options, hasLength(4));
      expect(
        hall.deadlineAt.isAfter(DateTime.now()),
        isTrue,
        reason: 'the countdown needs a future deadline',
      );
    });

    test('the redacted question model cannot carry an answer key', () {
      final source = _read('lib/features/exams/exam_models.dart');
      final model = source.substring(
        source.indexOf('class ExamQuestion'),
        source.indexOf('class ExamDraftQuestion'),
      );
      expect(model, contains('final List<String> options;'));
      expect(
        model.contains("'correct'"),
        isFalse,
        reason: 'the hall must never receive the answer key',
      );
      expect(model.contains('explanation'), isFalse);
    });
  });

  group('ApiService speaks the seven exam routes', () {
    final api = _read('lib/services/api_service.dart');

    test('every Phase 3 endpoint is registered exactly once', () {
      for (final route in const [
        "'/api/exams/create'",
        "'/api/exams/upload'",
        "'/api/exams'",
        "'/api/exams/\$examId'",
        "'/api/exams/\$examId/start'",
        "'/api/exams/\$examId/submit'",
        "'/api/exams/\$examId/analysis'",
      ]) {
        expect(api, contains(route), reason: 'missing $route');
      }
    });

    test('query parameters never live in the path literal', () {
      expect(api.contains('/api/exams/'), isTrue);
      for (final line in api.split('\n')) {
        if (!line.contains('_get(') && !line.contains('_post(')) continue;
        expect(
          line.contains('?'),
          isFalse,
          reason: 'query strings must go through `query:` - $line',
        );
      }
      expect(api, contains("'includeQuestions': '\$includeQuestions'"));
      expect(api, contains("'attemptId': ?attemptId"));
      expect(api, contains("'withAi': '\$withAi'"));
      expect(api, contains("'questionCount': '\$questionCount'"));
    });
  });

  group('Entry points', () {
    test('Home lists the simulator card in Study Mode', () {
      final home = _read('lib/features/home/presentation/home_screen.dart');
      expect(home, contains('const ExamSimulatorCard(),'));
      expect(home, contains("import '../../exams/exam_simulator_card.dart';"));
      expect(
        home.indexOf('const ExamSimulatorCard(),'),
        greaterThan(home.indexOf('if (mode == GochanoAppMode.study)')),
      );
    });

    test('Study carries an app-bar route into the setup screen', () {
      final study = _read('lib/features/study/presentation/study_screen.dart');
      expect(study, contains('ExamSetupScreen()'));
      expect(study, contains("import '../../exams/presentation/exam_setup_screen.dart';"));
    });
  });

  group('Setup screen', () {
    testWidgets('offers the three sources and the paper settings',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(_app(const ExamSetupScreen()));

      expect(find.text('Real Exam Simulator'), findsOneWidget);
      expect(find.text('Generate with AI'), findsOneWidget);
      expect(find.text('Upload a paper'), findsOneWidget);
      expect(find.text('Saved questions'), findsOneWidget);
      expect(find.text('Negative marking'), findsOneWidget);
      expect(find.text('Difficulty'), findsOneWidget);
      expect(find.text('Start exam'), findsOneWidget);
      // The answer key stays out of setup: it is not an exam question yet.
      expect(find.text('Answer key'), findsNothing);
    });

    testWidgets('creates an AI paper and opens the hall', (tester) async {
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
            submitFn: (
              String examId, {
              required String attemptId,
              required List<String> answers,
              int? timeSpentSeconds,
              List<int> markedForReview = const <int>[],
              bool withAiAnalysis = true,
            }) async =>
                _result(),
            analysisFn: (
              String examId, {
              String? attemptId,
              bool withAi = false,
            }) async =>
                _analysis(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Subject').first,
        'Physics',
      );
      await tester.pump();
      await tester.tap(find.text('Start exam'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!['source'], 'ai');
      expect(sent!['subject'], 'Physics');
      expect(sent!['questionCount'], 15);
      expect(sent!['timeLimitMinutes'], 45);
      expect(sent!['negativeMarking'], {
        'enabled': true,
        'penalty': 0.25,
      });
      expect(sent!.containsKey('questions'), isFalse);
      expect(started, ['exam_1']);

      // The hall is open: paper title, clock, navigator.
      expect(find.text('Physics mock'), findsOneWidget);
      expect(find.text('Question 1'), findsOneWidget);
      expect(find.text('Submit exam'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // cancel the hall timer
    });

    testWidgets('shows the server error instead of failing silently',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          ExamSetupScreen(
            createFn: (body) async =>
                throw Exception('failed host lookup'),
          ),
        ),
      );

      await tester.tap(find.text('Start exam'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No connection to Gochano'),
        findsOneWidget,
      );
    });

    testWidgets('upload source opens the extraction screen first',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(_app(const ExamSetupScreen()));

      await tester.tap(find.text('Upload a paper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start exam'));
      await tester.pumpAndSettle();

      expect(find.text('Extract questions'), findsOneWidget);
      expect(find.text('Choose a file'), findsOneWidget);
    });
  });

  group('Upload screen', () {
    testWidgets('shows every extracted question for correction',
        (tester) async {
      await _tallSurface(tester);
      String? pickedFile;

      await tester.pumpWidget(
        _app(
          ExamUploadScreen(
            pickFn: () async => ExamPickResult(
              name: 'physics.pdf',
              bytes: List<int>.filled(8, 1),
            ),
            uploadFn: ({
              required List<int> bytes,
              required String filename,
              String mimeType = '',
              String subject = '',
              int questionCount = 15,
            }) async {
              pickedFile = filename;
              return {
                'filename': filename,
                'textSource': 'pdf_text',
                'parser': 'line_parser',
                'questionCount': 3,
                'questions': [
                  for (var i = 0; i < 3; i++)
                    {
                      'question': 'Extracted ${i + 1}?',
                      'type': 'mcq',
                      'options': ['One', 'Two', 'Three', 'Four'],
                      'correct': 'A',
                      'topic': 'Optics',
                      'explanation': '',
                      'needsReview': i == 0,
                    },
                ],
                'needsReview': [0],
                'warnings': <String>[],
              };
            },
          ),
        ),
      );

      await tester.tap(find.text('Choose a file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extract questions'));
      await tester.pumpAndSettle();

      expect(pickedFile, 'physics.pdf');
      expect(find.textContaining('3 questions found'), findsOneWidget);
      expect(find.textContaining('3 ready'), findsOneWidget);
      expect(find.text('Extracted 1?'), findsOneWidget);
      expect(find.text('Use 3 questions'), findsOneWidget);

      // Every question is editable: open one and the answer key is visible.
      await tester.tap(find.text('Extracted 2?'));
      await tester.pumpAndSettle();
      expect(find.text('Answer key (A, B, C… or the answer)'), findsOneWidget);
    });

    testWidgets('pastes text when there is no file', (tester) async {
      await _tallSurface(tester);
      List<int>? uploadedBytes;
      String? uploadedName;

      await tester.pumpWidget(
        _app(
          ExamUploadScreen(
            uploadFn: ({
              required List<int> bytes,
              required String filename,
              String mimeType = '',
              String subject = '',
              int questionCount = 15,
            }) async {
              uploadedBytes = bytes;
              uploadedName = filename;
              return {
                'questionCount': 1,
                'questions': [
                  {
                    'question': 'Pasted question?',
                    'type': 'short',
                    'options': <String>[],
                    'correct': '42',
                    'topic': 'Math',
                    'explanation': '',
                    'needsReview': false,
                  },
                ],
                'needsReview': <String>[],
                'warnings': <String>[],
              };
            },
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Or paste the questions').first,
        '1. Pasted question?\nAnswer: 42',
      );
      await tester.pump();
      await tester.tap(find.text('Extract questions'));
      await tester.pumpAndSettle();

      expect(uploadedName, 'pasted.txt');
      expect(uploadedBytes, isNotNull);
      expect(uploadedBytes, isNotEmpty);
      expect(find.text('Use 1 questions'), findsOneWidget);
    });

    testWidgets('refuses to accept a question with no answer',
        (tester) async {
      await _tallSurface(tester);

      await tester.pumpWidget(
        _app(
          ExamUploadScreen(
            uploadFn: ({
              required List<int> bytes,
              required String filename,
              String mimeType = '',
              String subject = '',
              int questionCount = 15,
            }) async =>
                {
                  'questionCount': 1,
                  'questions': [
                    {
                      'question': 'Unanswered question?',
                      'type': 'mcq',
                      'options': ['One', 'Two'],
                      'correct': '  ',
                      'topic': '',
                      'explanation': '',
                      'needsReview': true,
                    },
                  ],
                  'needsReview': [0],
                  'warnings': <String>[],
                },
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Or paste the questions').first,
        '1. Unanswered question?',
      );
      await tester.pump();
      await tester.tap(find.text('Extract questions'));
      await tester.pumpAndSettle();

      expect(find.text('Use 1 questions'), findsOneWidget);
      await tester.tap(find.text('Use 1 questions'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('still need an answer'),
        findsOneWidget,
        reason: 'an unanswered draft must not reach the paper',
      );
    });

    testWidgets('hands the corrected questions back to setup',
        (tester) async {
      await _tallSurface(tester);
      List<ExamDraftQuestion>? accepted;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  accepted = await Navigator.of(context).push<
                    List<ExamDraftQuestion>
                  >(
                    MaterialPageRoute(
                      builder: (_) => ExamUploadScreen(
                        uploadFn: ({
                          required List<int> bytes,
                          required String filename,
                          String mimeType = '',
                          String subject = '',
                          int questionCount = 15,
                        }) async =>
                            {
                              'questionCount': 2,
                              'questions': [
                                for (var i = 0; i < 2; i++)
                                  {
                                    'question': 'Draft ${i + 1}?',
                                    'type': 'mcq',
                                    'options': ['A1', 'B1', 'C1', 'D1'],
                                    'correct': 'B',
                                    'topic': 'Optics',
                                    'explanation': '',
                                    'needsReview': false,
                                  },
                              ],
                              'needsReview': <String>[],
                              'warnings': <String>[],
                            },
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Or paste the questions').first,
        'paper',
      );
      await tester.pump();
      await tester.tap(find.text('Extract questions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use 2 questions'));
      await tester.pumpAndSettle();

      expect(accepted, isNotNull);
      expect(accepted, hasLength(2));
      expect(accepted!.first.correct, 'B');
      expect(accepted!.last.toJson()['options'], ['A1', 'B1', 'C1', 'D1']);
    });
  });

  group('Exam hall', () {
    testWidgets('runs the clock, collects letters and submits', (tester) async {
      await _tallSurface(tester);
      String? sentAttemptId;
      List<String>? sentAnswers;
      List<int>? sentFlags;
      int? sentSpent;

      await tester.pumpWidget(
        _app(
          ExamHallScreen(
            examId: 'exam_1',
            title: 'Physics mock',
            startFn: (examId) async => _hall(),
            submitFn: _recordSubmit(
              (
                String examId, {
                required String attemptId,
                required List<String> answers,
                int? timeSpentSeconds,
                List<int> markedForReview = const <int>[],
                bool withAiAnalysis = true,
              }) {
                sentAttemptId = attemptId;
                sentAnswers = answers;
                sentFlags = markedForReview;
                sentSpent = timeSpentSeconds;
              },
            ),
            analysisFn: (
              String examId, {
              String? attemptId,
              bool withAi = false,
            }) async =>
                _analysis(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Countdown from the server deadline.
      expect(
        find.textContaining(RegExp(r'^4[45]:\d\d$')),
        findsOneWidget,
      );
      expect(find.text('0 of 3 answered'), findsOneWidget);
      expect(find.text('Question 1'), findsOneWidget);

      // The redacted payload carries no answer key anywhere on screen.
      expect(find.text('Correct answer'), findsNothing);
      expect(find.text('Because Beta is the answer.'), findsNothing);

      // Answer question 1, flag question 2, move around.
      await tester.tap(find.text('A. Alpha'));
      await tester.pump();
      expect(find.text('1 of 3 answered'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Mark for review'));
      await tester.pump();
      expect(find.text('1 marked'), findsOneWidget);

      // Leave question 3 blank on purpose.
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Question 3'), findsOneWidget);

      // Back to question 1 to check the selection survived the round trip.
      await tester.tap(find.text('Previous'));
      await tester.pump();
      await tester.tap(find.text('Previous'));
      await tester.pump();

      await tester.tap(find.text('Submit exam'));
      await tester.pumpAndSettle();
      expect(find.text('Submit the paper?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('1 of 3 answered'),
        ),
        findsOneWidget,
        reason: 'the dialog must say what is still blank',
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(sentAttemptId, 'att_1');
      expect(sentAnswers, ['A', '', '']);
      expect(sentFlags, [1]);
      expect(sentSpent, isNotNull);
      expect(sentSpent! >= 0, isTrue);

      // The result screen took over.
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('9 / 15'), findsOneWidget);
    });

    testWidgets('auto-submits when the deadline passes', (tester) async {
      await _tallSurface(tester);
      var submitted = 0;

      await tester.pumpWidget(
        _app(
          ExamHallScreen(
            examId: 'exam_1',
            title: 'Physics mock',
            startFn: (examId) async =>
                _hall(runFor: const Duration(seconds: 2)),
            submitFn: _recordSubmit(
              (
                String examId, {
                required String attemptId,
                required List<String> answers,
                int? timeSpentSeconds,
                List<int> markedForReview = const <int>[],
                bool withAiAnalysis = true,
              }) =>
                  submitted += 1,
            ),
            analysisFn: (
              String examId, {
              String? attemptId,
              bool withAi = false,
            }) async =>
                _analysis(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(submitted, 1, reason: 'an expired clock still scores the paper');
      expect(find.text('Result'), findsOneWidget);
      expect(
        find.textContaining('Time ran out'),
        findsOneWidget,
        reason: 'the student has to know it was an auto-submit',
      );
    });

    testWidgets('reports a failed start instead of an empty room',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          ExamHallScreen(
            examId: 'exam_1',
            startFn: (examId) async =>
                throw Exception('attempt is already submitted'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Something went wrong'),
        findsOneWidget,
        reason: 'a failed start must surface the failure',
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Result screen', () {
    testWidgets('renders the score, weak topics, mistakes and the plan',
        (tester) async {
      await _tallSurface(tester);
      String? readAttemptId;

      await tester.pumpWidget(
        _app(
          ExamResultScreen(
            examId: 'exam_1',
            attemptId: 'att_1',
            result: _result(),
            analysisFn: (
              String examId, {
              String? attemptId,
              bool withAi = false,
            }) async {
              readAttemptId = attemptId;
              return _analysis();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(readAttemptId, 'att_1');
      expect(find.text('9 / 15'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);

      // Weak topics carry an action, not just a name.
      expect(find.text('Optics'), findsWidgets);
      expect(find.text('Solve 20 MCQ on Optics'), findsOneWidget);

      // Mistakes: what was answered, what was right, why, and when to revise.
      expect(find.text('Question 2?'), findsOneWidget);
      expect(find.text('Your answer'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('Because Beta is the answer.'), findsOneWidget);
      expect(find.text('2026-10-03'), findsOneWidget);
      expect(find.text('1 mistakes still waiting for AI analysis.'),
          findsOneWidget);

      // Ziku's deterministic plan ships even without the AI paragraph.
      expect(find.text('Three days to a clean paper'), findsOneWidget);
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Review Optics'), findsOneWidget);

      // The live health read ties the result back to Phase 2.
      expect(find.text('76 / 100'), findsOneWidget);
      expect(find.text('4 quizzes averaged 82%'), findsOneWidget);

      expect(find.text('Ask Ziku to analyse this paper'), findsOneWidget);
      expect(find.text('Open Academic Health'), findsOneWidget);
      expect(find.text('Open Learning Brain'), findsOneWidget);
    });

    testWidgets('generates Ziku\'s paragraph on demand, once',
        (tester) async {
      await _tallSurface(tester);
      final calls = <bool>[];

      await tester.pumpWidget(
        _app(
          ExamResultScreen(
            examId: 'exam_1',
            attemptId: 'att_1',
            analysisFn: (
              String examId, {
              String? attemptId,
              bool withAi = false,
            }) async {
              calls.add(withAi);
              return _analysis(hasAi: withAi);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, [false]);
      expect(find.text('Day 1: fix Optics. Day 2: practise.'), findsNothing);

      await tester.tap(find.text('Ask Ziku to analyse this paper'));
      await tester.pumpAndSettle();

      expect(calls, [false, true]);
      expect(
        find.text('Day 1: fix Optics. Day 2: practise.'),
        findsOneWidget,
      );
      expect(find.text('Ask Ziku to analyse this paper'), findsNothing);
    });

    testWidgets('reports an unreachable backend instead of a blank screen',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          ExamResultScreen(
            examId: 'exam_1',
            analysisFn: (
              String examId, {
              String? attemptId,
              bool withAi = false,
            }) async =>
                throw Exception('Connection refused'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No connection to Gochano'),
        findsOneWidget,
        reason: 'an unreachable backend must say so instead of blanking',
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Entry card', () {
    testWidgets('one tap reaches the setup screen', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _app(ExamSimulatorCard(openSetup: () => opened += 1)),
      );

      expect(find.text('Real Exam Simulator'), findsOneWidget);
      expect(
        find.textContaining('A full paper, a real timer, no hints.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Real Exam Simulator'));
      await tester.pump();

      expect(opened, 1);
    });
  });
}
