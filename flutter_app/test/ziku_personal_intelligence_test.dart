// Phase 8 — Ziku Personal Intelligence, client side.
//
// What the client owes Phase 8:
//   * the five `/api/ziku/*` reads exist and are wired to real paths;
//   * three screens render their payloads as-is — journey, learning profile,
//     achievements — with the standard loading / error / empty degradation;
//   * the coach dashboard gains a "Personal OS" section: three doors into
//     those screens plus the daily brief and the ranked next best action,
//     both of which fail silently (the mission above them never moves);
//   * the Home screen is untouched: no new Home items, no Phase 8 wording.
//
// Every reader is injected, so no test here opens a socket.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/planner/coach_dashboard_screen.dart';
import 'package:gochano/features/study/presentation/planner/learning_journey_screen.dart';
import 'package:gochano/features/study/presentation/planner/learning_personality_screen.dart';
import 'package:gochano/features/study/presentation/planner/ziku_achievements_screen.dart';
import 'package:gochano/shared/widgets/ai_widgets.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Every Phase 8 screen is one long list; a default 800x600 surface only
/// builds the first screenful.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

// ---------------------------------------------------------------------------
// payloads
// ---------------------------------------------------------------------------

Map<String, dynamic> _journey({bool hasData = true}) => {
  'student': 'Rafi',
  'dayKey': '2026-10-02',
  'title': 'Your Learning Journey',
  'headline': 'You studied on 12 of the last 90 days.',
  'hasData': hasData,
  'spanDays': 90,
  'windowStart': '2026-07-04',
  'windowEnd': '2026-10-02',
  'stats': {'daysActive': 12, 'focusStreak': 3},
  'streams': {'studyHours': 14.5, 'focusSessions': 9, 'quizAverage': 60},
  'timeline': [
    {
      'dayKey': '2026-10-01',
      'kind': 'quiz',
      'title': 'Quiz on Optics',
      'detail': 'Scored 60% in 12 questions.',
      'value': 60,
      'unit': 'percent',
      'tone': 'positive',
    },
  ],
  'timelineCount': 1,
  'trends': [
    {
      'key': 'quizAverage',
      'label': 'Quiz average',
      'unit': 'percent',
      'first': 40,
      'last': 60,
      'delta': 20,
      'higherIsBetter': true,
      'improving': true,
    },
    {
      'key': 'mistakes',
      'label': 'New mistakes',
      'unit': 'count',
      'first': 9,
      'last': 3,
      'delta': -6,
      'higherIsBetter': false,
      'improving': true,
    },
  ],
  'weakTopics': [
    {
      'topic': 'Thermodynamics',
      'mistakes': 6,
      'repeated': 2,
      'due': 2,
      'quizAverage': 41,
    },
  ],
  'improving': 2,
  'declining': 0,
  'generatedAt': '2026-10-02T00:00:00Z',
  'cached': false,
};

Map<String, dynamic> _personality({bool hasData = true}) => {
  'student': 'Rafi',
  'dayKey': '2026-10-02',
  'hasData': hasData,
  'title': 'Student Learning Profile',
  'label': 'The Steady Finisher',
  'personality': {
    'label': 'The Steady Finisher',
    'preferredStudyTime': {
      'key': 'morning',
      'label': 'Morning',
      'sharePct': 60,
      'sessions': 10,
      'breakdown': {'morning': 6, 'afternoon': 2, 'evening': 1, 'night': 1},
      'evidence': '60% of your finished sessions start in the morning.',
    },
    'learningStyle': {
      'key': 'deep_worker',
      'label': 'Deep work blocks',
      'why': 'You finish long, uninterrupted sessions - protect that habit.',
      'score': 5,
    },
    'strongSubjects': [
      {'name': 'Physics', 'average': 88, 'attempts': 4},
    ],
    'weakSubjects': [
      {'name': 'Chemistry', 'average': 41, 'attempts': 3},
    ],
    'subjectKind': 'subject',
    'strengths': ['Strongest in Physics (88%)'],
    'watchouts': ['Weakest in Chemistry (41%)'],
  },
  'evidence': {
    'quizzes': 12,
    'quizAverage': 71,
    'focusMinutes': 240,
    'focusConsistency': 70,
    'averageSessionMinutes': 30,
    'focusStreak': 3,
    'mistakes': 6,
    'repeatedMistakes': 1,
    'revisionDue': 2,
    'practiceExams': 1,
    'communityPosts': 2,
    'communityPoints': 15,
  },
  'healthScore': 76,
  'weakTopics': <Map<String, dynamic>>[],
  'strongTopics': <Map<String, dynamic>>[],
  'generatedAt': '2026-10-02T00:00:00Z',
  'cached': false,
};

