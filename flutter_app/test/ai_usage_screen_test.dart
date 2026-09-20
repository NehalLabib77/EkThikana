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
  });
}
