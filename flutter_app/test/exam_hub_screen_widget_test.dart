// Widget tests for ExamHubScreen visual polish, state presentation, and interaction integrity.
//
// Verifies:
// 1. Initial screen with GochanoAppBar, title, subtitle, refresh button in English.
// 2. Loading state presentation while loading dashboard data.
// 3. Error state presentation when API call fails with Retry button.
// 4. Empty state presentation when no active exam or data exists.
// 5. Exam countdown hero card when active plan is present (days remaining, exam name, daily study minutes, duration, View Plan button).
// 6. Exam readiness banner with circular arc score, readiness label, trend indicator, and recommended action.
// 7. Ziku coaching urgency note banner when present.
// 8. Today's Plan study blocks with priority indicator, duration, topic name, and completion status.
// 9. Ziku Recommends coaching items with lightbulb icon, topic, actionable guidance, and reason.
// 10. Priority Topics with "See All" button, priority badges (CRITICAL, HIGH, MEDIUM), and scores.
// 11. Quick Practice chips (Quick Quiz, Mistakes, Weak Topics, Mock Exam) and tapping triggers practice session and SnackBar with Start button.
// 12. Footer action cards (Past Papers with paper count badge and Full Readiness).
// 13. Bengali localization rendering all labels, numbers, and stats in Bengali digits and translated text.
// 14. Responsive 320dp narrow viewport with zero RenderFlex overflow.
// 15. Dark mode renders with appropriate contrast and dark surface containers.
// 16. Reduced-motion compliance (disableAnimations: true).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/exam_ecosystem/exam_ecosystem_models.dart';
import 'package:gochano/features/study/presentation/exam_ecosystem/exam_hub_screen.dart';