Map<String, dynamic> _achievements({bool hasData = true}) => {
  'dayKey': '2026-10-02',
  'hasData': hasData,
  'counts': {
    'earned': 1,
    'locked': 1,
    'total': 2,
    'earnedByCategory': {'mcq': 1, 'consistency': 0, 'improvement': 0, 'contribution': 0},
    'totalByCategory': {'mcq': 2, 'consistency': 0, 'improvement': 0, 'contribution': 0},
  },
  'categories': [
    {'key': 'mcq', 'earned': 1, 'total': 2},
    {'key': 'consistency', 'earned': 0, 'total': 0},
    {'key': 'improvement', 'earned': 0, 'total': 0},
    {'key': 'contribution', 'earned': 0, 'total': 0},
  ],
  'achievements': [
    {
      'id': 'mcq_first',
      'category': 'mcq',
      'metric': 'quizzes',
      'title': 'First Set',
      'description': 'Answer your first MCQ.',
      'current': 1,
      'target': 1,
      'progress': 1.0,
      'earned': true,
      'earnedAt': '2026-10-01T09:00:00Z',
    },
    {
      'id': 'mcq_10',
      'category': 'mcq',
      'metric': 'quizzes',
      'title': 'Ten Down',
      'description': 'Answer 10 MCQ sets.',
      'current': 4,
      'target': 10,
      'progress': 0.4,
      'earned': false,
      'earnedAt': null,
    },
  ],
  'next': {
    'id': 'mcq_10',
    'category': 'mcq',
    'title': 'Ten Down',
    'description': 'Answer 10 MCQ sets.',
    'current': 4,
    'target': 10,
    'progress': 0.4,
    'earned': false,
  },
  'metrics': {'quizzes': 4},
  'earnedAt': {'mcq_first': '2026-10-01T09:00:00Z'},
  'generatedAt': '2026-10-02T00:00:00Z',
};

/// The daily brief, morning headings and evening recap.
Map<String, dynamic> _zikuBrief() => {
  'dayKey': '2026-10-02',
  'phase': 'morning',
  'requestedPhase': 'auto',
  'morning': {
    'greeting': 'Good Morning',
    'greetingKey': 'morning',
    'academicHealth': {'score': 76, 'hasData': true, 'grade': 'good'},
    'priority': {
      'topic': 'Thermodynamics',
      'priority': 'high',
      'why': 'Thermodynamics keeps repeating.',
      'reasons': <String>[],
      'mistakes': 6,
    },
    'why': 'Thermodynamics keeps repeating.',
    'mission': <Map<String, dynamic>>[],
    'missionCount': 3,
    'exam': null,
    'focus': {'todayMinutes': 40},
    'generatedAt': '2026-10-02T00:00:00Z',
  },
  'evening': {
    'summary': 'Today: 40 min of deep work, 1 quiz(zes).',
    'progress': {
      'studyMinutes': 40,
      'focusSessions': 1,
      'quizzes': 1,
      'exams': 0,
      'mistakes': 1,
      'missionSteps': 3,
      'healthScore': 76,
    },
    'mistakesToday': [
      {'topic': 'Thermodynamics', 'count': 1},
    ],
    'mistakesTodayCount': 1,
    'mistakesTotal': 6,
    'tomorrow': {
      'topic': 'Thermodynamics',
      'title': 'Start tomorrow with Thermodynamics',
      'why': 'Thermodynamics: repeated mistakes.',
      'minutes': 40,
      'action': 'Review the concept, then drill it.',
      'priority': 'high',
      'destination': 'quiz',
    },
    'reflection': 'You put in 40 min of deep work today.',
    'reflectionAi': false,
  },
  'generatedAt': '2026-10-02T00:00:00Z',
  'cached': false,
};

