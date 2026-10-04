// Phase 4 — Ziku, the personal study coach, client side.
//
// What the client owes Phase 4:
//   * Home (study mode) shows a coach card: greeting, health, today's priority
//     and the mission, with one button into the dashboard;
//   * the dashboard reads profile + daily + weekly and renders them in the
//     order the coach produces them — nothing is recomputed here;
//   * every mission step that has a real destination goes there, and a step
//     whose destination does not exist yet shows no button at all;
//   * a failed weekly narrative (the only AI-authored part) degrades inline.
//
// Every reader is injected, so no test here opens a socket.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/page_route.dart';
import 'package:gochano/features/profile/presentation/learning_brain_screen.dart';
import 'package:gochano/features/study/presentation/ai/quiz_generator_screen.dart';
import 'package:gochano/features/study/presentation/focus/focus_session_screen.dart';
import 'package:gochano/features/study/presentation/planner/coach_dashboard_screen.dart';
import 'package:gochano/features/study/presentation/planner/ziku_coach_card.dart';
import 'package:gochano/shared/widgets/gochano_controls.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The dashboard is one long list; a default 800x600 surface only builds the
/// first screenful, so content tests open a taller one.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// A payload shaped like `GET /api/coach/daily`.
Map<String, dynamic> _brief({
  bool hasData = true,
  int score = 82,
  Map<String, dynamic>? priority,
  String? why,
  List<Map<String, dynamic>> mission = const [],
  Map<String, dynamic>? exam,
}) => {
  'dayKey': '2026-10-02',
  'greetingKey': 'morning',
  'greeting': 'Good Morning',
  'healthScore': score,
  'hasData': hasData,
  'priority': priority,
  'why':
      why ??
      (priority == null
          ? 'No urgent gaps today - keep the streak going with a focus session.'
          : '${priority['why']}'),
  'mission': mission,
  'missionCount': mission.length,
  'exam': exam,
  'generatedAt': '2026-10-02T00:00:00Z',
  'cached': false,
};

const Map<String, dynamic> _physicsExam = {
  'title': 'Physics Final',
  'examDate': '2026-10-07',
  'daysRemaining': 5,
};

const Map<String, dynamic> _opticsPriority = {
  'topic': 'Optics',
  'priority': 'high',
  'why': 'Optics is your weakest topic based on recent mistakes.',
  'reasons': ['exam in 5 day(s)', '1 repeated mistake(s)', 'quiz average 40%'],
  'mistakes': 6,
  'occurrences': 6,
  'repeated': 1,
  'due': 2,
  'quizAverage': 40,
};

const List<Map<String, dynamic>> _mission = [
  {
    'key': 'review',
    'action': 'review',
    'title': 'Review Optics',
    'detail': 'Re-read the concept you missed, then redo the question.',
    'minutes': 20,
    'target': 'Optics',
    'priority': 'high',
  },
  {
    'key': 'quiz',
    'action': 'quiz',
    'title': 'Solve 20 MCQ on Optics',
    'detail':
        'One short set is enough - accuracy matters more than volume today.',
    'minutes': 25,
    'count': 20,
    'target': 'Optics',
    'priority': 'high',
  },
  {
    'key': 'focus',
    'action': 'focus',
    'title': 'Complete a 25 minute focus session',
    'detail': 'No interruptions - one block, one subject.',
    'minutes': 25,
  },
];

