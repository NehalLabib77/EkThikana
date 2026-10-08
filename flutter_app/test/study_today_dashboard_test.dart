import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/app_design_system.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_session_service.dart';
import 'package:gochano/features/study/presentation/today/greeting_presentation.dart';
import 'package:gochano/features/study/presentation/today/study_today_dashboard_view.dart';
import 'package:gochano/widgets/language_toggle.dart';

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

  group('StudyTodayDashboardView - Grouped Architecture & Header Cleanup', () {
    testWidgets('renders all approved sections, dynamic greeting, grouped containers, and clean header', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int openedDestination = -1;

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
              onOpenProfile: () {},
              bootstrapData: bootstrapData,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. FIXED TOP APP BAR: Logo only, real gradient, no "Gochano" text, no tagline, no avatar
      expect(find.text('Gochano'), findsNothing);
      expect(find.text('Study Better. A Brighter You.'), findsNothing);
      expect(find.byType(Image), findsWidgets); // Logo mark remains
      expect(find.byType(LanguageToggle), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      // Profile avatar ABSENT from app bar
      expect(find.byType(CircleAvatar), findsNothing);

      // 2. DYNAMIC GREETING CARD
      expect(find.byType(AppGreetingCard), findsOneWidget);
      expect(find.textContaining('Farhan'), findsOneWidget);
      // "Today looks good" status card no longer renders
      expect(find.text('Today looks good!'), findsNothing);
      expect(find.text('Your day is clear'), findsNothing);

      // 3. HERO (Fallback hero when no active exam rescue)
      expect(find.text('Alkanes Revision'), findsOneWidget);
      expect(find.text('Weak area identified in mock test'), findsOneWidget);
      expect(find.text('Start Study Session'), findsOneWidget);

      // 4. TODAY'S PRIORITIES (Grouped inside AppSectionContainer)
      expect(find.widgetWithText(AppSectionContainer, "Today's Priorities"), findsOneWidget);
      expect(find.text('See All'), findsWidgets);

      // 5. ZIKU COACH + FOCUS SESSION
      expect(find.text('Ziku Coach'), findsOneWidget);
      expect(find.text("I'm ready! 🚀"), findsOneWidget);
      expect(find.text('Focus Session'), findsOneWidget);
      expect(find.text('Start Focus Session'), findsOneWidget);

      // 6. CONTINUE LEARNING (Grouped inside AppSectionContainer)
      expect(find.widgetWithText(AppSectionContainer, 'Continue Learning'), findsOneWidget);

      // 7. SIMPLIFIED ACADEMIC HEALTH (Grouped inside AppSectionContainer)
      expect(find.widgetWithText(AppSectionContainer, 'Academic Health'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text('Consistent study streak'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);

      // Test tapping CTA in fallback hero (opens Plan destination 2)
      await tester.tap(find.text('Start Study Session'));
      await tester.pumpAndSettle();
      expect(openedDestination, equals(2)); // Plan tab
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
      expect(find.text('Gochano'), findsNothing);
      expect(find.byType(LanguageToggle), findsOneWidget);
      expect(find.byType(AppGreetingCard), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('handles large text scaling gracefully without critical overflow', (tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 22),
            ),
          ),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: StudyTodayDashboardView(
                displayName: 'Student With A Very Long Name',
                onOpenDestination: (_) {},
                onOpenProfile: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Gochano'), findsNothing);
      expect(find.byType(LanguageToggle), findsOneWidget);
    });

    testWidgets('fixed header stays pinned when scrolling while greeting and body cards scroll', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyTodayDashboardView(
              displayName: 'Farhan',
              onOpenDestination: (_) {},
              onOpenProfile: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header controls and greeting are initially visible
      expect(find.text('Gochano'), findsNothing);
      expect(find.text('Study Better. A Brighter You.'), findsNothing);
      expect(find.byType(LanguageToggle), findsOneWidget);
      expect(find.byType(AppGreetingCard), findsOneWidget);

      final initialHeaderTop = tester.getTopLeft(find.byType(LanguageToggle)).dy;
      final initialGreetingTop = tester.getTopLeft(find.byType(AppGreetingCard)).dy;

      // Scroll CustomScrollView up by 30px
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -30));
      await tester.pumpAndSettle();

      // FIXED HEADER: Top coordinate does not move even when scrolled
      final scrolledHeaderTop = tester.getTopLeft(find.byType(LanguageToggle)).dy;
      expect(scrolledHeaderTop, equals(initialHeaderTop));
      expect(find.text('Gochano'), findsNothing);
      expect(find.text('Study Better. A Brighter You.'), findsNothing);
      expect(find.byType(LanguageToggle), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

      // Verify compact inset floating header properties
      final headerContainerFinder = find.ancestor(
        of: find.byType(LanguageToggle),
        matching: find.byType(Container),
      ).first;
      final headerContainer = tester.widget<Container>(headerContainerFinder);
      final decoration = headerContainer.decoration as BoxDecoration;

      // 1. Gradient remains
      expect(decoration.gradient, equals(AppGradients.todayAppBar));

      // 2. 18dp rounded radius exists
      expect(decoration.borderRadius, equals(GochanoRadius.appBarSurfaceAll));

      // 3. Subtle border exists
      expect(decoration.border, isNotNull);

      // 4. Visible gradient surface is narrower than viewport (400 - 2*14 = 372dp)
      final headerRenderBox = tester.renderObject(headerContainerFinder) as RenderBox;
      expect(headerRenderBox.size.width, equals(400.0 - (14.0 * 2)));
      expect(headerRenderBox.size.width, lessThan(400.0));

      // 5. Left/right inset exists (14dp on 400dp width)
      final headerTopLeft = tester.getTopLeft(headerContainerFinder);
      expect(headerTopLeft.dx, equals(14.0));

      // SCROLLABLE GREETING: Position moved upwards
      final scrolledGreetingTop = tester.getTopLeft(find.byType(AppGreetingCard)).dy;
      expect(scrolledGreetingTop, lessThan(initialGreetingTop));
    });

    testWidgets('compact inset floating header applies 10dp inset on 320dp narrow screen without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyTodayDashboardView(
              displayName: 'Student',
              onOpenDestination: (_) {},
              onOpenProfile: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final headerContainerFinder = find.ancestor(
        of: find.byType(LanguageToggle),
        matching: find.byType(Container),
      ).first;
      final headerContainer = tester.widget<Container>(headerContainerFinder);
      final decoration = headerContainer.decoration as BoxDecoration;

      expect(decoration.gradient, equals(AppGradients.todayAppBar));
      expect(decoration.borderRadius, equals(GochanoRadius.appBarSurfaceAll));

      // Width is 320 - 2*10 = 300dp
      final headerRenderBox = tester.renderObject(headerContainerFinder) as RenderBox;
      expect(headerRenderBox.size.width, equals(320.0 - (10.0 * 2)));
      expect(headerRenderBox.size.width, lessThan(320.0));

      final headerTopLeft = tester.getTopLeft(headerContainerFinder);
      expect(headerTopLeft.dx, equals(10.0));

      // Logo, Language, Search, Notification all present
      expect(find.byType(Image), findsWidgets);
      expect(find.byType(LanguageToggle), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

      // Absent: Gochano text, tagline, avatar
      expect(find.text('Gochano'), findsNothing);
      expect(find.text('Study Better. A Brighter You.'), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('compact header controls preserve accessible touch targets of at least 44dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyTodayDashboardView(
              displayName: 'Student',
              onOpenDestination: (_) {},
              onOpenProfile: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search button tap target >= 44dp
      final searchButtonFinder = find.widgetWithIcon(IconButton, Icons.search_rounded);
      expect(searchButtonFinder, findsOneWidget);
      final searchBox = tester.getSize(find.ancestor(
        of: searchButtonFinder,
        matching: find.byType(SizedBox),
      ).first);
      expect(searchBox.width, greaterThanOrEqualTo(44.0));
      expect(searchBox.height, greaterThanOrEqualTo(44.0));

      // Notification button tap target >= 44dp
      final notificationButtonFinder = find.widgetWithIcon(IconButton, Icons.notifications_outlined);
      expect(notificationButtonFinder, findsOneWidget);
      final notificationBox = tester.getSize(find.ancestor(
        of: notificationButtonFinder,
        matching: find.byType(SizedBox),
      ).first);
      expect(notificationBox.width, greaterThanOrEqualTo(44.0));
      expect(notificationBox.height, greaterThanOrEqualTo(44.0));

      // Language toggle tap target >= 44dp height
      final languageToggleFinder = find.byType(LanguageToggle);
      expect(languageToggleFinder, findsOneWidget);
      final languageToggleBox = tester.getSize(languageToggleFinder);
      expect(languageToggleBox.height, greaterThanOrEqualTo(44.0));

      // Unread notification badge remains visible
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

      // Header remains visually compact
      final headerContainerFinder = find.ancestor(
        of: find.byType(LanguageToggle),
        matching: find.byType(Container),
      ).first;
      final headerBox = tester.getSize(headerContainerFinder);
      expect(headerBox.height, lessThanOrEqualTo(56.0));
    });
  });

  group('GreetingPresentation Deterministic Tests', () {
    test('Early Morning (5:00 - 8:59) resolves correctly', () {
      final early = DateTime(2026, 10, 5, 6, 30);
      final p = GreetingPresentation.forTime(early);
      expect(p.period, GreetingPeriod.earlyMorning);
      expect(p.greetingEn, 'Good Morning');
      expect(p.greetingBn, 'শুভ সকাল');
      expect(p.icon, Icons.wb_twilight_rounded);
      expect(p.gradient, AppGradients.greetingEarlyMorning);
    });

    test('Morning (9:00 - 11:59) resolves correctly', () {
      final morning = DateTime(2026, 10, 5, 10, 15);
      final p = GreetingPresentation.forTime(morning);
      expect(p.period, GreetingPeriod.morning);
      expect(p.greetingEn, 'Good Morning');
      expect(p.greetingBn, 'শুভ সকাল');
      expect(p.icon, Icons.wb_sunny_rounded);
      expect(p.gradient, AppGradients.greetingMorning);
    });

    test('Afternoon (12:00 - 16:59) resolves correctly', () {
      final afternoon = DateTime(2026, 10, 5, 14, 0);
      final p = GreetingPresentation.forTime(afternoon);
      expect(p.period, GreetingPeriod.afternoon);
      expect(p.greetingEn, 'Good Afternoon');
      expect(p.greetingBn, 'শুভ অপরাহ্ন');
      expect(p.icon, Icons.wb_cloudy_rounded);
      expect(p.gradient, AppGradients.greetingAfternoon);
    });

    test('Evening (17:00 - 19:59) resolves correctly', () {
      final evening = DateTime(2026, 10, 5, 18, 30);
      final p = GreetingPresentation.forTime(evening);
      expect(p.period, GreetingPeriod.evening);
      expect(p.greetingEn, 'Good Evening');
      expect(p.greetingBn, 'শুভ সন্ধ্যা');
      expect(p.icon, Icons.wb_twilight_rounded);
      expect(p.gradient, AppGradients.greetingEvening);
    });

    test('Night (20:00 - 4:59) resolves correctly', () {
      final night = DateTime(2026, 10, 5, 22, 45);
      final p = GreetingPresentation.forTime(night);
      expect(p.period, GreetingPeriod.night);
      expect(p.greetingEn, 'Good Evening');
      expect(p.greetingBn, 'শুভ সন্ধ্যা');
      expect(p.icon, Icons.nights_stay_rounded);
      expect(p.gradient, AppGradients.greetingNight);
    });
  });

  group('Design System Components Verification', () {
    testWidgets('AppGreetingCard renders greeting, name, and visual icon badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppGreetingCard(
              userName: 'Nafis',
              dateTime: DateTime(2026, 10, 5, 14, 30),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Good Afternoon'), findsOneWidget);
      expect(find.textContaining('Nafis'), findsOneWidget);
      expect(find.text('Keep the momentum going.'), findsOneWidget);
      expect(find.byIcon(Icons.wb_cloudy_rounded), findsOneWidget);
    });

    testWidgets('AppSectionContainer renders header row and content', (tester) async {
      bool tappedAction = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSectionContainer(
              title: "Today's Priorities",
              icon: Icons.track_changes_rounded,
              actionLabel: 'See All',
              onAction: () => tappedAction = true,
              child: const Text('Priority Task Item'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text("Today's Priorities"), findsOneWidget);
      expect(find.text('See All'), findsOneWidget);
      expect(find.text('Priority Task Item'), findsOneWidget);
      expect(find.byIcon(Icons.track_changes_rounded), findsOneWidget);

      await tester.tap(find.text('See All'));
      expect(tappedAction, isTrue);
    });

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
