// Phase 1 — AI Mistake Memory, client side.
//
// Three things the client owes Phase 1:
//   * Profile shows "My Learning Brain" for students only;
//   * the quiz result screen surfaces what the save recorded and offers the
//     one batched explanation call;
//   * ApiService speaks exactly the four routes the backend registered.
//
// Everything that touches the network is either injected (save / analyze) or
// deliberately unreachable (no API base URL in tests), so no test here opens
// a socket.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/profile/presentation/learning_brain_card.dart';
import 'package:gochano/features/profile/presentation/learning_brain_screen.dart';
import 'package:gochano/features/study/presentation/ai/quiz_result_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

List<Map<String, dynamic>> get _questions => [
  {'question': 'What causes Rayleigh scattering?', 'correct': 'B'},
];

/// A save response shaped like the backend's `quiz_save_result`.
Map<String, dynamic> _saved({
  int mistakeCount = 0,
  int newMistakes = 0,
  int pendingAnalysis = 0,
}) => {
  'success': true,
  'mistakeCount': mistakeCount,
  'newMistakes': newMistakes,
  'repeatedMistakes': 0,
  'pendingAnalysis': pendingAnalysis,
};

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Profile — My Learning Brain entry', () {
    final profileSource = _read(
      'lib/features/profile/presentation/profile_screen.dart',
    );

    test('card renders on Profile, gated to the student role', () {
      expect(
        profileSource,
        contains("import 'learning_brain_card.dart';"),
        reason: 'Profile must import the Phase 1 card',
      );
      expect(
        profileSource,
        contains('const LearningBrainCard()'),
        reason: 'the card has to be on the Profile body',
      );
      expect(
        profileSource,
        contains("if (role == 'student')"),
        reason: 'the mistake memory is the student who made the mistakes',
      );
    });

    test('navigation and data loading live outside profile_screen', () {
      expect(
        profileSource.contains('LearningBrainScreen('),
        isFalse,
        reason: 'profile_screen stays a settings list; the screen opens '
            'from the card',
      );
      final cardSource = _read(
        'lib/features/profile/presentation/learning_brain_card.dart',
      );
      expect(cardSource, contains('const LearningBrainScreen()'));
      expect(cardSource, contains('ApiService.getLearningBrain'));
    });

    testWidgets('card shows a retry message when the backend is unreachable',
        (tester) async {
      await tester.pumpWidget(_app(const LearningBrainCard()));
      await tester.pumpAndSettle();

      expect(find.text('My Learning Brain'), findsOneWidget);
      expect(
        find.textContaining("Couldn't load right now"),
        findsOneWidget,
        reason: 'a failed read must say so instead of showing a blank card',
      );
    });
  });

  group('Brain screen — failure path', () {
    testWidgets('reports the error and offers a retry', (tester) async {
      await tester.pumpWidget(_app(const LearningBrainScreen()));
      await tester.pumpAndSettle();

      expect(find.text('My Learning Brain'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Quiz result — mistake feedback', () {
    testWidgets('shows what was saved when the backend recorded mistakes',
        (tester) async {
      await tester.pumpWidget(
        _app(
          QuizResultScreen(
            questions: _questions,
            userAnswers: const ['B'],
            correctAnswers: const ['B'],
            difficulty: 'medium',
            saveResultFn: ({
              required questions,
              required userAnswers,
              required correctAnswers,
              required score,
              required topicScores,
              required subjectId,
              required materialId,
              required difficulty,
              required timeSpentSeconds,
            }) async => _saved(mistakeCount: 3, newMistakes: 3),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved to My Learning Brain'), findsOneWidget);
      expect(find.textContaining('3 wrong answers kept'), findsOneWidget);
      // Nothing pending → no button that would do nothing.
      expect(find.text('Explain with Ziku'), findsNothing);
    });

    testWidgets('offers the batched analysis when mistakes are pending',
        (tester) async {
      var analysed = 0;
      await tester.pumpWidget(
        _app(
          QuizResultScreen(
            questions: _questions,
            userAnswers: const ['b'],
            correctAnswers: const ['B'],
            difficulty: 'medium',
            saveResultFn: ({
              required questions,
              required userAnswers,
              required correctAnswers,
              required score,
              required topicScores,
              required subjectId,
              required materialId,
              required difficulty,
              required timeSpentSeconds,
            }) async => _saved(
              mistakeCount: 1,
              newMistakes: 1,
              pendingAnalysis: 2,
            ),
            analyzeFn: () async {
              analysed++;
              return {'analyzed': 2, 'pending': 0, 'failed': 0, 'status': 'ok'};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Explain with Ziku'), findsOneWidget);

      await tester.tap(find.text('Explain with Ziku'));
      await tester.pumpAndSettle();

      expect(analysed, 1, reason: 'one batch, one call');
      expect(find.text('Ziku explained 2 mistakes.'), findsOneWidget);
      expect(
        find.text('Explain with Ziku'),
        findsNothing,
        reason: 'nothing left to explain once the batch came back',
      );
    });

    testWidgets('a save without mistake counts adds no new section',
        (tester) async {
      await tester.pumpWidget(
        _app(
          QuizResultScreen(
            questions: _questions,
            userAnswers: const ['B'],
            correctAnswers: const ['B'],
            difficulty: 'medium',
            saveResultFn: ({
              required questions,
              required userAnswers,
              required correctAnswers,
              required score,
              required topicScores,
              required subjectId,
              required materialId,
              required difficulty,
              required timeSpentSeconds,
            }) async => {'success': true},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved to My Learning Brain'), findsNothing);
      expect(find.text('Explain with Ziku'), findsNothing);
    });

    testWidgets('a failing analysis is shown, not swallowed', (tester) async {
      await tester.pumpWidget(
        _app(
          QuizResultScreen(
            questions: _questions,
            userAnswers: const ['B'],
            correctAnswers: const ['B'],
            difficulty: 'medium',
            saveResultFn: ({
              required questions,
              required userAnswers,
              required correctAnswers,
              required score,
              required topicScores,
              required subjectId,
              required materialId,
              required difficulty,
              required timeSpentSeconds,
            }) async => _saved(mistakeCount: 1, pendingAnalysis: 1),
            analyzeFn: () async => throw Exception('quota reached'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explain with Ziku'));
      await tester.pumpAndSettle();

      expect(find.textContaining('quota reached'), findsOneWidget);
      expect(find.text('Saved to My Learning Brain'), findsOneWidget);
    });
  });

  group('ApiService — mistake memory routes', () {
    final api = _read('lib/services/api_service.dart');

    test('exposes all four backend routes', () {
      expect(api, contains("'/api/ai/mistakes'"));
      expect(api, contains("'/api/ai/mistakes/brain'"));
      expect(api, contains("'/api/ai/mistakes/analyze'"));
      expect(api, contains("'/api/ai/mistakes/\$mistakeId/review'"));
    });

    test('no route carries a query string inside the path literal', () {
      expect(api, isNot(contains('/api/ai/mistakes?')));
      expect(
        api,
        isNot(contains('quiz/history?')),
        reason: 'the API contract test normalises paths without queries',
      );
      expect(api, isNot(contains('weak-topics?')));
    });

    test('queries are passed as query parameters', () {
      expect(api, contains("query: {'status': status, 'limit': '\$limit'}"));
      expect(api, contains("query: {'limit': '\$limit'}"));
    });
  });

  group('AI usage counter', () {
    test('counts mistake analyses without calling them revisions', () {
      final usage = _read(
        'lib/features/profile/presentation/ai_usage_screen.dart',
      );
      expect(usage, contains("count('mistake_analyses')"));
      expect(usage.toLowerCase(), isNot(contains('revision')));
    });
  });
}
