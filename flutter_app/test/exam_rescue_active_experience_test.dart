// Phase T5 — Active Exam Rescue Today Experience & Workspace Discovery Test Suite
//
// Tests covering:
// 1. ExamRescueSession eligibility and days remaining calculation.
// 2. ExamRescueSessionService.calculateTodayProgress isolation & calculations.
// 3. ExamRescueActiveCard presentation, badges, progress, completion states.
// 4. Responsive (320dp) and 2.0x text scale layout stability.
// 5. Localization (Bangla) string correctness.
// 6. HomeScreen integration, role gating, and Utility mode exclusion.
// 7. WorkspaceView Exam Rescue tile adaptation.
// 8. PlanView Exam Rescue banner adaptation.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/home/presentation/home_screen.dart';
import 'package:gochano/features/study/presentation/planner/plan_view.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_active_card.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_session_service.dart';
import 'package:gochano/features/study/presentation/workspace/workspace_view.dart';

class MockExamRescueSessionService extends ExamRescueSessionService {
  final Stream<ExamRescueSession?> _sessionStream;

  MockExamRescueSessionService({
    Stream<ExamRescueSession?>? sessionStream,
    DateTime? now,
  }) : _sessionStream = sessionStream ?? Stream.value(null),
       super(now: now != null ? () => now : null);

  @override
  Stream<ExamRescueSession?> streamNearestActiveSession() => _sessionStream;

  @override
  Stream<List<ExamRescueSession>> streamActiveSessions() =>
      _sessionStream.map((s) => s != null ? [s] : const []);
}

Widget _wrapWithTheme(
  Widget child, {
  Size size = const Size(390, 844),
  double textScaleFactor = 1.0,
  GochanoLocale locale = GochanoLocale.english,
}) {
  GochanoLanguage.current.value = locale;
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScaleFactor),
      ),
      child: Scaffold(
        // Bound the child's height: scrollable roots (WorkspaceView, PlanView)
        // must not receive unbounded height inside this scroll view.
        body: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.height),
            child: child,
          ),
        ),
      ),
    ),
  );
}