/// The Smart Recommendation Engine: one winner, the rest as alternatives.
Map<String, dynamic> _nextAction() => {
  'dayKey': '2026-10-02',
  'action': {
    'key': 'coach_review',
    'source': 'Study Coach',
    'title': 'Review Thermodynamics',
    'detail': 'Thermodynamics: repeated mistakes, quiz average 41%.',
    'minutes': 25,
    'score': 100.0,
    'destination': 'review',
    'target': 'Thermodynamics',
    'evidence': {'priority': 'high', 'reasons': <String>['repeated mistakes']},
  },
  'alternatives': [
    {
      'key': 'focus_block',
      'source': 'Ziku Focus Engine',
      'title': 'Bank 30 more focus minutes',
      'detail': '0/60 minutes today.',
      'minutes': 30,
      'score': 45.0,
      'destination': 'focus',
      'target': '',
      'evidence': <String, dynamic>{},
    },
  ],
  'why': 'Study Coach: Thermodynamics: repeated mistakes, quiz average 41%.',
  'sources': {'coach': {'priority': 'Thermodynamics'}},
  'generatedAt': '2026-10-02T00:00:00Z',
  'cached': false,
};

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Phase 8 wiring (source)', () {
    final api = _read('lib/services/api_service.dart');
    final dashboard = _read(
      'lib/features/study/presentation/planner/coach_dashboard_screen.dart',
    );
    final home = _read('lib/features/home/presentation/home_screen.dart');

    test('the five Ziku reads hit the five Phase 8 routes', () {
      expect(api, contains("'/api/ziku/journey'"));
      expect(api, contains("'/api/ziku/brief'"));
      expect(api, contains("'/api/ziku/profile'"));
      expect(api, contains("'/api/ziku/next-best-action'"));
      expect(api, contains("'/api/ziku/achievements'"));
      expect(api, contains('static Future<Map<String, dynamic>> zikuJourney('));
      expect(api, contains('static Future<Map<String, dynamic>> zikuBrief('));
      expect(api, contains('static Future<Map<String, dynamic>> zikuProfile('));
      expect(
        api,
        contains('static Future<Map<String, dynamic>> zikuNextBestAction('),
      );
      expect(
        api,
        contains('static Future<Map<String, dynamic>> zikuAchievements('),
      );
    });

    test('the dashboard reads the brief and the action, and links the screens',
        () {
      expect(dashboard, contains('ApiService.zikuBrief'));
      expect(dashboard, contains('ApiService.zikuNextBestAction'));
      expect(dashboard, contains('const LearningJourneyScreen()'));
      expect(dashboard, contains('const LearningPersonalityScreen()'));
      expect(dashboard, contains('const ZikuAchievementsScreen()'));
      expect(dashboard, contains("GochanoLanguage.text('Personal OS'"));
    });

    test('Home is untouched by Phase 8', () {
      expect(home, isNot(contains('Your Learning Journey')));
      expect(home, isNot(contains('Student Learning Profile')));
      expect(home, isNot(contains('Personal OS')));
      expect(home, isNot(contains('Next best action')));
      expect(home, isNot(contains('Achievements')));
    });
  });

  group('Your Learning Journey', () {
    testWidgets('a student with no history gets a sentence, not a chart',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          LearningJourneyScreen(
            journeyFn: () async => _journey(hasData: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your Learning Journey'), findsOneWidget);
      expect(find.byType(AiEmptyState), findsOneWidget);
      expect(
        find.textContaining('Your journey starts with one entry'),
        findsOneWidget,
      );
      expect(find.text('Quiz average'), findsNothing);
    });

    testWidgets('renders the headline, the trends and the timeline',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(LearningJourneyScreen(journeyFn: () async => _journey())),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You studied on 12 of the last 90 days.'),
        findsOneWidget,
      );
      expect(find.text('Improvement trends'), findsOneWidget);
      expect(find.text('Quiz average'), findsOneWidget);
      expect(find.text('New mistakes'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Quiz on Optics'), findsOneWidget);
      expect(find.text('Weak topics'), findsOneWidget);
      expect(find.text('Thermodynamics'), findsOneWidget);
      expect(
        find.text('2026-07-04 → 2026-10-02'),
        findsOneWidget,
        reason: 'the window is shown as-is, not reformatted',
      );
      expect(find.text('The rest of your Personal OS'), findsOneWidget);
    });

    testWidgets('a failed read degrades to a banner with a retry',
        (tester) async {
      await tester.pumpWidget(
        _app(
          LearningJourneyScreen(
            journeyFn: () async => throw Exception('backend down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AiErrorBanner), findsOneWidget);
      expect(find.textContaining('backend down'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the profile and achievements are one tap away',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(LearningJourneyScreen(journeyFn: () async => _journey())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Student Learning Profile'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);

      await tester.tap(find.text('Achievements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(ZikuAchievementsScreen), findsOneWidget);
    });
  });

  group('Student Learning Profile', () {
    testWidgets('renders the label, the preferred time and the evidence',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          LearningPersonalityScreen(profileFn: () async => _personality()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Student Learning Profile'), findsOneWidget);
      expect(find.text('The Steady Finisher'), findsOneWidget);
      expect(find.text('Deep work blocks'), findsOneWidget);
      expect(find.text('Preferred study time'), findsOneWidget);
      expect(find.text('60% of your finished sessions start in the morning.'),
          findsOneWidget);
      expect(find.text('Strengths and watch-outs'), findsOneWidget);
      expect(
        find.text('Strongest in Physics (88%)'),
        findsOneWidget,
      );
      expect(
        find.text('Weakest in Chemistry (41%)'),
        findsOneWidget,
      );
      expect(find.text('Evidence'), findsOneWidget);
      expect(find.text('Quizzes taken'), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Chemistry'), findsOneWidget);
    });

    testWidgets('an empty profile explains what fills it in', (tester) async {
      await tester.pumpWidget(
        _app(
          LearningPersonalityScreen(
            profileFn: () async => _personality(hasData: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AiEmptyState), findsOneWidget);
      expect(
        find.textContaining('No study history yet'),
        findsOneWidget,
      );
      expect(find.text('The Steady Finisher'), findsNothing);
    });

    testWidgets('a failed read degrades to a banner with a retry',
        (tester) async {
      await tester.pumpWidget(
        _app(
          LearningPersonalityScreen(
            profileFn: () async => throw Exception('backend down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AiErrorBanner), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Achievements', () {
    testWidgets('the scoreboard shows counts, categories and every bar',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          ZikuAchievementsScreen(
            achievementsFn: () async => _achievements(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('1 of 2 earned'), findsOneWidget);
      expect(find.text('MCQ milestones'), findsOneWidget);
      expect(find.text('First Set'), findsOneWidget);
      expect(find.text('Answer your first MCQ.'), findsOneWidget);
      expect(find.text('Ten Down'), findsNWidgets(2),
          reason: 'the list row and the "next up" card both name it');
      expect(find.text('Earned'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Next up'), findsOneWidget);
      expect(
        find.byType(LinearProgressIndicator),
        findsNWidgets(4),
        reason: 'scoreboard + next up + one bar per achievement row',
      );
    });

    testWidgets('a student who has earned nothing is invited to start',
        (tester) async {
      await tester.pumpWidget(
        _app(
          ZikuAchievementsScreen(
            achievementsFn: () async => _achievements(hasData: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AiEmptyState), findsOneWidget);
      expect(
        find.textContaining('Your first milestone is one quiz away'),
        findsOneWidget,
      );
      expect(find.text('First Set'), findsNothing);
    });

    testWidgets('a failed read degrades to a banner with a retry',
        (tester) async {
      await tester.pumpWidget(
        _app(
          ZikuAchievementsScreen(
            achievementsFn: () async => throw Exception('backend down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AiErrorBanner), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Coach dashboard — the Personal OS section', () {
    Widget dashboard({
      Future<Map<String, dynamic>> Function()? profileFn,
      Future<Map<String, dynamic>> Function()? dailyFn,
      Future<Map<String, dynamic>> Function()? weeklyFn,
      Future<Map<String, dynamic>> Function()? briefFn,
      Future<Map<String, dynamic>> Function()? actionFn,
    }) =>
        CoachDashboardScreen(
          profileFn: profileFn,
          dailyFn: dailyFn,
          weeklyFn: weeklyFn,
          briefFn: briefFn,
          actionFn: actionFn,
        );

    testWidgets('renders the brief, the next action and the three doors',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          dashboard(
            profileFn: () async => _dashProfile(),
            dailyFn: () async => _dashDaily(),
            weeklyFn: () async => _dashWeekly(),
            briefFn: () async => _zikuBrief(),
            actionFn: () async => _nextAction(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Personal OS'), findsOneWidget);
      expect(find.text('Ziku\u2019s daily brief'), findsOneWidget);
      expect(
        find.text('Thermodynamics keeps repeating.'),
        findsOneWidget,
      );
      expect(find.text('Next best action'), findsOneWidget);
      expect(find.text('Review Thermodynamics'), findsOneWidget);
      expect(find.text('Study Coach'), findsOneWidget);
      expect(find.text('Your Learning Journey'), findsOneWidget);
      expect(find.text('Student Learning Profile'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
      expect(
        find.textContaining('Start tomorrow with Thermodynamics'),
        findsOneWidget,
      );
    });

    testWidgets('a failed Phase 8 read leaves the section as three doors',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          dashboard(
            profileFn: () async => _dashProfile(),
            dailyFn: () async => _dashDaily(),
            weeklyFn: () async => _dashWeekly(),
            briefFn: () async => throw Exception('backend down'),
            actionFn: () async => throw Exception('backend down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Personal OS'), findsOneWidget);
      expect(find.text('Your Learning Journey'), findsOneWidget);
      expect(find.text('Student Learning Profile'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Ziku\u2019s daily brief'), findsNothing);
      expect(find.text('Next best action'), findsNothing);
      expect(find.byType(AiErrorBanner), findsNothing);
    });

    testWidgets('the doors open the Phase 8 screens', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          dashboard(
            profileFn: () async => _dashProfile(),
            dailyFn: () async => _dashDaily(),
            weeklyFn: () async => _dashWeekly(),
            briefFn: () async => _zikuBrief(),
            actionFn: () async => _nextAction(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Student Learning Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(LearningPersonalityScreen), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// minimal dashboard payloads (Phase 4 shapes, only what the screen reads)
// ---------------------------------------------------------------------------

Map<String, dynamic> _dashProfile() => {
  'student': 'Rafi',
  'dayKey': '2026-10-02',
  'hasData': true,
  'healthScore': 76,
  'healthGrade': 'good',
  'healthHeadline': 'Good — steady and in control.',
  'trend': {'direction': 'up', 'delta': 4, 'previousScore': 72},
  'weakTopics': <Map<String, dynamic>>[],
  'strongTopics': <Map<String, dynamic>>[],
  'studyPattern': {
    'weekMinutes': 240,
    'studyDays': 4,
    'todayMinutes': 40,
    'averageFocusScore': 80,
    'focusConsistency': 70,
  },
  'examReadiness': 72,
  'upcomingExam': null,
  'repeatedMistakes': 1,
  'totalMistakes': 6,
  'revisionDue': 2,
  'quizAverage': 71,
  'averageFocusTime': 60,
  'generatedAt': '2026-10-02T00:00:00Z',
};

Map<String, dynamic> _dashDaily() => {
  'dayKey': '2026-10-02',
  'greeting': 'Good Morning',
  'hasData': true,
  'healthScore': 76,
  'priority': null,
  'why': 'No urgent gaps today - keep the streak going.',
  'mission': <Map<String, dynamic>>[],
  'missionCount': 0,
  'exam': null,
};

Map<String, dynamic> _dashWeekly() => {
  'weekStart': '2026-09-26',
  'studyMinutes': 240,
  'studyDays': 4,
  'quizAverage': 71,
  'focusScore': 88,
  'mistakes': 6,
  'repeatedMistakes': 1,
  'revisionDue': 2,
  'scoreDelta': 4,
  'weakArea': 'Thermodynamics',
  'weakReason': 'two repeated mistakes',
  'recommendation': 'Spend the next 3 days revising Thermodynamics.',
  'narrative': 'You studied 4h this week and Academic Health rose to 76.',
  'aiGenerated': true,
  'improvement': <Map<String, dynamic>>[],
};
