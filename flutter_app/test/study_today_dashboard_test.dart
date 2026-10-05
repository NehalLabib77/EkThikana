import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/app_design_system.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_session_service.dart';
import 'package:gochano/features/study/presentation/today/study_today_dashboard_view.dart';

class _MockRescueService extends ExamRescueSessionService {
  _MockRescueService({required this.sessionStream, required this.now});

  final Stream<ExamRescueSession?> sessionStream;

  @override
  final DateTime now;

  @override
  Stream<ExamRescueSession?> streamNearestActiveSession() => sessionStream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('StudyTodayDashboardView - Hierarchy & Components', () {
    testWidgets('renders all 7 approved sections with fallback hero', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int openedDestination = -1;
      bool profileOpened = false;

      final bootstrapData = {
        'profile': {
          'uid': 'test_student',
          'displayName': 'Farhan',
          'role': 'student',
        },
        'academicHealth': {
          'score': 88,
          'hasData': true,
          'headline': 'Consistent study streak',
        },
        'recommendation': {
          'available': true,
          'items': [
            {'title': 'Alkanes Revision', 'reason': 'Weak area identified in mock test'},
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyTodayDashboardView(
              displayName: 'Farhan',
              onOpenDestination: (idx) => openedDestination = idx,
              onOpenProfile: () => profileOpened = true,
              bootstrapData: bootstrapData,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // SECTION 1: HEADER
      expect(find.text('Gochano'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsWidgets);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

      // SECTION 2: GREETING & CONTEXTUAL STATUS
      expect(find.textContaining('Farhan'), findsOneWidget);

      // SECTION 3: HERO (Fallback hero when no active exam rescue)
      expect(find.text('Alkanes Revision'), findsOneWidget);
      expect(find.text('Weak area identified in mock test'), findsOneWidget);
      expect(find.text('Start Study Session'), findsOneWidget);

      // SECTION 4: TODAY'S PRIORITIES
      expect(find.text("Today's Priorities"), findsOneWidget);
      expect(find.text('See All'), findsWidgets);

      // SECTION 5: ZIKU COACH + FOCUS SESSION
      expect(find.text('Ziku Coach'), findsOneWidget);
      expect(find.text("I'm ready! 🚀"), findsOneWidget);
      expect(find.text('Focus Session'), findsOneWidget);
      expect(find.text('Start Focus Session'), findsOneWidget);

      // SECTION 6: CONTINUE LEARNING
      expect(find.text('Continue Learning'), findsOneWidget);

      // SECTION 7: SIMPLIFIED ACADEMIC HEALTH
      expect(find.text('Academic Health'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text('Consistent study streak'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);

      // Test tapping CTA in fallback hero (opens Plan destination 2)
      await tester.tap(find.text('Start Study Session'));
      await tester.pumpAndSettle();
      expect(openedDestination, equals(2)); // Plan tab

      // Test tapping profile avatar
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();
      expect(profileOpened, isTrue);
    });

    testWidgets('renders Active Exam Rescue hero when session is active', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final examDate = now.add(const Duration(days: 4));

      final activeSession = ExamRescueSession(
        sessionId: 'rescue_test_1',
        examTitle: 'Physics Paper 1',
        examDate: examDate,
        totalTasks: 4,
        totalMinutes: 120,
        createdAt: now.subtract(const Duration(hours: 2)),
        status: 'active',
      );

      final stubService = _MockRescueService(
        sessionStream: Stream.value(activeSession),
        now: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyTodayDashboardView(
              displayName: 'Farhan',
              onOpenDestination: (_) {},
              onOpenProfile: () {},
              examRescueSessionService: stubService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Exam Rescue Hero renders
      expect(find.text('Physics Paper 1'), findsOneWidget);
      expect(find.text('Exam Rescue'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // 4 days left
      expect(find.text('days left'), findsOneWidget);
      expect(find.text("Start Today's Plan"), findsOneWidget);
    });

    testWidgets('adapts responsively on narrow 320dp screen without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyTodayDashboardView(
              displayName: 'S',
              onOpenDestination: (_) {},
              onOpenProfile: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Gochano'), findsOneWidget);
      expect(find.text('Your day is clear'), findsOneWidget);
    });
  });

  group('Design System Components Verification', () {
    testWidgets('AppHeroCard renders stats and responds to CTA tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppHeroCard(
              title: 'Linear Algebra',
              subtitle: 'Matrices and Eigenvectors',
              badgeText: 'PRIORITY',
              stats: const [
                HeroStatItem(icon: Icons.calendar_today, value: '3', label: 'days'),
                HeroStatItem(icon: Icons.timer, value: '45m', label: 'today'),
              ],
              ctaLabel: 'Begin Now',
              onCta: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Linear Algebra'), findsOneWidget);
      expect(find.text('Matrices and Eigenvectors'), findsOneWidget);
      expect(find.text('PRIORITY'), findsOneWidget);
      expect(find.text('Begin Now'), findsOneWidget);

      await tester.tap(find.text('Begin Now'));
      expect(tapped, isTrue);
    });

    testWidgets('AppPriorityTaskCard renders duration, category and completion checkbox', (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPriorityTaskCard(
              title: 'Complete Worksheet 4',
              subtitle: 'Physics 101',
              durationMinutes: 25,
              category: 'Assignment',
              categoryTint: CategoryTint.coral,
              onComplete: () => completed = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Complete Worksheet 4'), findsOneWidget);
      expect(find.text('Physics 101'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(find.text('Assignment'), findsOneWidget);

      // Tap circular checkbox
      await tester.tap(find.byKey(const Key('task_complete_button')));
      expect(completed, isTrue);
    });

    testWidgets('AppSimplifiedAcademicHealthCard renders score ring and metrics', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSimplifiedAcademicHealthCard(
              score: 92,
              hasData: true,
              headline: 'Exceptional consistency',
              strongestMetric: 'Focus +15%',
              attentionOrStreakMetric: '5 Day Streak',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('92'), findsOneWidget);
      expect(find.text('/100'), findsOneWidget);
      expect(find.text('Exceptional consistency'), findsOneWidget);
      expect(find.text('Focus +15%'), findsOneWidget);
      expect(find.text('5 Day Streak'), findsOneWidget);

      await tester.tap(find.text('92'));
      expect(tapped, isTrue);
    });
  });
}
