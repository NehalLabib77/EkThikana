// Phase 2 — AI Academic Health Score, client side.
//
// What the client owes Phase 2:
//   * Profile shows "My Academic Health" for students only;
//   * the screen explains the 0-100 score, its four parts, weak topics and
//     the merged health + Ziku advice;
//   * ApiService speaks exactly the three routes the backend registered.
//
// Everything networked is injected, so no test here opens a socket.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/profile/presentation/academic_health_card.dart';
import 'package:gochano/features/profile/presentation/academic_health_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The screen is one long list; a default 800x600 test surface only builds
/// the first screenful, so content tests open a taller one.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// A payload shaped like the backend's `get_academic_health`.
Map<String, dynamic> _health({
  bool hasData = true,
  int score = 76,
  String grade = 'good',
  String headline = 'Good — steady and in control.',
}) => {
  'score': score,
  'grade': grade,
  'headline': headline,
  'hasData': hasData,
  'generatedAt': '2026-10-02T00:00:00Z',
  'dayKey': '2026-10-02',
  'trend': {'direction': 'up', 'delta': 4, 'previousScore': 72},
  'metrics': [
    {
      'key': 'consistency',
      'label': 'Consistency',
      'weight': 0.25,
      'score': 60.0,
      'available': true,
      'detail': '3 of 7 days · 95 min today',
    },
    {
      'key': 'understanding',
      'label': 'Understanding',
      'weight': 0.30,
      'score': 82.5,
      'available': true,
      'detail': '4 quizzes averaged 82%',
    },
    {
      'key': 'revision',
      'label': 'Revision',
      'weight': 0.25,
      'score': 70.0,
      'available': true,
      'detail': '2 mistakes due · 1 repeated',
    },
    {
      'key': 'examReadiness',
      'label': 'Exam readiness',
      'weight': 0.20,
      'score': null,
      'available': false,
      'detail': 'Signal unavailable',
    },
  ],
  'signals': {
    'quizzes': {'total': 4, 'recentAverage': 82},
    'study': {
      'hasData': true,
      'studyDays': 3,
      'weekMinutes': 240,
      'todayMinutes': 95,
      'todaySessions': 2,
      'averageFocusScore': 88,
    },
    'mistakes': {'total': 5, 'due': 2, 'repeated': 1},
    'tasks': {'open': 3, 'overdue': 1, 'dueSoon': 2},
    'exam': null,
    'ai': {'mistakeAnalyses': 1, 'chatMessages': 4},
  },
  'weakAreas': [
    {
      'topic': 'Networking',
      'quizAverage': 44,
      'priority': 'high',
      'action': 'Averaging 44% in Networking — re-read the rules, then quiz again.',
      'mistakes': 3,
      'due': 2,
    },
  ],
  'recommendations': [
    {
      'title': 'Revise Networking',
      'reason': '2 mistakes due — revise before the next quiz.',
      'priority': 'high',
      'source': 'health',
    },
  ],
  'coverage': ['consistency', 'understanding', 'revision'],
  'missing': ['examReadiness'],
};

Map<String, dynamic> _history() => {
  'days': 7,
  'count': 3,
  'history': [
    {'dayKey': '2026-10-01', 'score': 72, 'grade': 'good'},
    {'dayKey': '2026-10-02', 'score': 76, 'grade': 'good'},
  ],
};