/// A payload shaped like `GET /api/coach/profile`.
Map<String, dynamic> _profile({bool hasData = true}) => {
  'student': 'Rafi',
  'dayKey': '2026-10-02',
  'hasData': hasData,
  'healthScore': 76,
  'healthGrade': 'good',
  'healthHeadline': 'Good — steady and in control.',
  'trend': {'direction': 'up', 'delta': 4, 'previousScore': 72},
  'weakTopics': [
    {
      'topic': 'Optics',
      'quizAverage': 40,
      'mistakes': 6,
      'occurrences': 6,
      'repeated': 1,
      'due': 2,
      'priority': 'high',
      'action': 'Re-read the concept, then quiz again.',
    },
  ],
  'strongTopics': [
    {'topic': 'Networking', 'averageScore': 88, 'attempts': 3},
  ],
  'repeatedMistakes': 1,
  'revisionDue': 2,
  'totalMistakes': 6,
  'quizAverage': 71,
  'averageFocusTime': 80,
  'studyPattern': {
    'weekMinutes': 240,
    'studyDays': 3,
    'todayMinutes': 95,
    'averageFocusScore': 88,
    'bySubjectMinutes': {'Physics': 120},
  },
  'examReadiness': 72,
  'upcomingExam': {..._physicsExam, 'sessionId': 'session-1'},
  'practiceExams': {},
  'generatedAt': '2026-10-02T00:00:00Z',
  'cached': false,
};

/// A payload shaped like `GET /api/coach/weekly-report`.
Map<String, dynamic> _weekly({bool aiGenerated = true}) => {
  'weekKey': '2026-W40',
  'weekStart': '2026-09-28',
  'studyMinutes': 240,
  'studyDays': 3,
  'score': 76,
  'previousScore': 72,
  'scoreDelta': 4,
  'improvement': [
    {
      'key': 'understanding',
      'label': 'Understanding',
      'delta': 6,
      'first': 70,
      'last': 76,
    },
  ],
  'strongArea': 'Networking',
  'weakArea': 'Optics',
  'weakReason': '6 mistake(s) recorded',
  'focusScore': 88,
  'quizAverage': 71,
  'mistakes': 6,
  'repeatedMistakes': 1,
  'revisionDue': 2,
  'practiceExams': {},
  'recommendation': 'Spend the next 3 days revising Optics.',
  'narrative': 'You studied 4h this week and Academic Health rose to 76.',
  'aiGenerated': aiGenerated,
  'cached': false,
  'generatedAt': '2026-10-02T00:00:00Z',
};

