import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/planner/plan_view.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_preview_screen.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_setup_sheet.dart';
import 'package:gochano/services/api_service.dart';

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

  group('Final T3 Async & Error Hardening Audit', () {
    final auditPlan = ExamRescuePlan(
      examTitle: 'Advanced Microprocessors',
      daysRemaining: 2,
      totalEstimatedMinutes: 240,
      strategySummary: 'Master pipelining hazards and memory hierarchy.',
      sourceMode: 'materials',
      generationMode: 'ai',
      days: const [
        ExamRescueDay(
          dayNumber: 1,
          dateOffset: 0,
          theme: 'Instruction Pipeline & Hazards',
          targetMinutes: 120,
          items: [
            ExamRescueItem(
              title: 'Data Hazard Forwarding Review',
              type: 'study',
              estimatedMinutes: 60,
              actionNote: 'Focus on load-use hazard stalls.',
            ),
            ExamRescueItem(
              title: 'Pipeline Practice Quiz',
              type: 'quiz',
              estimatedMinutes: 60,
            ),
          ],
        ),
        ExamRescueDay(
          dayNumber: 2,
          dateOffset: 1,
          theme: 'Cache Coherence & Branch Prediction',
          targetMinutes: 120,
          items: [
            ExamRescueItem(
              title: 'MESI Protocol Drill',
              type: 'practice',
              estimatedMinutes: 60,
            ),
            ExamRescueItem(
              title: 'Final Revision Checklist',
              type: 'revision',
              estimatedMinutes: 60,
            ),
          ],
        ),
      ],
    );

    testWidgets('tap "Generate Rescue Plan" twice rapidly calls generator once and pushes one preview', (tester) async {
      int callCount = 0;
      final completer = Completer<ExamRescuePlan>();

      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            initialTitle: 'Advanced Microprocessors',
            initialMaterials: const [
              {'id': 'm1', 'title': 'Ch1.pdf'}
            ],
            planGenerator: ({
              required String examTitle,
              required DateTime examDate,
              int dailyMinutes = 120,
              List<String> materialIds = const [],
              String? extraTopics,
            }) async {
              callCount++;
              return completer.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final genButton = find.text('Generate Rescue Plan');
      expect(genButton, findsOneWidget);

      // Tap twice rapidly
      await tester.tap(genButton);
      await tester.tap(genButton);
      await tester.pump();

      // Verify only 1 invocation fired
      expect(callCount, equals(1));
      expect(find.text('Generating Rescue Plan…'), findsOneWidget);

      // Complete the future
      completer.complete(auditPlan);
      await tester.pumpAndSettle();

      // Only one preview screen is pushed
      expect(find.byType(ExamRescuePreviewScreen), findsOneWidget);
      expect(find.text('ADVANCED MICROPROCESSORS'), findsOneWidget);
    });

    testWidgets('dismiss/dispose sheet during generation does not throw or call setState', (tester) async {
      final completer = Completer<ExamRescuePlan>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: ctx,
                    builder: (_) => ExamRescueSetupSheet(
                      initialTitle: 'Advanced Microprocessors',
                      initialMaterials: const [
                        {'id': 'm1', 'title': 'Ch1.pdf'}
                      ],
                      planGenerator: ({
                        required String examTitle,
                        required DateTime examDate,
                        int dailyMinutes = 120,
                        List<String> materialIds = const [],
                        String? extraTopics,
                      }) => completer.future,
                    ),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Start generation
      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pump();

      expect(find.text('Generating Rescue Plan…'), findsOneWidget);

      // Dismiss/pop sheet while request is pending
      Navigator.of(tester.element(find.byType(ExamRescueSetupSheet))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(ExamRescueSetupSheet), findsNothing);

      // Complete future after sheet is disposed
      completer.complete(auditPlan);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ExamRescuePreviewScreen), findsNothing);
    });

    testWidgets('429 quota error displays specific daily AI limit message', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            initialTitle: 'Advanced Microprocessors',
            initialMaterials: const [
              {'id': 'm1', 'title': 'Ch1.pdf'}
            ],
            planGenerator: ({
              required String examTitle,
              required DateTime examDate,
              int dailyMinutes = 120,
              List<String> materialIds = const [],
              String? extraTopics,
            }) async {
              throw ApiException('Quota exceeded', statusCode: 429);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Daily AI plan generation limit reached. Please try again tomorrow or upgrade your plan.',
        ),
        findsOneWidget,
      );
      expect(find.text('Something went wrong'), findsNothing);
    });

    testWidgets('network/offline failure displays dedicated internet connection error', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            initialTitle: 'Advanced Microprocessors',
            initialMaterials: const [
              {'id': 'm1', 'title': 'Ch1.pdf'}
            ],
            planGenerator: ({
              required String examTitle,
              required DateTime examDate,
              int dailyMinutes = 120,
              List<String> materialIds = const [],
              String? extraTopics,
            }) async {
              throw ApiException(
                'Cannot reach the Gochano backend. Check internet/Render status and try again.',
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cannot reach the Gochano backend. Check internet/Render status and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('successful generation flow: Setup -> Generate -> Preview screen with days', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            initialTitle: 'Advanced Microprocessors',
            initialMaterials: const [
              {'id': 'm1', 'title': 'Ch1.pdf'}
            ],
            planGenerator: ({
              required String examTitle,
              required DateTime examDate,
              int dailyMinutes = 120,
              List<String> materialIds = const [],
              String? extraTopics,
            }) async => auditPlan,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();

      expect(find.byType(ExamRescuePreviewScreen), findsOneWidget);
      expect(find.text('ADVANCED MICROPROCESSORS'), findsOneWidget);
      expect(find.text('Based on your selected materials'), findsOneWidget);
      expect(find.text('Instruction Pipeline & Hazards'), findsOneWidget);
      expect(find.text('Data Hazard Forwarding Review'), findsOneWidget);
      expect(find.text('Cache Coherence & Branch Prediction'), findsOneWidget);
      expect(find.text('MESI Protocol Drill'), findsOneWidget);
    });

    testWidgets('date boundary tests: Today, +14d accepted; +15d, past rejected', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // 1. Today accepted
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            key: const ValueKey('boundary-today'),
            initialTitle: 'Cram Exam',
            initialDate: today,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Exam is today (1-day emergency cram)'), findsOneWidget);

      // 2. Today + 14 days accepted
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            key: const ValueKey('boundary-14d'),
            initialTitle: 'Future Exam',
            initialDate: today.add(const Duration(days: 14)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('14 days remaining'), findsOneWidget);

      // 3. Past date rejected
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            key: const ValueKey('boundary-past'),
            initialTitle: 'Past Exam',
            initialDate: today.subtract(const Duration(days: 1)),
            initialMaterials: const [
              {'id': 'm1', 'title': 'Ch1.pdf'}
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Exam date cannot be in the past.'), findsOneWidget);

      // 4. Today + 15 days rejected
      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            key: const ValueKey('boundary-15d'),
            initialTitle: 'Far Exam',
            initialDate: today.add(const Duration(days: 15)),
            initialMaterials: const [
              {'id': 'm1', 'title': 'Ch1.pdf'}
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Rescue Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Exam date cannot be more than 14 days away.'), findsOneWidget);
    });

    testWidgets('material selection boundaries: max 3, deduplication, removal and replacement', (tester) async {
      int pickerCallCount = 0;
      List<Map<String, String>> pickerBatch = [];

      await tester.pumpWidget(
        _buildWrapper(
          ExamRescueSetupSheet(
            initialTitle: 'Materials Test',
            materialPicker: (ctx) async {
              pickerCallCount++;
              return pickerBatch;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 of 3 selected'), findsOneWidget);

      // 1. Pick 1 material
      pickerBatch = [
        {'id': 'm1', 'title': 'Doc 1.pdf'},
      ];
      await tester.ensureVisible(find.text('+ Select Materials'));
      await tester.tap(find.text('+ Select Materials'));
      await tester.pumpAndSettle();

      expect(pickerCallCount, equals(1));
      expect(find.text('1 of 3 selected'), findsOneWidget);
      expect(find.text('Doc 1.pdf'), findsOneWidget);

      // 2. Pick duplicate item -> deduplicated, counter stays 1
      pickerBatch = [
        {'id': 'm1', 'title': 'Doc 1.pdf'},
      ];
      await tester.ensureVisible(find.text('+ Select Materials'));
      await tester.tap(find.text('+ Select Materials'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 selected'), findsOneWidget);

      // 3. Pick 3 more items (m2, m3, m4) -> only 2 slots remain, m4 is rejected, button disappears
      pickerBatch = [
        {'id': 'm2', 'title': 'Doc 2.pdf'},
        {'id': 'm3', 'title': 'Doc 3.pdf'},
        {'id': 'm4', 'title': 'Doc 4.pdf'},
      ];
      await tester.ensureVisible(find.text('+ Select Materials'));
      await tester.tap(find.text('+ Select Materials'));
      await tester.pumpAndSettle();

      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(find.text('Doc 2.pdf'), findsOneWidget);
      expect(find.text('Doc 3.pdf'), findsOneWidget);
      expect(find.text('Doc 4.pdf'), findsNothing);
      expect(find.text('+ Select Materials'), findsNothing); // Button hidden when 3 selected

      // 4. Remove one material ('Doc 1.pdf') -> button reappears
      final removeButtons = find.byTooltip('Remove material');
      expect(removeButtons, findsNWidgets(3));
      await tester.ensureVisible(removeButtons.first);
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(find.text('Doc 1.pdf'), findsNothing);
      expect(find.text('+ Select Materials'), findsOneWidget);

      // 5. Now pick 'Doc 4.pdf' -> accepted, total 3 of 3 selected
      pickerBatch = [
        {'id': 'm4', 'title': 'Doc 4.pdf'},
      ];
      await tester.ensureVisible(find.text('+ Select Materials'));
      await tester.tap(find.text('+ Select Materials'));
      await tester.pumpAndSettle();

      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(find.text('Doc 4.pdf'), findsOneWidget);
      expect(find.text('+ Select Materials'), findsNothing);
    });

    testWidgets('regenerate concurrency: double-tap invokes generator once and replaces in-memory plan once', (tester) async {
      int regenCalls = 0;
      final regenCompleter = Completer<ExamRescuePlan>();

      final updatedPlan = auditPlan.copyWith(
        strategySummary: 'UPDATED STRATEGY: Mastered cache coherence.',
      );

      await tester.pumpWidget(
        _buildWrapper(
          ExamRescuePreviewScreen(
            plan: auditPlan,
            initialTitle: 'Advanced Microprocessors',
            initialDate: DateTime.now().add(const Duration(days: 2)),
            initialDailyMinutes: 120,
            planGenerator: ({
              required String examTitle,
              required DateTime examDate,
              int dailyMinutes = 120,
              List<String> materialIds = const [],
              String? extraTopics,
            }) async {
              regenCalls++;
              return regenCompleter.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Master pipelining hazards and memory hierarchy.'), findsOneWidget);

      // Tap Regenerate twice rapidly
      final regenBtn = find.text('Regenerate');
      await tester.tap(regenBtn);
      await tester.tap(regenBtn);
      await tester.pump();

      // Only one call fired
      expect(regenCalls, equals(1));
      expect(find.text('Regenerating…'), findsOneWidget);

      // Complete the regeneration
      regenCompleter.complete(updatedPlan);
      await tester.pumpAndSettle();

      // In-memory plan was replaced once
      expect(find.text('UPDATED STRATEGY: Mastered cache coherence.'), findsOneWidget);
      expect(find.text('Regenerate'), findsOneWidget);
    });
  });
}

