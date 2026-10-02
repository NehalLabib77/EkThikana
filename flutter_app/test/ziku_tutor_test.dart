// Phase 12 — Ziku Socratic AI Tutor Flutter Widget Tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/study/presentation/tutor/ziku_tutor_screen.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: child,
  );
}


void main() {
  group('Phase 12 — Ziku Socratic AI Tutor Widget Tests', () {
    testWidgets('renders initial diagnostic question, progress bar, and mode badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var startCalled = false;
      await tester.pumpWidget(
        _buildTestApp(
          ZikuTutorScreen(
            initialSubject: 'Physics',
            initialTopic: 'Optics',
            startSessionFn: ({
              required String subject,
              required String topic,
              String? concept,
              String mode = 'socratic',
            }) async {
              startCalled = true;
              return {
                'sessionId': 'test_session_1',
                'status': 'active',
                'mode': 'socratic',
                'step': 1,
                'question': 'How does light change speed when moving between media?',
                'understandingLevel': 0.25,
                'masteryScore': 0.25,
                'hintsUsed': 0,
              };
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(startCalled, isTrue);
      expect(find.text('Ziku Tutor'), findsOneWidget);
      expect(find.text('Physics • Optics'), findsOneWidget);
      expect(find.text('Step 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_progress_bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_progress_text')), findsOneWidget);
      expect(
        find.text('How does light change speed when moving between media?'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tutor_hint_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_explain_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_practice_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_input_field')), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_send_button')), findsOneWidget);
    });

    testWidgets('requesting hint displays Hint card and updates hints counter', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var hintRequested = false;
      await tester.pumpWidget(
        _buildTestApp(
          ZikuTutorScreen(
            startSessionFn: ({
              required String subject,
              required String topic,
              String? concept,
              String mode = 'socratic',
            }) async {
              return {
                'sessionId': 'test_session_hint',
                'status': 'active',
                'mode': 'socratic',
                'step': 1,
                'question': 'What causes total internal reflection?',
                'understandingLevel': 0.1,
                'masteryScore': 0.1,
                'hintsUsed': 0,
              };
            },
            hintFn: ({required String sessionId}) async {
              hintRequested = true;
              return {
                'sessionId': sessionId,
                'hint': 'Consider the critical angle of incidence.',
                'hintLevel': 1,
                'hintType': 'conceptual',
                'hintsUsed': 1,
                'maxHintsReached': false,
              };
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap hint button
      await tester.tap(find.byKey(const ValueKey('tutor_hint_button')));
      await tester.pumpAndSettle();

      expect(hintRequested, isTrue);
      expect(find.byKey(const ValueKey('tutor_hint_card')), findsOneWidget);
      expect(find.text('Hint 1'), findsOneWidget);
      expect(find.text('Consider the critical angle of incidence.'), findsOneWidget);
      expect(find.text('1 hints'), findsOneWidget);
    });

    testWidgets('explain button switches to explain mode and displays explanation card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var switchCalled = false;
      await tester.pumpWidget(
        _buildTestApp(
          ZikuTutorScreen(
            startSessionFn: ({
              required String subject,
              required String topic,
              String? concept,
              String mode = 'socratic',
            }) async {
              return {
                'sessionId': 'test_session_explain',
                'status': 'active',
                'mode': 'socratic',
                'step': 1,
                'question': 'Explain dispersion.',
                'understandingLevel': 0.2,
                'masteryScore': 0.2,
                'hintsUsed': 0,
              };
            },
            switchModeFn: ({required String sessionId, required String mode}) async {
              switchCalled = true;
              return {
                'sessionId': sessionId,
                'mode': 'explain',
                'prompt': 'Dispersion occurs because different wavelengths experience different refractive indices.',
              };
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Explain button
      await tester.tap(find.byKey(const ValueKey('tutor_explain_button')));
      await tester.pumpAndSettle();

      expect(switchCalled, isTrue);
      expect(find.byKey(const ValueKey('tutor_explanation_card')), findsOneWidget);
      expect(
        find.text('Dispersion occurs because different wavelengths experience different refractive indices.'),
        findsOneWidget,
      );
    });

    testWidgets('submitting student answer displays student bubble and evaluation card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var respondCalled = false;
      await tester.pumpWidget(
        _buildTestApp(
          ZikuTutorScreen(
            startSessionFn: ({
              required String subject,
              required String topic,
              String? concept,
              String mode = 'socratic',
            }) async {
              return {
                'sessionId': 'test_session_respond',
                'status': 'active',
                'mode': 'socratic',
                'step': 1,
                'question': 'Why do stars twinkle?',
                'understandingLevel': 0.2,
                'masteryScore': 0.2,
                'hintsUsed': 0,
              };
            },
            respondFn: ({required String sessionId, required String response}) async {
              respondCalled = true;
              return {
                'sessionId': sessionId,
                'status': 'active',
                'mode': 'socratic',
                'step': 2,
                'understandingLevel': 0.65,
                'masteryScore': 0.65,
                'hintsUsed': 0,
                'evaluation': {
                  'understanding': 'partial',
                  'confidence': 0.8,
                  'misconception': 'Planets do not twinkle because they are extended sources, not point sources.',
                  'missingConcepts': ['atmospheric refraction', 'point source'],
                  'nextAction': 'question',
                  'feedback': 'Good start! Atmospheric refraction bends starlight continuously.',
                },
                'nextQuestion': 'Why do planets usually not twinkle as much as stars?',
                'completed': false,
              };
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter student text
      await tester.enterText(
        find.byKey(const ValueKey('tutor_input_field')),
        'Because atmosphere bends light constantly.',
      );
      await tester.tap(find.byKey(const ValueKey('tutor_send_button')));
      await tester.pumpAndSettle();

      expect(respondCalled, isTrue);
      expect(find.text('Because atmosphere bends light constantly.'), findsOneWidget);
      expect(
        find.text('Good start! Atmospheric refraction bends starlight continuously.'),
        findsOneWidget,
      );
      expect(find.text('Why do planets usually not twinkle as much as stars?'), findsOneWidget);
      expect(find.text('atmospheric refraction'), findsOneWidget);
      expect(find.text('65% Understanding'), findsOneWidget);
    });

    testWidgets('finish button finalizes session and displays completion summary card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var completeCalled = false;
      await tester.pumpWidget(
        _buildTestApp(
          ZikuTutorScreen(
            startSessionFn: ({
              required String subject,
              required String topic,
              String? concept,
              String mode = 'socratic',
            }) async {
              return {
                'sessionId': 'test_session_complete',
                'status': 'active',
                'mode': 'socratic',
                'step': 1,
                'question': 'How does a convex lens converge light?',
                'understandingLevel': 0.3,
                'masteryScore': 0.3,
                'hintsUsed': 0,
              };
            },
            completeFn: ({required String sessionId}) async {
              completeCalled = true;
              return {
                'sessionId': sessionId,
                'status': 'completed',
                'mode': 'socratic',
                'stepsCount': 3,
                'hintsUsed': 1,
                'masteryScore': 0.85,
                'masteryBand': 'Mastered',
                'summary': {
                  'overview': 'Great job mastering convex lens principles!',
                  'conceptsMastered': ['Focal length', 'Ray diagrams'],
                  'conceptsToReview': [],
                  'recommendedNextAction': 'Take a practice quiz',
                },
              };
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Finish button
      await tester.tap(find.byKey(const ValueKey('tutor_finish_button')));
      await tester.pumpAndSettle();

      expect(completeCalled, isTrue);
      expect(find.byKey(const ValueKey('tutor_summary_card')), findsOneWidget);
      expect(find.text('Session Complete'), findsOneWidget);
      expect(find.text('Mastered'), findsOneWidget);
      expect(find.text('Great job mastering convex lens principles!'), findsOneWidget);
      expect(find.text('• Focal length'), findsOneWidget);
      expect(find.text('• Ray diagrams'), findsOneWidget);
      expect(find.byKey(const ValueKey('tutor_return_button')), findsOneWidget);
    });
  });
}