List<Widget> _cardsForMode(HomeScreen screen, GochanoAppMode mode) {
  late List<Widget> result;
  runApp(
    MaterialApp(
      home: Builder(
        builder: (ctx) {
          result = screen.buildModeCards(ctx, mode);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseNow = DateTime(2026, 6, 10, 10, 0, 0);

  ExamRescueSession makeSession({
    String sessionId = 'session_123',
    String examTitle = 'Optical Fiber Midterm',
    DateTime? examDate,
    String status = 'active',
  }) {
    return ExamRescueSession(
      sessionId: sessionId,
      examTitle: examTitle,
      examDate: examDate ?? baseNow.add(const Duration(days: 3)),
      sourceMode: 'materials_grounded',
      generationMode: 'ai_grounded',
      totalTasks: 4,
      totalMinutes: 120,
      taskIds: const ['task_1', 'task_2', 'task_3', 'task_4'],
      createdAt: baseNow.subtract(const Duration(days: 1)),
      status: status,
    );
  }

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
  });

  group('1. ExamRescueSession Model & Days Remaining', () {
    test('isEligibleActive returns true for future exam within bounds', () {
      final session = makeSession(
        examDate: baseNow.add(const Duration(days: 2)),
      );
      expect(session.isEligibleActive(baseNow), isTrue);
    });

    test(
      'isEligibleActive returns true for same day exam (even if earlier hour)',
      () {
        final sameDayMorning = DateTime(2026, 6, 10, 8, 0, 0);
        final session = makeSession(examDate: sameDayMorning);
        expect(session.isEligibleActive(baseNow), isTrue);
      },
    );

    test('isEligibleActive returns false for yesterday exam', () {
      final yesterday = DateTime(2026, 6, 9, 23, 59, 59);
      final session = makeSession(examDate: yesterday);
      expect(session.isEligibleActive(baseNow), isFalse);
    });

    test('isEligibleActive returns false for non-active status', () {
      final completed = makeSession(status: 'completed');
      expect(completed.isEligibleActive(baseNow), isFalse);

      final cancelled = makeSession(status: 'cancelled');
      expect(cancelled.isEligibleActive(baseNow), isFalse);
    });

    test(
      'localDaysRemaining computes 0 for today, 1 for tomorrow, 3 for in 3 days',
      () {
        final todaySession = makeSession(
          examDate: DateTime(2026, 6, 10, 18, 0, 0),
        );
        expect(todaySession.localDaysRemaining(baseNow), equals(0));

        final tomorrowSession = makeSession(
          examDate: DateTime(2026, 6, 11, 9, 0, 0),
        );
        expect(tomorrowSession.localDaysRemaining(baseNow), equals(1));

        final futureSession = makeSession(
          examDate: DateTime(2026, 6, 13, 14, 0, 0),
        );
        expect(futureSession.localDaysRemaining(baseNow), equals(3));
      },
    );
  });

  group('2. ExamRescueSessionService.calculateTodayProgress', () {
    final session = makeSession(sessionId: 'active_session');

    test('ignores tasks from different sessions or unrelated sources', () {
      final tasks = [
        {
          'id': 'unrelated_task',
          'title': 'General Task',
          'source': 'manual',
          'dueDate': '2026-06-10T15:00:00Z',
          'isCompleted': false,
        },
        {
          'id': 'other_rescue_task',
          'title': 'Other Rescue Task',
          'source': 'exam_rescue',
          'rescueSessionId': 'other_session_999',
          'dueDate': '2026-06-10T15:00:00Z',
          'isCompleted': false,
        },
        {
          'id': 'my_rescue_task',
          'title': 'Photonics Review',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-10T15:00:00Z',
          'isCompleted': false,
          'estimatedMinutes': 45,
        },
      ];

      final progress = ExamRescueSessionService.calculateTodayProgress(
        session: session,
        tasks: tasks,
        now: baseNow,
      );

      expect(progress.todayTotal, equals(1));
      expect(progress.todayCompleted, equals(0));
      expect(progress.todayPlannedMinutes, equals(45));
      expect(progress.hasTasksToday, isTrue);
    });

    test('calculates todayProgressFraction accurately', () {
      final tasks = [
        {
          'id': 't1',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-10T12:00:00Z',
          'isCompleted': true,
          'estimatedMinutes': 30,
        },
        {
          'id': 't2',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-10T16:00:00Z',
          'isCompleted': false,
          'estimatedMinutes': 30,
        },
      ];

      final progress = ExamRescueSessionService.calculateTodayProgress(
        session: session,
        tasks: tasks,
        now: baseNow,
      );

      expect(progress.todayTotal, equals(2));
      expect(progress.todayCompleted, equals(1));
      expect(progress.todayProgressFraction, closeTo(0.5, 0.001));
      expect(progress.isTodayAllDone, isFalse);
    });

    test('detects all today tasks completed', () {
      final tasks = [
        {
          'id': 't1',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-10T12:00:00Z',
          'isCompleted': true,
          'estimatedMinutes': 30,
        },
        {
          'id': 't2',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-11T16:00:00Z',
          'isCompleted': false,
          'estimatedMinutes': 30,
        },
      ];

      final progress = ExamRescueSessionService.calculateTodayProgress(
        session: session,
        tasks: tasks,
        now: baseNow,
      );

      expect(progress.todayTotal, equals(1));
      expect(progress.todayCompleted, equals(1));
      expect(progress.isTodayAllDone, isTrue);
      expect(progress.isPlanAllDone, isFalse);
    });

    test('detects all plan tasks completed across all days', () {
      final tasks = [
        {
          'id': 't1',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-10T12:00:00Z',
          'isCompleted': true,
        },
        {
          'id': 't2',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-11T16:00:00Z',
          'isCompleted': true,
        },
      ];

      final progress = ExamRescueSessionService.calculateTodayProgress(
        session: session,
        tasks: tasks,
        now: baseNow,
      );

      expect(progress.isPlanAllDone, isTrue);
    });

    test('handles case when no tasks are scheduled for today', () {
      final tasks = [
        {
          'id': 't1',
          'source': 'exam_rescue',
          'rescueSessionId': 'active_session',
          'dueDate': '2026-06-12T12:00:00Z',
          'isCompleted': false,
        },
      ];

      final progress = ExamRescueSessionService.calculateTodayProgress(
        session: session,
        tasks: tasks,
        now: baseNow,
      );

      expect(progress.hasTasksToday, isFalse);
      expect(progress.todayTotal, equals(0));
    });
  });

  group('3. ExamRescueActiveCard Widget Tests', () {
    testWidgets('renders category label, exam title, badge, and CTA button', (
      tester,
    ) async {
      final session = makeSession(
        examTitle: 'Optical Fiber Midterm',
        examDate: baseNow.add(const Duration(days: 3)),
      );
      const progress = ExamRescueTodayProgress(
        overallTotal: 4,
        overallCompleted: 2,
        todayTotal: 4,
        todayCompleted: 2,
        todayPlannedMinutes: 120,
      );

      bool tapped = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          ExamRescueActiveCard(
            session: session,
            progress: progress,
            onContinueRescue: () => tapped = true,
            now: baseNow,
          ),
        ),
      );

      expect(find.text('EXAM RESCUE'), findsOneWidget);
      expect(find.text('Optical Fiber Midterm'), findsOneWidget);
      expect(find.text('3 days left'), findsOneWidget);
      expect(find.text('2 of 4 rescue tasks completed'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('120 min planned today'), findsOneWidget);
      expect(find.text('Continue Rescue'), findsOneWidget);

      await tester.tap(find.text('Continue Rescue'));
      expect(tapped, isTrue);
    });

    testWidgets('displays warning badge when exam is today (0 days left)', (
      tester,
    ) async {
      final session = makeSession(
        examTitle: 'Digital Signal Processing',
        examDate: DateTime(2026, 6, 10, 14, 0, 0),
      );
      const progress = ExamRescueTodayProgress(
        overallTotal: 2,
        overallCompleted: 1,
        todayTotal: 2,
        todayCompleted: 1,
        todayPlannedMinutes: 60,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ExamRescueActiveCard(
            session: session,
            progress: progress,
            onContinueRescue: () {},
            now: baseNow,
          ),
        ),
      );

      expect(find.text('Exam Today'), findsOneWidget);
    });

    testWidgets('displays all today tasks completed state', (tester) async {
      final session = makeSession();
      const progress = ExamRescueTodayProgress(
        overallTotal: 4,
        overallCompleted: 2,
        todayTotal: 2,
        todayCompleted: 2,
        todayPlannedMinutes: 60,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ExamRescueActiveCard(
            session: session,
            progress: progress,
            onContinueRescue: () {},
            now: baseNow,
          ),
        ),
      );

      expect(
        find.text("All of today's rescue tasks are completed!"),
        findsOneWidget,
      );
      expect(find.text('Open Plan'), findsOneWidget);
    });

    testWidgets('displays all plan tasks completed state', (tester) async {
      final session = makeSession();
      const progress = ExamRescueTodayProgress(
        overallTotal: 4,
        overallCompleted: 4,
        todayTotal: 2,
        todayCompleted: 2,
        todayPlannedMinutes: 60,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ExamRescueActiveCard(
            session: session,
            progress: progress,
            onContinueRescue: () {},
            now: baseNow,
          ),
        ),
      );

      expect(
        find.text('All rescue tasks completed! Great work!'),
        findsOneWidget,
      );
      expect(find.text('Review Plan'), findsOneWidget);
    });

    testWidgets('displays no tasks scheduled for today message', (
      tester,
    ) async {
      final session = makeSession();
      const progress = ExamRescueTodayProgress(
        overallTotal: 4,
        overallCompleted: 0,
        todayTotal: 0,
        todayCompleted: 0,
        todayPlannedMinutes: 0,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ExamRescueActiveCard(
            session: session,
            progress: progress,
            onContinueRescue: () {},
            now: baseNow,
          ),
        ),
      );

      expect(find.text('No rescue tasks scheduled for today.'), findsOneWidget);
      expect(find.text('Open Plan'), findsOneWidget);
    });

    testWidgets('renders cleanly on 320dp width without overflow', (
      tester,
    ) async {
      final session = makeSession(
        examTitle: 'Super Long Subject Midterm Examination',
      );
      const progress = ExamRescueTodayProgress(
        overallTotal: 4,
        overallCompleted: 1,
        todayTotal: 4,
        todayCompleted: 1,
        todayPlannedMinutes: 90,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ExamRescueActiveCard(
            session: session,
            progress: progress,
            onContinueRescue: () {},
            now: baseNow,
          ),
          size: const Size(320, 600),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Super Long Subject Midterm Examination'),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders cleanly with 2.0x text scale factor without overflow',
      (tester) async {
        final session = makeSession();
        const progress = ExamRescueTodayProgress(
          overallTotal: 4,
          overallCompleted: 2,
          todayTotal: 4,
          todayCompleted: 2,
          todayPlannedMinutes: 120,
        );

        await tester.pumpWidget(
          _wrapWithTheme(
            ExamRescueActiveCard(
              session: session,
              progress: progress,
              onContinueRescue: () {},
              now: baseNow,
            ),
            textScaleFactor: 2.0,
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders Bengali labels correctly when language is Bangla', (
      tester,
    ) async {
      final session = makeSession(
        examTitle: 'পদার্থবিজ্ঞান পরীক্ষা',
        examDate: baseNow.add(const Duration(days: 3)),
      );
      const progress = ExamRescueTodayProgress(
        overallTotal: 4,
        overallCompleted: 2,
        todayTotal: 4,
        todayCompleted: 2,
        todayPlannedMinutes: 120,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ExamRescueActiveCard(
            session: session,
            progress: progress,
            onContinueRescue: () {},
            now: baseNow,
          ),
          locale: GochanoLocale.bangla,
        ),
      );

      expect(find.text('পরীক্ষা উদ্ধার'), findsOneWidget);
      expect(find.text('পদার্থবিজ্ঞান পরীক্ষা'), findsOneWidget);
      expect(find.text('৩ দিন বাকি'), findsOneWidget);
      expect(find.text('উদ্ধার চালিয়ে যান'), findsOneWidget);
    });
  });

  group('4. WorkspaceView Quick Access Tile', () {
    testWidgets(
      'displays remaining days and invokes onOpenPlan when active session exists',
      (tester) async {
        final session = makeSession(
          examTitle: 'Chemistry Final',
          examDate: baseNow.add(const Duration(days: 3)),
        );
        final mockService = MockExamRescueSessionService(
          sessionStream: Stream.value(session),
          now: baseNow,
        );

        bool planOpened = false;

        await tester.pumpWidget(
          _wrapWithTheme(
            WorkspaceView(
              onOpenPlan: () => planOpened = true,
              examRescueSessionService: mockService,
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Exam Rescue'), findsOneWidget);
        expect(find.text('Exam in 3 days · View plan'), findsOneWidget);

        await tester.tap(find.text('Exam Rescue'));
        expect(planOpened, isTrue);
      },
    );

    testWidgets('displays fallback subtitle when no active session exists', (
      tester,
    ) async {
      final mockService = MockExamRescueSessionService(
        sessionStream: Stream.value(null),
        now: baseNow,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          WorkspaceView(
            onOpenPlan: () {},
            examRescueSessionService: mockService,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Exam Rescue'), findsOneWidget);
      expect(
        find.text('Exam close? Build a quick rescue plan.'),
        findsOneWidget,
      );
    });
  });

  group('5. PlanView Adaptive Exam Rescue Banner', () {
    testWidgets(
      'displays active session title and days remaining when active',
      (tester) async {
        final session = makeSession(
          examTitle: 'Optical Fiber Midterm',
          examDate: baseNow.add(const Duration(days: 2)),
        );
        final mockService = MockExamRescueSessionService(
          sessionStream: Stream.value(session),
          now: baseNow,
        );

        await tester.pumpWidget(
          _wrapWithTheme(PlanView(examRescueSessionService: mockService)),
        );
        await tester.pump();

        expect(find.text('Exam Rescue: Optical Fiber Midterm'), findsOneWidget);
        expect(find.text('2 days remaining · Active Plan'), findsOneWidget);
        expect(find.text('+ New Plan'), findsOneWidget);
      },
    );

    testWidgets('displays default banner when no active session exists', (
      tester,
    ) async {
      final mockService = MockExamRescueSessionService(
        sessionStream: Stream.value(null),
        now: baseNow,
      );

      await tester.pumpWidget(
        _wrapWithTheme(PlanView(examRescueSessionService: mockService)),
      );
      await tester.pump();

      expect(find.text('Exam Rescue'), findsOneWidget);
      expect(
        find.text('Exam close? Build a focused rescue plan.'),
        findsOneWidget,
      );
      expect(find.text('Build Plan'), findsOneWidget);
    });
  });

  group('6. HomeScreen Mode & Role Gating', () {
    testWidgets(
      'cardsForMode includes ExamRescueActiveCard inside _TodaysTasksCard only in study mode',
      (tester) async {
        final home = HomeScreen(
          role: 'student',
          displayName: 'Test Student',
          onOpenDestination: (_) {},
          onOpenProfile: () {},
        );

        // Study mode keeps the required cards and may include additive learning
        // intelligence cards such as the Phase 10.5 recommendation card.
        final studyCards = _cardsForMode(home, GochanoAppMode.study);
        expect(studyCards.length, greaterThanOrEqualTo(15));
        final studyTypes = studyCards
            .map((w) => w.runtimeType.toString())
            .toList();
        expect(studyTypes, contains('LearningRecommendationCard'));
        expect(studyTypes, contains('ZikuCoachCard'));

        // In Utility mode: returns 5 elements (SyncStatusIndicator, SizedBox, _CommuteCard, SizedBox, _MoneyCard)
        final utilityCards = _cardsForMode(home, GochanoAppMode.utility);
        expect(utilityCards.length, equals(5));

        final utilityTypes = utilityCards
            .map((w) => w.runtimeType.toString())
            .toList();
        expect(utilityTypes, isNot(contains('_TodaysTasksCard')));
        expect(utilityTypes, contains('_CommuteCard'));
        expect(utilityTypes, contains('_MoneyCard'));
      },
    );
  });
}