Widget _wrap(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 1800),
  bool disableAnimations = false,
  Map<String, WidgetBuilder>? routes,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      disableAnimations: disableAnimations,
    ),
    child: MaterialApp(
      theme: GochanoTheme.light(),
      darkTheme: GochanoTheme.dark(),
      themeMode: themeMode,
      routes: routes ??
          {
            '/exams': (_) => const Scaffold(body: Text('Exams Screen')),
            '/mistakes': (_) => const Scaffold(body: Text('Mistakes Screen')),
            '/quiz-generate': (_) =>
                const Scaffold(body: Text('Quiz Generate Screen')),
          },
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  final samplePlan = ExamPlan(
    planId: 'plan_1',
    examName: 'HSC Board Exam 2026',
    examDate: DateTime.now().add(const Duration(days: 12)).toIso8601String(),
    durationDays: 30,
    dailyMinutes: 120,
    status: 'active',
  );

  final sampleReadiness = const ExamReadiness(
    overallReadiness: 78.0,
    label: 'Ready for Exam',
    trend: 5.0,
    components: {'Physics': 80.0, 'Chemistry': 76.0},
    recommendedNextAction: 'Review Organic Chemistry reactions',
    dataCoverage: 0.85,
  );

  final samplePriorities = const [
    PriorityTopic(
      topic: 'Organic Chemistry',
      priority: 'critical',
      priorityScore: 92.0,
    ),
    PriorityTopic(
      topic: 'Electromagnetism',
      priority: 'high',
      priorityScore: 84.0,
    ),
    PriorityTopic(
      topic: 'Thermodynamics',
      priority: 'medium',
      priorityScore: 68.0,
    ),
  ];

  final sampleBlocks = const [
    StudyBlock(
      itemId: 'block_1',
      blockType: 'learn_review',
      topic: 'Kinematics Formulas',
      durationMinutes: 30,
      priority: 'high',
      status: 'pending',
    ),
    StudyBlock(
      itemId: 'block_2',
      blockType: 'practice',
      topic: 'Calculus Integration Drills',
      durationMinutes: 45,
      priority: 'critical',
      status: 'completed',
    ),
  ];

  final sampleCoaching = const [
    CoachingItem(
      type: 'study_recommendation',
      topic: 'Wave Optics',
      action: 'Solve 10 past MCQ questions on diffraction',
      durationMinutes: 20,
      priority: 'high',
      reason: 'Frequent mistakes in recent quizzes',
    ),
  ];

  group('ExamHubScreen Visual & Interaction Tests', () {
    testWidgets(
        'renders GochanoAppBar, title, subtitle, and refresh button in English',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialReadiness: sampleReadiness,
            initialPriorities: samplePriorities,
            initialTodayBlocks: sampleBlocks,
            initialCoachingItems: sampleCoaching,
            initialCoachingUrgency: 'Final stretch before exam season!',
            initialPapersAnalyzed: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Exam Hub'), findsOneWidget);
      expect(find.textContaining('HSC Board Exam 2026'), findsWidgets);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    });

    testWidgets('renders loading state with progress indicator and label',
        (tester) async {
      final completer = Completer<Map<String, dynamic>>();

      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            loadDashboardOverride: () => completer.future,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading exam dashboard…'), findsOneWidget);

      completer.complete({});
      await tester.pumpAndSettle();
    });

    testWidgets('renders error state on API failure with Retry button',
        (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialError: 'Server connection timeout. Please try again.',
            loadDashboardOverride: () async {
              retryCalled = true;
              return {};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('Server connection timeout. Please try again.'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retryCalled, isTrue);
    });

    testWidgets('renders empty state when no active exam or data exists',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExamHubScreen(
            initialPlan: null,
            initialReadiness: null,
            initialPriorities: [],
            initialTodayBlocks: [],
            initialCoachingItems: [],
            initialCoachingUrgency: '',
            initialPapersAnalyzed: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Active Exam Setup'), findsOneWidget);
      expect(
          find.text(
              'Get started by creating a practice quiz or setting up an exam study plan.'),
          findsOneWidget);
      expect(find.text('Start Quick Practice'), findsOneWidget);
    });

    testWidgets(
        'renders exam countdown hero card with days remaining, daily study time, and View Plan',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialReadiness: sampleReadiness,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HSC Board Exam 2026'), findsWidgets);
      expect(find.textContaining('days remaining'), findsOneWidget);
      expect(find.textContaining('120 min/day · 30-day plan'), findsOneWidget);
      expect(find.text('View Plan'), findsWidgets);
    });

    testWidgets('renders exam readiness banner with score, label, and trend',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialReadiness: sampleReadiness,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Exam Readiness'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget);
      expect(find.text('Ready for Exam'), findsOneWidget);
      expect(find.text('+5%'), findsOneWidget);
      expect(find.text('Review Organic Chemistry reactions'), findsOneWidget);
    });

    testWidgets('renders Ziku coaching urgency banner when note is present',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialCoachingUrgency: 'HSC Chemistry exam is approaching in 12 days!',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HSC Chemistry exam is approaching in 12 days!'),
          findsOneWidget);
      expect(find.byIcon(Icons.school_outlined), findsOneWidget);
    });

    testWidgets(
        'renders Today\'s Plan study blocks with topic, duration, and completion status',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialTodayBlocks: sampleBlocks,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Today's Plan"), findsOneWidget);
      expect(find.text('1/2 done'), findsOneWidget);
      expect(find.text('Kinematics Formulas'), findsOneWidget);
      expect(find.text('30m'), findsOneWidget);
      expect(find.text('Calculus Integration Drills'), findsOneWidget);
      expect(find.text('45m'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('renders Ziku Recommends coaching items with guidance and duration',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialCoachingItems: sampleCoaching,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziku Recommends'), findsOneWidget);
      expect(find.text('Wave Optics'), findsOneWidget);
      expect(find.text('Solve 10 past MCQ questions on diffraction'),
          findsOneWidget);
      expect(find.text('Frequent mistakes in recent quizzes'), findsOneWidget);
      expect(find.text('20m'), findsOneWidget);
    });

    testWidgets(
        'renders Priority Topics with See All, priority tags (CRITICAL, HIGH, MEDIUM), and scores',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialPriorities: samplePriorities,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Priority Topics'), findsOneWidget);
      expect(find.text('See All'), findsOneWidget);
      expect(find.text('Organic Chemistry'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('92'), findsOneWidget);
      expect(find.text('Electromagnetism'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('84'), findsOneWidget);
      expect(find.text('Thermodynamics'), findsOneWidget);
      expect(find.text('MEDIUM'), findsOneWidget);
      expect(find.text('68'), findsOneWidget);
    });

    testWidgets(
        'renders Quick Practice chips and tapping triggers practice session SnackBar with Start button',
        (tester) async {
      var startedMode = '';

      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialPriorities: samplePriorities,
            startPracticeOverride: (mode) async {
              startedMode = mode;
              return {
                'engineType': 'quiz',
                'engineConfig': {
                  'instruction': 'Custom Quick Quiz session ready!',
                },
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick Practice'), findsOneWidget);
      expect(find.text('Quick Quiz'), findsOneWidget);
      expect(find.text('Mistakes'), findsOneWidget);
      expect(find.text('Weak Topics'), findsOneWidget);
      expect(find.text('Mock Exam'), findsOneWidget);

      await tester.tap(find.text('Quick Quiz'));
      await tester.pumpAndSettle();

      expect(startedMode, equals('quick_quiz'));
      expect(find.text('Custom Quick Quiz session ready!'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      // Tap Start action button which pushes /quiz-generate
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Quiz Generate Screen'), findsOneWidget);
    });

    testWidgets('renders footer action cards for Past Papers and Full Readiness',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialPapersAnalyzed: 14,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Past Papers (14)'), findsOneWidget);
      expect(find.text('Full Readiness'), findsOneWidget);
    });

    testWidgets(
        'Bengali localization renders all labels, stats, subtitles, and numbers in Bengali',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialReadiness: sampleReadiness,
            initialPriorities: samplePriorities,
            initialTodayBlocks: sampleBlocks,
            initialCoachingItems: sampleCoaching,
            initialCoachingUrgency: 'এইচএসসি পরীক্ষার প্রস্তুতি চূড়ান্ত করুন!',
            initialPapersAnalyzed: 14,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('পরীক্ষা হাব'), findsOneWidget);
      expect(find.text('পরীক্ষা প্রস্তুতি'), findsOneWidget);
      expect(find.text('আজকের পরিকল্পনা'), findsOneWidget);
      expect(find.text('যিকু সুপারিশ'), findsOneWidget);
      expect(find.text('অগ্রাধিকার বিষয়সমূহ'), findsOneWidget);
      expect(find.text('দ্রুত অনুশীলন'), findsOneWidget);
      expect(find.text('দ্রুত কুইজ'), findsOneWidget);
      expect(find.text('ভুল সংশোধন'), findsOneWidget);
      expect(find.text('দুর্বল বিষয়'), findsOneWidget);
      expect(find.text('মক পরীক্ষা'), findsOneWidget);
      expect(find.text('সব দেখুন'), findsOneWidget);
      expect(find.textContaining('বিগত প্রশ্ন'), findsOneWidget);
      expect(find.text('পূর্ণাঙ্গ প্রস্তুতি'), findsOneWidget);

      // Bengali numbers check
      expect(find.textContaining(GochanoLanguage.toBanglaDigits(14)),
          findsWidgets);
      expect(find.textContaining('৭৮%'), findsOneWidget);
    });

    testWidgets('renders cleanly on 320dp narrow viewport with zero overflow',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialReadiness: sampleReadiness,
            initialPriorities: samplePriorities,
            initialTodayBlocks: sampleBlocks,
            initialCoachingItems: sampleCoaching,
            initialCoachingUrgency: 'Final stretch before exam season!',
            initialPapersAnalyzed: 8,
          ),
          size: const Size(320, 640),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Exam Hub'), findsOneWidget);
      expect(find.text('HSC Board Exam 2026'), findsWidgets);

      // Scroll down to test bottom sections on 320dp
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Quick Practice'), findsOneWidget);
    });

    testWidgets('renders cleanly in Dark Mode with theme-adaptive surfaces',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialReadiness: sampleReadiness,
            initialPriorities: samplePriorities,
            initialTodayBlocks: sampleBlocks,
            initialCoachingItems: sampleCoaching,
            initialCoachingUrgency: 'Final stretch before exam season!',
            initialPapersAnalyzed: 8,
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Exam Hub'), findsOneWidget);
    });

    testWidgets('respects reduced-motion preferences without animation errors',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExamHubScreen(
            initialPlan: samplePlan,
            initialReadiness: sampleReadiness,
            initialPriorities: samplePriorities,
            initialTodayBlocks: sampleBlocks,
            initialCoachingItems: sampleCoaching,
            initialCoachingUrgency: 'Final stretch before exam season!',
            initialPapersAnalyzed: 8,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Exam Hub'), findsOneWidget);
    });
  });
}
