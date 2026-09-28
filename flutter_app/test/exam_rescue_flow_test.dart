import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/planner/plan_view.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_preview_screen.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_setup_sheet.dart';

Widget _buildWrapper(
  Widget child, {
  Size size = const Size(390, 844),
  double textScaleFactor = 1.0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScaleFactor),
      ),
      child: Scaffold(body: child),
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

  group('Phase T3 — Exam Rescue Setup Sheet', () {
    testWidgets('renders all setup form elements cleanly', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Exam Rescue'), findsOneWidget);
      expect(find.text('Build a focused plan before your exam.'), findsOneWidget);
      expect(find.text('Exam / Subject'), findsOneWidget);
      expect(find.text('Exam Date'), findsOneWidget);
      expect(find.text('Daily Study Time'), findsOneWidget);
      expect(find.text('Study Materials'), findsOneWidget);
      expect(find.text('Generate Rescue Plan'), findsOneWidget);
    });

    testWidgets('validates empty and short exam title inline', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap generate with empty title
      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter an exam or subject title.'),
        findsOneWidget,
      );

      // Enter single character title
      await tester.enterText(find.byType(TextField).first, 'A');
      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Exam title must be at least 2 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('date chips update remaining days indicator', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Today
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Exam is today (1-day emergency cram)'), findsOneWidget);

      // Tap Tomorrow
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      expect(find.text('1 day remaining (Tomorrow)'), findsOneWidget);

      // Tap 5 Days
      await tester.tap(find.text('5 Days'));
      await tester.pumpAndSettle();
      expect(find.text('5 days remaining'), findsOneWidget);
    });

    testWidgets('daily study time chips update selection', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2h 0m'), findsOneWidget);

      await tester.tap(find.text('1 hour'));
      await tester.pumpAndSettle();
      expect(find.text('1h 0m'), findsOneWidget);

      await tester.tap(find.text('3 hours'));
      await tester.pumpAndSettle();
      expect(find.text('3h 0m'), findsOneWidget);

      await tester.tap(find.text('4 hours'));
      await tester.pumpAndSettle();
      expect(find.text('4h 0m'), findsOneWidget);
    });

    testWidgets('renders initial materials and allows removing them', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(
            initialTitle: 'Database Systems Final',
            initialMaterials: [
              {'id': 'mat-1', 'title': 'Lecture 1.pdf'},
              {'id': 'mat-2', 'title': 'Chapter 3 Notes'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lecture 1.pdf'), findsOneWidget);
      expect(find.text('Chapter 3 Notes'), findsOneWidget);
      expect(find.text('2 of 3 selected'), findsOneWidget);

      // Tap remove on first material
      final removeButtons = find.byTooltip('Remove material');
      expect(removeButtons, findsNWidgets(2));
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Lecture 1.pdf'), findsNothing);
      expect(find.text('Chapter 3 Notes'), findsOneWidget);
      expect(find.text('1 of 3 selected'), findsOneWidget);
    });

    testWidgets('zero materials flow prompts confirmation dialog', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(
            initialTitle: 'Organic Chemistry',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();

      // Confirmation dialog should be visible
      expect(find.text('No Materials Selected'), findsOneWidget);
      expect(
        find.text('No materials selected. Gochano will create a general subject-based rescue plan.'),
        findsOneWidget,
      );
      expect(find.text('Select Materials'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('responsive 320dp width renders without overflow', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(
            initialTitle: 'Mobile Architecture',
            initialMaterials: [
              {'id': 'm1', 'title': 'Very Long Document Name That Could Potentially Overflow.pdf'}
            ],
          ),
          size: const Size(320, 640),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Exam Rescue'), findsOneWidget);
    });

    testWidgets('text scale 2.0x renders without overflow', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const ExamRescueSetupSheet(
            initialTitle: 'Algorithms',
          ),
          textScaleFactor: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Phase T3 — Exam Rescue Preview Screen', () {
    final samplePlan = ExamRescuePlan(
      examTitle: 'Optical Fiber Midterm',
      daysRemaining: 3,
      totalEstimatedMinutes: 360,
      strategySummary: 'Prioritize dispersion formulas, detector physics, and run full mock quiz.',
      sourceMode: 'materials',
      generationMode: 'ai',
      days: [
        const ExamRescueDay(
          dayNumber: 1,
          dateOffset: 0,
          theme: 'Fiber Propagation Fundamentals',
          targetMinutes: 120,
          items: [
            ExamRescueItem(
              title: 'Total Internal Reflection & Modes',
              type: 'study',
              estimatedMinutes: 60,
              materialId: 'mat-fiber-1',
              actionNote: 'Review derivations in chapter 1.',
            ),
            ExamRescueItem(
              title: 'Numerical Aperture Problems',
              type: 'practice',
              estimatedMinutes: 60,
            ),
          ],
        ),
        const ExamRescueDay(
          dayNumber: 2,
          dateOffset: 1,
          theme: 'Attenuation & Dispersion',
          targetMinutes: 120,
          items: [
            ExamRescueItem(
              title: 'Chromatic Dispersion Review',
              type: 'study',
              estimatedMinutes: 60,
            ),
            ExamRescueItem(
              title: 'Checkpoint Quiz',
              type: 'quiz',
              estimatedMinutes: 60,
            ),
          ],
        ),
        const ExamRescueDay(
          dayNumber: 3,
          dateOffset: 2,
          theme: 'Mock Exam & Final Formula Polish',
          targetMinutes: 120,
          items: [
            ExamRescueItem(
              title: 'Full Simulation Mock Quiz',
              type: 'quiz',
              estimatedMinutes: 60,
            ),
            ExamRescueItem(
              title: 'Final Formula Polish',
              type: 'revision',
              estimatedMinutes: 60,
            ),
          ],
        ),
      ],
    );

    testWidgets('renders preview header, badges, strategy, and days', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescuePreviewScreen(
            plan: samplePlan,
            initialTitle: 'Optical Fiber Midterm',
            initialDate: DateTime.now().add(const Duration(days: 3)),
            initialDailyMinutes: 120,
            initialMaterials: const [
              {'id': 'mat-fiber-1', 'title': 'Fiber_Optics_Ch1.pdf'}
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OPTICAL FIBER MIDTERM'), findsOneWidget);
      expect(find.text('3 days remaining'), findsOneWidget);
      expect(find.text('2h / day'), findsOneWidget);
      expect(find.text('Total: 6h'), findsOneWidget);
      expect(find.text('Based on your selected materials'), findsOneWidget);
      expect(find.text('AI Rescue Strategy'), findsOneWidget);

      // Verify days and items render
      expect(find.text('Fiber Propagation Fundamentals'), findsOneWidget);
      expect(find.text('Total Internal Reflection & Modes'), findsOneWidget);
      expect(find.text('Study'), findsNWidgets(2));
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('Quiz'), findsNWidgets(2));
      expect(find.text('Revision'), findsOneWidget);

      // Buttons
      expect(find.text('Edit / Back'), findsOneWidget);
      expect(find.text('Regenerate'), findsOneWidget);
    });

    testWidgets('general subject plan displays general plan label', (tester) async {
      final generalPlan = samplePlan.copyWith(
        sourceMode: 'general_subject',
      );

      await tester.pumpWidget(
        _buildWrapper(
          ExamRescuePreviewScreen(
            plan: generalPlan,
            initialTitle: 'Optical Fiber Midterm',
            initialDate: DateTime.now().add(const Duration(days: 3)),
            initialDailyMinutes: 120,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('General subject-based plan'), findsOneWidget);
      expect(find.text('Based on your selected materials'), findsNothing);
    });

    testWidgets('fallback mode displays fallback transparency label', (tester) async {
      final fallbackPlan = samplePlan.copyWith(
        generationMode: 'fallback',
      );

      await tester.pumpWidget(
        _buildWrapper(
          ExamRescuePreviewScreen(
            plan: fallbackPlan,
            initialTitle: 'Optical Fiber Midterm',
            initialDate: DateTime.now().add(const Duration(days: 3)),
            initialDailyMinutes: 120,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("Quick recovery plan created using Gochano's fallback planner."),
        findsOneWidget,
      );
    });

    testWidgets('in-memory item removal removes item and updates total minutes', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescuePreviewScreen(
            plan: samplePlan,
            initialTitle: 'Optical Fiber Midterm',
            initialDate: DateTime.now().add(const Duration(days: 3)),
            initialDailyMinutes: 120,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total: 6h'), findsOneWidget);
      expect(find.text('Total Internal Reflection & Modes'), findsOneWidget);

      // Remove the first item
      final deleteButtons = find.byTooltip('Remove item');
      expect(deleteButtons, findsWidgets);
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      // Total minutes should now be 5h (300 min)
      expect(find.text('Total Internal Reflection & Modes'), findsNothing);
      expect(find.text('Total: 5h'), findsOneWidget);
    });

    testWidgets('responsive 320dp and 2.0x text scale renders without overflow', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescuePreviewScreen(
            plan: samplePlan,
            initialTitle: 'Optical Fiber Midterm',
            initialDate: DateTime.now().add(const Duration(days: 3)),
            initialDailyMinutes: 120,
          ),
          size: const Size(320, 640),
          textScaleFactor: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Bangla mode renders localized titles without overflow', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          ExamRescuePreviewScreen(
            plan: samplePlan,
            initialTitle: 'অপটিক্যাল ফাইবার পরীক্ষা',
            initialDate: DateTime.now().add(const Duration(days: 3)),
            initialDailyMinutes: 120,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('এক্সাম রেসকিউ'), findsOneWidget);
      expect(find.text('রেসকিউ প্ল্যান প্রিভিউ'), findsOneWidget);
      expect(find.text('এআই রেসকিউ কৌশল'), findsOneWidget);
      expect(find.text('আবার তৈরি করুন'), findsOneWidget);
    });

    testWidgets('renders Exam Rescue banner on PlanView', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          const PlanView(),
        ),
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
}