Map<String, dynamic> _advice() => {
  'recommendations': [
    {
      'title': 'Revise Networking',
      'reason': '2 mistakes due — revise before the next quiz.',
      'priority': 'high',
      'source': 'health',
    },
    {
      'title': 'Take one quiz today',
      'reason': 'Understanding has no fresh attempt.',
      'priority': 'medium',
      'source': 'ai',
    },
  ],
  'count': 2,
  'healthCount': 1,
  'aiCount': 1,
};

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Profile — My Academic Health entry', () {
    final profileSource = _read(
      'lib/features/profile/presentation/profile_screen.dart',
    );

    test('card renders on Profile, gated to the student role', () {
      expect(
        profileSource,
        contains("import 'academic_health_card.dart';"),
        reason: 'Profile must import the Phase 2 card',
      );
      expect(
        profileSource,
        contains('const AcademicHealthCard()'),
        reason: 'the card has to be on the Profile body',
      );
      expect(
        profileSource,
        contains("if (role == 'student')"),
        reason: 'the health score is the student who produced it',
      );
    });

    test('navigation and data loading live outside profile_screen', () {
      expect(
        profileSource.contains('AcademicHealthScreen('),
        isFalse,
        reason: 'profile_screen stays a settings list; the screen opens '
            'from the card',
      );
      final cardSource = _read(
        'lib/features/profile/presentation/academic_health_card.dart',
      );
      expect(cardSource, contains('AcademicHealthScreen('));
      expect(cardSource, contains('ApiService.getAcademicHealth'));
    });

    testWidgets('card reports an unreachable backend instead of going blank',
        (tester) async {
      await tester.pumpWidget(_app(const AcademicHealthCard()));
      await tester.pumpAndSettle();

      expect(find.text('My Academic Health'), findsOneWidget);
      expect(
        find.textContaining("Couldn't load right now"),
        findsOneWidget,
        reason: 'a failed read must say so instead of showing a blank card',
      );
    });

    testWidgets('card shows the score and headline when the read succeeds',
        (tester) async {
      await tester.pumpWidget(
        _app(AcademicHealthCard(healthFn: () async => _health())),
      );
      await tester.pumpAndSettle();

      expect(find.text('76'), findsOneWidget);
      expect(find.text('Good — steady and in control.'), findsOneWidget);
      expect(find.text('Improving'), findsOneWidget);
    });
  });

  group('Academic Health screen', () {
    testWidgets('reports the error and offers a retry', (tester) async {
      await tester.pumpWidget(
        _app(
          AcademicHealthScreen(
            healthFn: () async => throw Exception('backend is down'),
            recommendationsFn: () async => _advice(),
            historyFn: () async => _history(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Academic Health'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('explains the score, its parts, weak topics and advice',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          AcademicHealthScreen(
            healthFn: () async => _health(),
            recommendationsFn: () async => _advice(),
            historyFn: () async => _history(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('76'), findsOneWidget);
      expect(
        find.text('Good — steady and in control.'),
        findsOneWidget,
      );
      expect(find.text('+4 since yesterday'), findsOneWidget);
      expect(find.text('What the score is made of'), findsOneWidget);
      expect(find.text('Consistency'), findsOneWidget);
      expect(find.text('Exam readiness'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget);
      expect(find.text('Topics to strengthen'), findsOneWidget);
      expect(find.text('Networking'), findsOneWidget);
      expect(find.text('Recommended next'), findsOneWidget);
      expect(find.text('Take one quiz today'), findsOneWidget);
      expect(find.text('Ask Ziku'), findsOneWidget);
      expect(find.text('Open Ziku'), findsOneWidget);
      expect(find.text('Recent scores'), findsOneWidget);
      expect(find.text('72 → 76 over 2 days'), findsOneWidget);
    });

    testWidgets('an empty profile asks for one signal, not a zero score',
        (tester) async {
      await tester.pumpWidget(
        _app(
          AcademicHealthScreen(
            healthFn: () async => _health(
              hasData: false,
              score: 0,
              grade: 'no_data',
              headline:
                  'Not enough data yet — take a quiz or start a study session.',
            ),
            recommendationsFn: () async => _advice(),
            historyFn: () async => _history(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(find.text('What the score is made of'), findsNothing);
    });

    testWidgets('pull-to-refresh re-reads the payload', (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        _app(
          AcademicHealthScreen(
            healthFn: () async {
              reads++;
              return _health();
            },
            recommendationsFn: () async => _advice(),
            historyFn: () async => _history(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);

      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(reads, 2, reason: 'refresh must hit the backend again');
    });
  });

  group('Ziku hand-off', () {
    test('the weakest topic beats the generic advice', () {
      final question = academicHealthZikuQuestion(weakTopic: 'Networking');
      expect(question, contains('Networking'));
      expect(question, contains('revise'));
    });

    test('falls back to the first recommendation, then to a default', () {
      expect(
        academicHealthZikuQuestion(recommendation: 'Revise Networking'),
        'Revise Networking',
      );
      expect(academicHealthZikuQuestion(), isNotEmpty);
      expect(
        academicHealthZikuQuestion(weakTopic: '   ', recommendation: ' '),
        isNotEmpty,
        reason: 'blank inputs must still produce something to ask',
      );
    });
  });

  group('ApiService — academic health routes', () {
    final api = _read('lib/services/api_service.dart');

    test('exposes all three backend routes', () {
      expect(api, contains("'/api/ai/academic-health'"));
      expect(api, contains("'/api/ai/academic-health/history'"));
      expect(api, contains("'/api/ai/academic-health/recommendations'"));
    });

    test('no route carries a query string inside the path literal', () {
      expect(api, isNot(contains('/api/ai/academic-health?')));
      expect(api, isNot(contains('academic-health/history?')));
      expect(api, isNot(contains('academic-health/recommendations?')));
    });

    test('queries are passed as query parameters', () {
      expect(api, contains("query: {'days': '\$days'}"));
    });
  });
}
