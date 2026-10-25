// Widget tests for PastPaperScreen visual polish, state presentation, and interaction integrity.
//
// Verifies:
// 1. Initial screen with GochanoAppBar, subtitle, Add Paper button, and Refresh button in English.
// 2. Loading state presentation while loading past papers data.
// 3. Error state presentation when API call fails with Retry button.
// 4. Empty paper list state with clean call to action.
// 5. Populated state with Historical Coverage overview card and stat blocks.
// 6. Populated analyzed papers list with paper card title, subject, year, and question count.
// 7. Frequently tested topics section with topic name, label, question count, and frequency score pill.
// 8. Analyze Paper dialog opening on Add Paper tap with form fields and actions.
// 9. Bengali localization rendering all labels, stats, subtitles, and numbers in Bengali digits.
// 10. Responsive 320dp narrow viewport with zero RenderFlex overflow.
// 11. Dark mode theme contrast and surfaces.
// 12. Reduced-motion accessibility compliance.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/exam_ecosystem/exam_ecosystem_models.dart';
import 'package:gochano/features/study/presentation/exam_ecosystem/past_paper_screen.dart';

Widget _wrap(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  bool disableAnimations = false,
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

  final sampleInsights = PastPaperInsight(
    papersAnalyzed: 12,
    yearsCovered: const [2021, 2022, 2023, 2024],
    subjects: const ['Physics', 'Chemistry'],
    totalQuestions: 150,
    topicStats: const [
      {
        'topic': 'Newtonian Mechanics',
        'displayTopic': 'Newtonian Mechanics',
        'frequencyLabel': 'Frequently Tested',
        'questionCount': 28,
        'historicalFrequencyScore': 85,
      },
      {
        'topic': 'Thermodynamics',
        'displayTopic': 'Thermodynamics',
        'frequencyLabel': 'Moderate Frequency',
        'questionCount': 14,
        'historicalFrequencyScore': 55,
      },
    ],
  );

  final samplePapers = const [
    {
      'examName': 'HSC Physics Paper 1',
      'subject': 'Physics',
      'year': 2024,
      'questionCount': 25,
    },
    {
      'examName': 'HSC Chemistry Paper 1',
      'subject': 'Chemistry',
      'year': 2023,
      'questionCount': 25,
    },
  ];

  group('PastPaperScreen Visual & Interaction Tests', () {
    testWidgets('renders GochanoAppBar, subtitle, Add Paper button, and Refresh button in English', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: const [],
            initialInsights: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Past Papers'), findsOneWidget);
      expect(
        find.text('Exam trends & historical question coverage'),
        findsOneWidget,
      );
      expect(find.byTooltip('Analyze Paper'), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });

    testWidgets('renders loading state with progress indicator and friendly message', (
      tester,
    ) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            loadDataOverride: () => completer.future,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading past papers data…'), findsOneWidget);
    });

    testWidgets('renders error state on API failure with Retry button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PastPaperScreen(
            initialError: 'Could not connect to examination server.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Could not connect to examination server.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders empty paper list state with clean call to action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: const [],
            initialInsights: sampleInsights,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No past papers analyzed yet. Tap "Add Paper" to begin.'),
        findsOneWidget,
      );
      expect(find.text('Add Paper'), findsOneWidget);
    });

    testWidgets('renders Historical Coverage overview card and stat blocks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Historical Coverage'), findsOneWidget);
      expect(
        find.text('Based on analyzed past examination papers'),
        findsOneWidget,
      );
      expect(find.text('Papers Analyzed'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Questions'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
      expect(find.text('Years Covered'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('renders populated analyzed papers list with paper details', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Analyzed Papers (2)'), findsOneWidget);
      expect(find.text('HSC Physics Paper 1'), findsOneWidget);
      expect(find.text('Physics · 2024 · 25 questions'), findsOneWidget);
      expect(find.text('HSC Chemistry Paper 1'), findsOneWidget);
      expect(find.text('Chemistry · 2023 · 25 questions'), findsOneWidget);
    });

    testWidgets('renders Frequently Tested Topics section with ranking and score pills', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Frequently Tested Topics (Historical Data)'),
        findsOneWidget,
      );
      expect(find.text('Newtonian Mechanics'), findsOneWidget);
      expect(
        find.text('Frequently Tested · 28 question(s)'),
        findsOneWidget,
      );
      expect(find.text('85%'), findsOneWidget);

      expect(find.text('Thermodynamics'), findsOneWidget);
      expect(
        find.text('Moderate Frequency · 14 question(s)'),
        findsOneWidget,
      );
      expect(find.text('55%'), findsOneWidget);
    });

    testWidgets('tapping Add Paper opens Analyze Workspace Past Paper dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Paper'));
      await tester.pumpAndSettle();

      expect(find.text('Analyze Workspace Past Paper'), findsOneWidget);
      expect(find.text('Material ID'), findsOneWidget);
      expect(find.text('Exam Name'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('Board / Authority'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Analyze'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Analyze Workspace Past Paper'), findsNothing);
    });

    testWidgets('Bengali localization renders all labels, stats, subtitles, and numbers in Bengali', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('বিগত প্রশ্ন'), findsOneWidget);
      expect(
        find.text('বিগত পরীক্ষার প্রশ্ন ও ট্রেন্ড বিশ্লেষণ'),
        findsOneWidget,
      );
      expect(find.text('ঐতিহাসিক কভারেজ সারসংক্ষেপ'), findsOneWidget);
      expect(find.text('বিশ্লেষিত প্রশ্নপত্র'), findsOneWidget);
      expect(find.text('১২'), findsOneWidget);
      expect(find.text('মোট প্রশ্ন'), findsOneWidget);
      expect(find.text('১৫০'), findsOneWidget);
      expect(find.text('কভার করা বছর'), findsOneWidget);
      expect(find.text('৪'), findsOneWidget);
      expect(find.text('বিশ্লেষিত প্রশ্নপত্র (২)'), findsOneWidget);
      expect(find.text('নতুন যোগ করুন'), findsOneWidget);
      expect(find.text('Physics · ২০২৪ · ২৫ টি প্রশ্ন'), findsOneWidget);
      expect(
        find.text('ঘন ঘন আসা বিষয়সমূহ (ঐতিহাসিক তথ্য)'),
        findsOneWidget,
      );
      expect(find.text('৮৫%'), findsOneWidget);
      expect(find.text('৫৫%'), findsOneWidget);
    });

    testWidgets('renders cleanly on 320dp narrow viewport with zero overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
          size: const Size(320, 640),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Historical Coverage'), findsOneWidget);
      expect(find.text('Analyzed Papers (2)'), findsOneWidget);
    });

    testWidgets('renders cleanly in Dark Mode with theme-adaptive surfaces', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HSC Physics Paper 1'), findsOneWidget);
    });

    testWidgets('respects reduced-motion preferences without animation errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PastPaperScreen(
            initialPapers: samplePapers,
            initialInsights: sampleInsights,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Historical Coverage'), findsOneWidget);
    });
  });
}
