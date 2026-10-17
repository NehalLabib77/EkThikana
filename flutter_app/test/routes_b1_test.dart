import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/app.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/exams/presentation/exam_setup_screen.dart';
import 'package:gochano/features/study/presentation/adaptive/revision_queue_screen.dart';
import 'package:gochano/features/study/presentation/ai/quiz_generator_screen.dart';

Widget _buildHarness() {
  return MaterialApp(
    theme: GochanoTheme.light(),
    onGenerateRoute: onGenerateAppRoute,
    home: Builder(
      builder: (context) => Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamed('/exams'),
              child: const Text('Go Exams'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamed('/mistakes'),
              child: const Text('Go Mistakes'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamed('/quiz-generate'),
              child: const Text('Go Quiz Generate'),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B-1 Route Verification Tests', () {
    testWidgets('Navigator resolves /exams route to ExamSetupScreen', (tester) async {
      await tester.pumpWidget(_buildHarness());
      await tester.pump();

      await tester.tap(find.text('Go Exams'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ExamSetupScreen), findsOneWidget);
    });

    testWidgets('Navigator resolves /mistakes route to RevisionQueueScreen', (tester) async {
      await tester.pumpWidget(_buildHarness());
      await tester.pump();

      await tester.tap(find.text('Go Mistakes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(RevisionQueueScreen), findsOneWidget);
    });

    testWidgets('Navigator resolves /quiz-generate route to QuizGeneratorScreen', (tester) async {
      await tester.pumpWidget(_buildHarness());
      await tester.pump();

      await tester.tap(find.text('Go Quiz Generate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(QuizGeneratorScreen), findsOneWidget);
    });
  });
}