CoachDashboardScreen _dashboard({
  Future<Map<String, dynamic>> Function()? profileFn,
  Future<Map<String, dynamic>> Function()? dailyFn,
  Future<Map<String, dynamic>> Function()? weeklyFn,
  ValueChanged<int>? onOpenPlan,
}) => CoachDashboardScreen(
  profileFn: profileFn,
  dailyFn: dailyFn,
  weeklyFn: weeklyFn,
  onOpenPlan: onOpenPlan,
);

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Home — the coach card is on the study surface', () {
    final homeSource = _read('lib/features/home/presentation/home_screen.dart');

    test('Home imports and mounts the card in study mode', () {
      expect(
        homeSource,
        contains(
          "import '../../study/presentation/planner/ziku_coach_card.dart'",
        ),
        reason: 'the coach has to reach the Home screen',
      );
      final studyIndex = homeSource.indexOf(
        'if (mode == GochanoAppMode.study)',
      );
      expect(studyIndex, greaterThan(0));
      final studyEnd = homeSource.indexOf('// Utility Mode:', studyIndex);
      expect(studyEnd, greaterThan(studyIndex));
      final studyBlock = homeSource.substring(studyIndex, studyEnd);
      expect(studyBlock, contains('ZikuCoachCard('));
      expect(
        studyBlock,
        contains('onOpenPlan: onOpenDestination'),
        reason: 'the plan hand-off has to reach the app shell',
      );
      expect(homeSource, isNot(contains('const ZikuCoachCard')));
    });

    test('the card does not reintroduce removed Home wording', () {
      expect(homeSource, isNot(contains('Focus')));
      expect(homeSource, isNot(contains('Insights')));
      expect(homeSource, isNot(contains('Study Goal')));
    });
  });

  group('Ziku coach card', () {
    testWidgets('shows the greeting, priority and mission from the brief', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ZikuCoachCard(
            briefFn: () async => _brief(
              priority: _opticsPriority,
              mission: _mission,
              exam: _physicsExam,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziku Coach'), findsOneWidget);
      expect(find.textContaining('Good Morning'), findsOneWidget);
      expect(find.textContaining('Health 82%'), findsOneWidget);
      expect(find.text('Today\u2019s Priority'), findsOneWidget);
      expect(find.text('Optics'), findsOneWidget);
      expect(
        find.textContaining('exam in 5 day(s)'),
        findsNothing,
        reason: 'reason badges are rendered on the dashboard, not the card',
      );
      expect(find.text('Review Optics'), findsOneWidget);
      expect(find.text('Solve 20 MCQ on Optics'), findsOneWidget);
      expect(find.text('Start Mission'), findsOneWidget);
    });

    testWidgets('a failed read degrades to a sentence, not a blank card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ZikuCoachCard(briefFn: () async => throw Exception('backend down')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziku Coach'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
    });

    testWidgets('Start Mission opens the coach dashboard', (tester) async {
      await tester.pumpWidget(
        _app(
          ZikuCoachCard(
            briefFn: () async =>
                _brief(priority: _opticsPriority, mission: _mission),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Mission'));
      await tester.pumpAndSettle();

      expect(find.byType(CoachDashboardScreen), findsOneWidget);
      expect(find.text('My AI Coach'), findsOneWidget);
    });
  });

  group('Coach dashboard', () {
    testWidgets('renders health, mission and the topic lists', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(),
            dailyFn: () async => _brief(
              priority: _opticsPriority,
              why: _opticsPriority['why'] as String,
              mission: _mission,
              exam: _physicsExam,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My AI Coach'), findsOneWidget);
      expect(find.text('76'), findsOneWidget);
      expect(find.textContaining('Exam ready 72%'), findsOneWidget);
      expect(find.text('Good — steady and in control.'), findsOneWidget);
      expect(find.text('Optics'), findsOneWidget);
      expect(find.text('Networking'), findsOneWidget);
      expect(find.text('240m'), findsOneWidget);
      expect(find.text('Review Optics'), findsOneWidget);
      expect(find.text('Solve 20 MCQ on Optics'), findsOneWidget);
      expect(find.text('Complete a 25 minute focus session'), findsOneWidget);
      expect(find.textContaining('exam in 5 day(s)'), findsOneWidget);
    });

    testWidgets('the weekly narrative and recommendation render', (
      tester,
    ) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(),
            dailyFn: () async => _brief(mission: _mission),
            weeklyFn: () async => _weekly(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You studied 4h this week and Academic Health rose to 76.'),
        findsOneWidget,
      );
      expect(
        find.text('Spend the next 3 days revising Optics.'),
        findsOneWidget,
      );
      expect(find.text('Written by Ziku'), findsOneWidget);
      expect(find.text('Understanding'), findsOneWidget);
      expect(find.text('+6'), findsOneWidget);
    });

    testWidgets('a failed weekly report degrades inline', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(),
            dailyFn: () async => _brief(mission: _mission),
            weeklyFn: () async => throw Exception('quota exceeded'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('76'),
        findsOneWidget,
        reason: 'the mission must survive a failed narrative',
      );
      expect(find.text('Retry report'), findsOneWidget);
      expect(find.text('Spend the next 3 days revising Optics.'), findsNothing);
    });

    testWidgets('reports an unreachable profile with a retry', (tester) async {
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => throw Exception('backend down'),
            dailyFn: () async => _brief(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('76'), findsNothing);
    });

    testWidgets('the review step opens the Learning Brain', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(),
            dailyFn: () async =>
                _brief(priority: _opticsPriority, mission: _mission),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Review'));
      await tester.pumpAndSettle();

      expect(find.byType(LearningBrainScreen), findsOneWidget);
    });

    testWidgets('the quiz step opens the generator on the priority topic', (
      tester,
    ) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(),
            dailyFn: () async =>
                _brief(priority: _opticsPriority, mission: _mission),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Start quiz'));
      await tester.pumpAndSettle();

      final screen = tester.widget<QuizGeneratorScreen>(
        find.byType(QuizGeneratorScreen),
      );
      expect(screen.initialTopic, 'Optics');
    });

    testWidgets('the focus step opens the focus session screen', (
      tester,
    ) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(),
            dailyFn: () async =>
                _brief(priority: _opticsPriority, mission: _mission),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Start focus'), findsOneWidget);

      await tester.tap(find.byTooltip('Start focus'));
      await tester.pumpAndSettle();

      final screen = tester.widget<FocusSessionScreen>(
        find.byType(FocusSessionScreen),
      );
      expect(screen.initialTopic, '');
      expect(find.text('Start Session'), findsOneWidget);
    });

    testWidgets('the rescue step hands back to the Plan tab', (tester) async {
      await _tallSurface(tester);
      int? opened;
      final rescueMission = [
        ..._mission,
        <String, dynamic>{
          'key': 'rescue',
          'action': 'rescue',
          'title': "Follow today's Exam Rescue plan",
          'detail': 'Physics Final is 5 day(s) away - stick to the schedule.',
          'minutes': 60,
          'target': 'Optics',
          'priority': 'high',
        },
      ];

      await tester.pumpWidget(
        _app(
          _Launcher(
            child: _dashboard(
              profileFn: () async => _profile(),
              dailyFn: () async =>
                  _brief(priority: _opticsPriority, mission: rescueMission),
              onOpenPlan: (index) => opened = index,
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open plan'), findsOneWidget);
      await tester.tap(find.byTooltip('Open plan'));
      await tester.pumpAndSettle();

      expect(opened, 2);
      expect(
        find.byType(CoachDashboardScreen),
        findsNothing,
        reason: 'the dashboard steps aside so the Plan tab can show',
      );
    });

    testWidgets('no exam and no data still builds a usable screen', (
      tester,
    ) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(hasData: false),
            dailyFn: () async =>
                _brief(hasData: false, score: 0, mission: [_mission.last]),
            weeklyFn: () async => _weekly(aiGenerated: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziku has nothing to coach yet'), findsOneWidget);
      expect(find.text('Complete a 25 minute focus session'), findsOneWidget);
      expect(find.text('Written by Ziku'), findsNothing);
    });

    testWidgets('the dashboard can ask Ziku about the priority topic', (
      tester,
    ) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          _dashboard(
            profileFn: () async => _profile(),
            dailyFn: () async =>
                _brief(priority: _opticsPriority, mission: _mission),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ask Ziku'), findsOneWidget);
      expect(
        find.textContaining('Optics before my exam'),
        findsNothing,
        reason: 'the question is built when the hand-off is tapped',
      );
    });
  });

  group('Coach payloads match the client', () {
    final apiSource = _read('lib/services/api_service.dart');

    test('the three reads and the recalculate exist', () {
      expect(apiSource, contains("'/api/coach/profile'"));
      expect(apiSource, contains("'/api/coach/daily'"));
      expect(apiSource, contains("'/api/coach/weekly-report'"));
      expect(apiSource, contains("'/api/coach/recalculate'"));
    });

    test('the card and the dashboard read through those methods', () {
      expect(
        _read('lib/features/study/presentation/planner/ziku_coach_card.dart'),
        contains('ApiService.coachDailyBrief'),
      );
      expect(
        _read(
          'lib/features/study/presentation/planner/coach_dashboard_screen.dart',
        ),
        contains('ApiService.coachProfile'),
      );
    });

    test('a saved quiz rebuilds the coach caches', () {
      // The profile and the mission are cached for the day, so a quiz has to
      // invalidate them itself — otherwise the coach coaches yesterday.
      final resultSource = _read(
        'lib/features/study/presentation/ai/quiz_result_screen.dart',
      );
      expect(resultSource, contains('ApiService.coachRecalculate'));
      expect(resultSource, contains('widget.saveResultFn == null'));
    });
  });
}

/// Pushes a screen onto a real navigator so a hand-off can pop it again.
class _Launcher extends StatelessWidget {
  const _Launcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () =>
            Navigator.of(context).push(GochanoRoute.to(builder: (_) => child)),
        child: const Text('open'),
      ),
    );
  }
}
