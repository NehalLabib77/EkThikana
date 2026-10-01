import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/profile/presentation/ai_usage_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('AI Usage Screen - Phase 3A verification', () {
    final aiUsageScreenFile = _read(
      'lib/features/profile/presentation/ai_usage_screen.dart',
    );
    final profileScreenFile = _read(
      'lib/features/profile/presentation/profile_screen.dart',
    );

    test('profile_screen routes AI usage row to AiUsageScreen', () {
      expect(
        profileScreenFile.contains('AiUsageScreen()'),
        isTrue,
        reason:
            'Tapping AI usage row in profile must navigate to AiUsageScreen',
      );
    });

    test('ai_usage_screen defines Chat with daily 20 limit', () {
      expect(aiUsageScreenFile.contains("'Chat'"), isTrue);
      expect(
        aiUsageScreenFile.contains(
          "chatLimit = chatData['limit'] as int? ?? 20",
        ),
        isTrue,
      );
      expect(aiUsageScreenFile.contains('00:00 UTC'), isTrue);
    });

    test('ai_usage_screen defines Note AI with monthly 5 limit', () {
      expect(aiUsageScreenFile.contains("'Note AI'"), isTrue);
      expect(
        aiUsageScreenFile.contains(
          "noteLimit = noteData['limit'] as int? ?? 5",
        ),
        isTrue,
      );
      expect(aiUsageScreenFile.contains('Monthly'), isTrue);
    });

    test('ai_usage_screen defines Quiz with monthly 3 limit', () {
      expect(aiUsageScreenFile.contains("'Quiz Generator'"), isTrue);
      expect(
        aiUsageScreenFile.contains(
          "quizLimit = quizData['limit'] as int? ?? 3",
        ),
        isTrue,
      );
    });

    test('ai_usage_screen defines Study Planner with 1 active limit', () {
      expect(aiUsageScreenFile.contains("'Study Planner'"), isTrue);
      expect(
        aiUsageScreenFile.contains(
          "planLimit = planData['limit'] as int? ?? 1",
        ),
        isTrue,
      );
    });

    test('ai_usage_screen includes Bengali translations', () {
      expect(aiUsageScreenFile.contains("'এআই ব্যবহার'"), isTrue);
      expect(aiUsageScreenFile.contains("'চ্যাট'"), isTrue);
      expect(aiUsageScreenFile.contains("'নোট এআই'"), isTrue);
      expect(aiUsageScreenFile.contains("'কুইজ জেনারেটর'"), isTrue);
      expect(aiUsageScreenFile.contains("'স্টাডি প্ল্যানার'"), isTrue);
    });

    // ---- Phase 3A Physical Test Fix: error diagnostics ----

    test('_fetchUsage logs sanitized error via debugPrint', () {
      expect(
        aiUsageScreenFile.contains('debugPrint('),
        isTrue,
        reason: 'Error logging must use debugPrint for safe diagnostics',
      );
      expect(
        aiUsageScreenFile.contains('_sanitizeErrorMessage'),
        isTrue,
        reason: 'Error messages must be sanitized before logging',
      );
    });

    test('error categorization differentiates 401, 403, and network', () {
      // Auth error (not signed in)
      expect(
        aiUsageScreenFile.contains('code == 401'),
        isTrue,
        reason: 'Must detect 401 for auth errors',
      );
      // Role gate (student only)
      expect(
        aiUsageScreenFile.contains('code == 403'),
        isTrue,
        reason: 'Must detect 403 for role gate errors',
      );
      // Network error
      expect(
        aiUsageScreenFile.contains('SocketException'),
        isTrue,
        reason: 'Must detect SocketException for network errors',
      );
      // Config error
      expect(
        aiUsageScreenFile.contains('Backend URL is not configured'),
        isTrue,
        reason: 'Must detect missing API_BASE_URL configuration',
      );
    });

    test('error logging does not expose sensitive data', () {
      // Ensure no raw token or key logging patterns
      expect(
        aiUsageScreenFile.contains(
          RegExp(r'print\(.*(token|key|auth)', caseSensitive: false),
        ),
        isFalse,
        reason: 'Must not log raw tokens or API keys',
      );
    });

    testWidgets('renders AiUsageScreen loading or error state cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: GochanoTheme.light(), home: const AiUsageScreen()),
      );

      // In unit test environment without backend, it initially shows loading progress indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Pump to settle async fetch (which will catch network error in test environment)
      await tester.pumpAndSettle();

      // Upon network error, displays Retry button
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    // ---- Phase AI-FLOAT-1.1: full activity inventory ----

    test('dashboard reads every server-side activity counter', () {
      const counters = [
        'ai_chat_messages',
        'ai_notes',
        'pdf_questions',
        'image_questions',
        'quiz_generations',
        'quiz_questions',
        'assignment_uses',
        'planner_plans',
        'exam_rescue_plans',
        'study_recommendations',
        'commute_guides',
      ];

      for (final counter in counters) {
        expect(
          aiUsageScreenFile.contains("count('$counter')"),
          isTrue,
          reason: 'Activity dashboard must display "$counter"',
        );
      }
    });

    test('quiz generations and quiz questions are distinct metrics', () {
      expect(aiUsageScreenFile.contains("'Quiz generations'"), isTrue);
      expect(aiUsageScreenFile.contains("'Quiz questions'"), isTrue);
      expect(aiUsageScreenFile.contains("count('quiz_generations')"), isTrue);
      expect(aiUsageScreenFile.contains("count('quiz_questions')"), isTrue);
      expect(
        aiUsageScreenFile.contains("'Quiz generations'") &&
            aiUsageScreenFile.contains("'Quiz questions'"),
        isTrue,
        reason: 'Generations and questions must be shown as separate rows',
      );
    });

    test('dashboard does not claim a Revision AI metric', () {
      expect(
        aiUsageScreenFile.contains(RegExp(r'revision', caseSensitive: false)),
        isFalse,
        reason: 'Revision AI was removed — the dashboard must not invent it',
      );
    });

    test('unlimited banner keys off quota_enforcement_enabled', () {
      expect(aiUsageScreenFile.contains("quota_enforcement_enabled'"), isTrue);
      expect(aiUsageScreenFile.contains('Unlimited AI Mode Active'), isTrue);
    });

    // ---- AI-FLOAT-1.2: unlimited-mode presentation ----

    test('unlimited mode has a usage-not-quota caption', () {
      expect(
        aiUsageScreenFile.contains(
          'Usage is still tracked, but limits are temporarily not enforced.',
        ),
        isTrue,
        reason: 'Unlimited mode must explain that usage is tracked but '
            'limits are not enforced',
      );
      expect(
        aiUsageScreenFile.contains('final unlimited = usage['),
        isTrue,
        reason: 'Presentation must branch on quota_enforcement_enabled',
      );
    });

    test('unlimited mode hides the limits footer', () {
      expect(
        aiUsageScreenFile.contains('if (!unlimited)'),
        isTrue,
        reason: 'The "Limits ensure equal access..." footer must not show '
            'while limits are unenforced',
      );
    });

    test('feature card supports unlimited usage presentation', () {
      expect(aiUsageScreenFile.contains('class AiFeatureUsageCard'), isTrue);
      expect(aiUsageScreenFile.contains('this.unlimited = false'), isTrue);
      expect(aiUsageScreenFile.contains('this.usageLabel'), isTrue);
      expect(
        aiUsageScreenFile.contains('if (showQuota)'),
        isTrue,
        reason: 'Progress bar / reset badge / remaining text must only '
            'render when quotas are enforced',
      );
    });

    testWidgets(
      'unlimited mode shows usage counts, never remaining/negative quota',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: GochanoTheme.light(),
            home: Scaffold(
              body: AiFeatureUsageCard(
                icon: Icons.edit_note_rounded,
                title: 'Note AI',
                resetBadge: 'Monthly (resets 1st of month)',
                remainingText: '0 of 5 remaining this month',
                usageLabel: '6 uses',
                unlimited: true,
                used: 6,
                limit: 5,
                isPlan: false,
              ),
            ),
          ),
        );

        // Actual usage is shown.
        expect(find.text('6 uses'), findsWidgets);
        // Over-limit usage never renders as a negative or "left" value.
        expect(find.textContaining('-1/5'), findsNothing);
        expect(find.textContaining('remaining'), findsNothing);
        expect(find.textContaining('left'), findsNothing);
        // No progress bar implying a limit.
        expect(find.byType(LinearProgressIndicator), findsNothing);
        // No red exhaustion styling on the caption.
        expect(find.textContaining('0 of 5'), findsNothing);
      },
    );

    testWidgets(
      'production quota mode still shows normal used/limit/remaining',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: GochanoTheme.light(),
            home: Scaffold(
              body: AiFeatureUsageCard(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Chat',
                resetBadge: 'Daily (resets at 00:00 UTC)',
                remainingText: '4 of 20 remaining today',
                usageLabel: '16 uses',
                unlimited: false,
                used: 16,
                limit: 20,
                isPlan: false,
              ),
            ),
          ),
        );

        expect(find.text('4/20 left'), findsOneWidget);
        expect(find.text('4 of 20 remaining today'), findsOneWidget);
        expect(find.text('Daily (resets at 00:00 UTC)'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        // The unlimited usage label must not leak into quota mode.
        expect(find.text('16 uses'), findsNothing);
      },
    );
  });
}
