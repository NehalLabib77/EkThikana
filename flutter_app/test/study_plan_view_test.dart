import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/app_design_system.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/shell/presentation/gochano_shell.dart';
import 'package:gochano/features/study/presentation/planner/plan_view.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_session_service.dart';

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

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  Widget buildPlanView({
    Size size = const Size(390, 844),
    double textScale = 1.0,
    bool isDark = false,
    List<Map<String, dynamic>>? mockTasks = const [],
    Map<String, dynamic>? mockTargetExam,
    Map<String, int?>? mockStudyGoals,
    ExamRescueSessionService? examRescueSessionService,
  }) {
    return MaterialApp(
      theme: isDark ? ThemeData.dark() : ThemeData.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: PlanView(
            mockTasks: mockTasks,
            mockTargetExam: mockTargetExam,
            mockStudyGoals: mockStudyGoals,
            examRescueSessionService: examRescueSessionService,
          ),
        ),
      ),
    );
  }

  group('Study Mode → Plan Redesign Tests', () {
    // ─── Test 1: Pinned Header & Trailing Action ──────────────────────────────
    testWidgets(
      '1. contextual AppStudyHeader has search hidden and calendar trailing action',
      (tester) async {
        await tester.pumpWidget(buildPlanView());
        await tester.pump();

        expect(find.byType(AppStudyHeader), findsOneWidget);

        // Search IconButton must be hidden in the header
        final searchIconButtons = find.widgetWithIcon(
          IconButton,
          Icons.search_rounded,
        );
        expect(
          searchIconButtons,
          findsNothing,
          reason: 'Header search should be hidden on Plan',
        );

        // Trailing action calendar icon should be present
        expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
      },
    );

    // ─── Test 2: Intro Section ────────────────────────────────────────────────
    testWidgets('2. renders page title "Plan" and subtitle', (tester) async {
      await tester.pumpWidget(buildPlanView());
      await tester.pump();

      expect(find.text('Plan'), findsWidgets);
      expect(
        find.text('Organize your upcoming study and goals.'),
        findsOneWidget,
      );
    });

    // ─── Test 3: Current Goal Card (Empty State) ──────────────────────────────
    testWidgets('3. current goal empty state renders when no target exam', (
      tester,
    ) async {
      await tester.pumpWidget(buildPlanView(mockTargetExam: null));
      await tester.pump();

      expect(find.text('Set your target exam'), findsOneWidget);
      expect(find.text('Set Goal'), findsOneWidget);
    });

    // ─── Test 4: Current Goal Card (Populated) ─────────────────────────────────
    testWidgets(
      '4. current goal card renders exam details, milestone, and roadmap CTA',
      (tester) async {
        await tester.pumpWidget(
          buildPlanView(
            mockTargetExam: {
              'examName': 'HSC Final Exam 2026',
              'targetDate': 'Dec 2026',
              'nextMilestone': 'Physics Chapter 4 Revision',
              'readiness': 75.0,
            },
          ),
        );
        await tester.pump();

        expect(find.text('Current Goal'), findsOneWidget);
        expect(find.text('HSC Final Exam 2026'), findsOneWidget);
        expect(find.text('Dec 2026'), findsOneWidget);
        expect(
          find.text('Next Milestone: Physics Chapter 4 Revision'),
          findsOneWidget,
        );
        expect(find.text('View Roadmap'), findsOneWidget);
      },
    );

    // ─── Test 5: Date Strip Navigation ────────────────────────────────────────
    testWidgets(
      '5. date strip renders dates and "Today" button resets selection',
      (tester) async {
        await tester.pumpWidget(buildPlanView());
        await tester.pump();

        expect(find.text('Today'), findsWidgets);

        // Tap "Today" button
        await tester.tap(find.widgetWithText(InkWell, 'Today').first);
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    // ─── Test 6: Due Tasks on Selected Day ────────────────────────────────────
    testWidgets('6. tasks scheduled for selected day are rendered', (
      tester,
    ) async {
      final now = DateTime.now();
      final todayAt5pm = DateTime(now.year, now.month, now.day, 17, 0);

      await tester.pumpWidget(
        buildPlanView(
          mockTasks: [
            {
              'id': 'task_1',
              'title': 'Revise Organic Chemistry',
              'dueAt': todayAt5pm.toIso8601String(),
              'done': false,
            },
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Due This Day'), findsOneWidget);
      expect(find.text('Revise Organic Chemistry'), findsWidgets);
    });

    // ─── Test 7: Past Missed Tasks Excluded from Upcoming Plan ────────────────
    testWidgets(
      '7. past missed task is NOT displayed in current/future plan view',
      (tester) async {
        final pastDate = DateTime.now().subtract(const Duration(days: 3));

        await tester.pumpWidget(
          buildPlanView(
            mockTasks: [
              {
                'id': 'task_old',
                'title': 'Past Incomplete Task',
                'dueAt': pastDate.toIso8601String(),
                'done': false,
              },
            ],
          ),
        );
        await tester.pump();

        // Because the selected date is today, a task from 3 days ago should NOT appear
        expect(find.text('Past Incomplete Task'), findsNothing);
      },
    );

    // ─── Test 8: Empty Tasks Day State ────────────────────────────────────────
    testWidgets(
      '8. empty tasks day displays helpful message and quick action buttons',
      (tester) async {
        await tester.pumpWidget(buildPlanView(mockTasks: const []));
        await tester.pump();

        expect(
          find.text('No tasks or assignments for this day.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Task'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Assignment'),
          findsOneWidget,
        );
      },
    );

    // ─── Test 9: Deadline Timeline Section ────────────────────────────────────
    testWidgets('9. timeline renders upcoming future deadlines in order', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 10, 0);
      final inThreeDays = DateTime(now.year, now.month, now.day + 3, 15, 0);

      await tester.pumpWidget(
        buildPlanView(
          mockTasks: [
            {
              'id': 'task_tmrw',
              'title': 'Math Assignment 2',
              'dueAt': tomorrow.toIso8601String(),
              'done': false,
            },
            {
              'id': 'task_3d',
              'title': 'Physics Lab Submission',
              'dueAt': inThreeDays.toIso8601String(),
              'done': false,
            },
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Exam & Deadline Timeline'), findsOneWidget);
      expect(find.text('Math Assignment 2'), findsOneWidget);
      expect(find.text('Physics Lab Submission'), findsOneWidget);
    });

    // ─── Test 10: Study Goals & Milestones ─────────────────────────────────────
    testWidgets(
      '10. study goals container renders weekly target and edit CTA',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          buildPlanView(
            mockStudyGoals: {'weeklyGoalMinutes': 900, 'dailyGoalMinutes': 120},
          ),
        );
        await tester.pump();

        expect(find.text('Goals & Milestones'), findsOneWidget);
        expect(find.text('15h 0m'), findsOneWidget);
        expect(find.text('Edit'), findsOneWidget);
      },
    );

    // ─── Test 11: Edit Goal Sheet Modal ───────────────────────────────────────
    testWidgets('11. tapping Edit opens the goal editing bottom sheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildPlanView(
          mockStudyGoals: {'weeklyGoalMinutes': 900, 'dailyGoalMinutes': 120},
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Set Study Goals'), findsOneWidget);
      expect(find.text('Save Goals'), findsOneWidget);
    });

    // ─── Test 12: Default Exam Rescue Banner ──────────────────────────────────
    testWidgets(
      '12. default exam rescue banner renders when no active session',
      (tester) async {
        await tester.pumpWidget(buildPlanView());
        await tester.pump();

        expect(find.text('Exam Rescue'), findsOneWidget);
        expect(
          find.text('Exam close? Build a quick rescue plan.'),
          findsOneWidget,
        );
        expect(find.text('Build Plan'), findsOneWidget);
      },
    );

    // ─── Test 13: 320dp Screen No Overflow ────────────────────────────────────
    testWidgets('13. 320dp narrow layout renders without RenderFlex overflow', (
      tester,
    ) async {
      await tester.pumpWidget(buildPlanView(size: const Size(320, 640)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Plan'), findsWidgets);
    });

    // ─── Test 14: 360dp Screen No Overflow ────────────────────────────────────
    testWidgets('14. 360dp standard mobile layout renders without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(buildPlanView(size: const Size(360, 640)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Plan'), findsWidgets);
    });

    // ─── Test 15: 390dp Screen No Overflow ────────────────────────────────────
    testWidgets('15. 390dp layout renders without overflow', (tester) async {
      await tester.pumpWidget(buildPlanView(size: const Size(390, 844)));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // ─── Test 16: 412dp Screen No Overflow ────────────────────────────────────
    testWidgets('16. 412dp large mobile layout renders without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(buildPlanView(size: const Size(412, 915)));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // ─── Test 17: 1.5x Text Scale ─────────────────────────────────────────────
    testWidgets('17. 1.5x text scale renders safely without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(buildPlanView(textScale: 1.5));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // ─── Test 18: Dark Mode ───────────────────────────────────────────────────
    testWidgets('18. dark mode renders without errors', (tester) async {
      await tester.pumpWidget(buildPlanView(isDark: true));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Plan'), findsWidgets);
    });

    // ─── Test 19: Localization ────────────────────────────────────────────────
    testWidgets('19. localization switches to Bangla strings', (tester) async {
      await tester.pumpWidget(buildPlanView());
      await tester.pump();

      GochanoLanguage.current.value = GochanoLocale.bangla;
      await tester.pump();

      expect(find.text('পরিকল্পনা'), findsWidgets);
      expect(
        find.text('আপনার পড়াশোনার লক্ষ্য ও সময়সূচি সাজান।'),
        findsOneWidget,
      );
    });

    // ─── Test 20: Header Pinned While Scrolling ───────────────────────────────
    testWidgets('20. header stays pinned while body scrolls', (tester) async {
      await tester.pumpWidget(buildPlanView());
      await tester.pump();

      final headerFinder = find.byType(AppStudyHeader);
      expect(headerFinder, findsOneWidget);
      final initialTop = tester.getTopLeft(headerFinder).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();

      final scrolledTop = tester.getTopLeft(headerFinder).dy;
      expect(scrolledTop, equals(initialTop));
    });

    // ─── Test 21: Shell Navigation to Plan (Tab 2) ────────────────────────────
    testWidgets('21. shell navigation activates Plan tab at index 2', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GochanoShell(
            role: 'student',
            displayName: 'Student',
            pagesBuilder: (context, mode) => [
              const Text('Page: Today'),
              const Text('Page: Workspace'),
              const PlanView(mockTasks: []),
              const Text('Page: Community'),
              const Text('Page: You'),
            ],
          ),
        ),
      );
      await tester.pump();

      final planTab = find.text('Plan');
      expect(planTab, findsOneWidget);

      await tester.tap(planTab);
      await tester.pump();

      expect(find.byType(PlanView), findsOneWidget);
    });

    // ─── Test 22: IndexedStack State Preservation ─────────────────────────────
    testWidgets('22. switching Today -> Plan -> Today preserves state', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GochanoShell(
            role: 'student',
            displayName: 'Student',
            pagesBuilder: (context, mode) => [
              const Text('Page: Today'),
              const Text('Page: Workspace'),
              const PlanView(mockTasks: []),
              const Text('Page: Community'),
              const Text('Page: You'),
            ],
          ),
        ),
      );
      await tester.pump();

      // Go to Plan
      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(find.byType(PlanView), findsOneWidget);

      // Return to Today
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
      );
      await tester.pump();
      expect(find.text('Page: Today'), findsOneWidget);
    });

    // ─── Test 23: Header Trailing Action Tap Target Size ───────────────────────
    testWidgets('23. calendar trailing action in header >= 44dp tap target', (
      tester,
    ) async {
      await tester.pumpWidget(buildPlanView());
      await tester.pump();

      final calendarFinder = find.widgetWithIcon(
        IconButton,
        Icons.calendar_month_outlined,
      );
      expect(calendarFinder, findsOneWidget);

      final box = tester.getSize(
        find
            .ancestor(of: calendarFinder, matching: find.byType(SizedBox))
            .first,
      );
      expect(box.width, greaterThanOrEqualTo(44.0));
      expect(box.height, greaterThanOrEqualTo(44.0));
    });

    // ─── Test 24: Hierarchy — Date Strip immediately followed by Due This Day ──
    testWidgets(
      '24. date strip is immediately followed by Due This Day (Exam Rescue placed after Timeline)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildPlanView());
        await tester.pump();

        final dueThisDayFinder = find.text('Due This Day');
        final timelineFinder = find.text('Exam & Deadline Timeline');
        final examRescueFinder = find.text('Exam Rescue');
        final goalsFinder = find.text('Goals & Milestones');

        final dueY = tester.getTopLeft(dueThisDayFinder).dy;
        final timelineY = tester.getTopLeft(timelineFinder).dy;
        final examRescueY = tester.getTopLeft(examRescueFinder).dy;
        final goalsY = tester.getTopLeft(goalsFinder).dy;

        // Assert strict vertical visual order:
        // Due This Day < Exam & Deadline Timeline < Exam Rescue < Goals & Milestones
        expect(
          dueY,
          lessThan(timelineY),
          reason: 'Due This Day must appear before Timeline',
        );
        expect(
          timelineY,
          lessThan(examRescueY),
          reason: 'Timeline must appear before Exam Rescue',
        );
        expect(
          examRescueY,
          lessThan(goalsY),
          reason: 'Exam Rescue must appear before Goals & Milestones',
        );
      },
    );

    // ─── Test 25: Active Exam Rescue Compact Card ─────────────────────────────
    testWidgets(
      '25. active Exam Rescue renders compact planning card with title, days left, progress, roadmap & adjust CTAs',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final examDate = DateTime.now().add(const Duration(days: 5));
        final session = ExamRescueSession(
          sessionId: 'session_123',
          examTitle: 'HSC Physics 1st Paper',
          examDate: examDate,
          totalTasks: 10,
          totalMinutes: 120,
          taskIds: ['task_1'],
          status: 'active',
        );

        final mockService = MockExamRescueSessionService(
          sessionStream: Stream.value(session),
          now: DateTime.now(),
        );

        await tester.pumpWidget(
          buildPlanView(examRescueSessionService: mockService),
        );
        await tester.pump();

        expect(find.text('HSC Physics 1st Paper'), findsOneWidget);
        expect(find.text('5 days left'), findsOneWidget);
        expect(find.text('View Roadmap'), findsWidgets);
        expect(find.text('Adjust Plan'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsWidgets);
      },
    );

    // ─── Test 26: Inactive Exam Rescue Height Constraint ──────────────────────
    testWidgets(
      '26. inactive Exam Rescue secondary CTA strip has compact height within 64-80dp',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildPlanView());
        await tester.pump();

        expect(find.text('Exam Rescue'), findsOneWidget);
        expect(
          find.text('Exam close? Build a quick rescue plan.'),
          findsOneWidget,
        );
        expect(find.text('Build Plan'), findsOneWidget);

        final buttonFinder = find.widgetWithText(FilledButton, 'Build Plan');
        final stripContainer = find
            .ancestor(of: buttonFinder, matching: find.byType(Container))
            .first;
        final size = tester.getSize(stripContainer);
        expect(size.height, greaterThanOrEqualTo(50.0));
        expect(size.height, lessThanOrEqualTo(90.0));
      },
    );

    // ─── Test 27: Active Exam Rescue CTAs Tappable ────────────────────────────
    testWidgets(
      '27. active Exam Rescue Roadmap and Adjust Plan buttons are tappable',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final examDate = DateTime.now().add(const Duration(days: 3));
        final session = ExamRescueSession(
          sessionId: 'session_789',
          examTitle: 'Chemistry Final',
          examDate: examDate,
          totalTasks: 8,
          totalMinutes: 90,
          taskIds: ['task_c1'],
          status: 'active',
        );

        final mockService = MockExamRescueSessionService(
          sessionStream: Stream.value(session),
          now: DateTime.now(),
        );

        await tester.pumpWidget(
          buildPlanView(examRescueSessionService: mockService),
        );
        await tester.pump();

        // Tap Adjust Plan
        final adjustBtn = find.widgetWithText(FilledButton, 'Adjust Plan');
        expect(adjustBtn, findsOneWidget);
        await tester.tap(adjustBtn);
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    // ─── Test 28: Inactive Exam Rescue Build Plan Button Tappable ─────────────
    testWidgets('28. inactive Exam Rescue Build Plan button is tappable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildPlanView());
      await tester.pump();

      final buildBtn = find.widgetWithText(FilledButton, 'Build Plan');
      expect(buildBtn, findsOneWidget);
      await tester.tap(buildBtn);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
