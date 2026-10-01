import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/study/presentation/ai/ai_conversation_service.dart';
import 'package:gochano/features/study/presentation/ai/ziku_assistant_panel.dart';
import 'package:gochano/shared/widgets/ziku_floating_launcher.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    return File('flutter_app/$relativePath').readAsStringSync().replaceAll('\r\n', '\n');
  }
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  group('AiConversationService Unit Tests', () {
    final service = AiConversationService.instance;

    setUp(() {
      service.clearConversation();
    });

    test('initial state has starter suggestions and empty messages', () {
      expect(service.messages.isEmpty, isTrue);
      expect(service.suggestions.isNotEmpty, isTrue);
      expect(service.hasActiveContext, isFalse);
    });

    test('context material can be set and cleared', () {
      service.setContextMaterial(id: 'mat_123', title: 'Calculus Notes.pdf');
      expect(service.hasActiveContext, isTrue);
      expect(service.contextMaterialId, equals('mat_123'));
      expect(service.contextMaterialTitle, equals('Calculus Notes.pdf'));

      service.clearContextMaterial();
      expect(service.hasActiveContext, isFalse);
      expect(service.contextMaterialId, isNull);
    });

    test('clearConversation resets messages and restores suggestions', () {
      service.setContextMaterial(id: 'mat_1', title: 'Doc.pdf');
      service.clearConversation();
      expect(service.messages.isEmpty, isTrue);
      expect(service.contextMaterialId, isNull);
      expect(service.suggestions.isNotEmpty, isTrue);
    });
  });

  group('ZikuFloatingLauncher Widget Tests', () {
    testWidgets('renders launcher button and responds to tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: Scaffold(
            floatingActionButton: ZikuFloatingLauncher(
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('ziku_floating_launcher')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ziku_floating_launcher')));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('ZikuAssistantPanel Widget Tests', () {
    testWidgets('renders header, close button, input field, and starter suggestions', (tester) async {
      AiConversationService.instance.clearConversation();

      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: const Scaffold(
            body: ZikuAssistantPanel(
              currentDestination: 'Today',
              appMode: 'student',
            ),
          ),
        ),
      );

      expect(find.text('Ziku AI'), findsOneWidget);
      expect(find.byKey(const ValueKey('ziku_panel_close_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('ziku_message_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('ziku_send_button')), findsOneWidget);

      // Welcome prompt or starter chips visible
      expect(find.byKey(const ValueKey('ziku_suggestion_0')), findsOneWidget);
    });
  });

  group('Static Code Verifications - Phase AI-FLOAT-1', () {
    final shellFile = _read('lib/features/shell/presentation/gochano_shell.dart');
    final aiUsageScreenFile = _read('lib/features/profile/presentation/ai_usage_screen.dart');
    final aiAssistantScreenFile = _read('lib/features/study/presentation/ai/ai_assistant_screen.dart');
    final apiServiceFile = _read('lib/services/api_service.dart');

    test('gochano_shell mounts ZikuFloatingLauncher stacked with quick add fab', () {
      expect(shellFile.contains('ZikuFloatingLauncher('), isTrue);
      expect(shellFile.contains('universal_quick_add_fab'), isTrue);
    });

    test('api_service exposes aiChat endpoint', () {
      expect(apiServiceFile.contains('aiChat('), isTrue);
      expect(apiServiceFile.contains('/api/ai/chat'), isTrue);
    });

    test('ai_assistant_screen uses multi-turn aiChat and dynamic suggestions', () {
      expect(aiAssistantScreenFile.contains('ApiService.aiChat'), isTrue);
      expect(aiAssistantScreenFile.contains('_dynamicSuggestions'), isTrue);
    });

    test('ai_usage_screen supports unlimited mode banner and activity dashboard', () {
      expect(aiUsageScreenFile.contains('Unlimited AI Mode Active'), isTrue);
      expect(aiUsageScreenFile.contains('AI Activity Dashboard'), isTrue);
      expect(aiUsageScreenFile.contains('_AiSummaryStatCard'), isTrue);
      expect(aiUsageScreenFile.contains('quota_enforcement_enabled'), isTrue);
    });
  });

  group('Static Code Verifications - Phase AI-FLOAT-1.1', () {
    final panelFile = _read(
      'lib/features/study/presentation/ai/ziku_assistant_panel.dart',
    );
    final launcherFile = _read('lib/shared/widgets/ziku_floating_launcher.dart');
    final shellFile = _read('lib/features/shell/presentation/gochano_shell.dart');

    test('Ziku panel is a RIGHT-side sheet, not a bottom modal', () {
      expect(panelFile.contains('showGeneralDialog'), isTrue);
      expect(panelFile.contains('Alignment.centerRight'), isTrue);
      expect(panelFile.contains('Offset(1, 0)'), isTrue);
      expect(
        panelFile.contains('begin: const Offset(1, 0)'),
        isTrue,
        reason: 'Panel must slide in from the right edge',
      );
      expect(
        panelFile.contains('Offset(0, 1)'),
        isFalse,
        reason: 'Bottom-slide animation would make it a bottom sheet',
      );
      expect(
        panelFile.contains('Alignment.bottomCenter'),
        isFalse,
        reason: 'Panel must be anchored to the right edge',
      );
    });

    test('Ziku launcher key and shell stacking above quick add', () {
      expect(
        launcherFile.contains('ziku_floating_launcher'),
        isTrue,
        reason: 'Launcher must keep its stable key for UI tests',
      );
      expect(shellFile.contains('ZikuFloatingLauncher('), isTrue);
      expect(shellFile.contains('universal_quick_add_fab'), isTrue);
      // The launcher entry must appear in the same stack as the quick add fab.
      final launcherIndex = shellFile.indexOf('ZikuFloatingLauncher(');
      final fabIndex = shellFile.indexOf('universal_quick_add_fab');
      expect(launcherIndex, greaterThanOrEqualTo(0));
      expect(fabIndex, greaterThanOrEqualTo(0));
      expect(
        (launcherIndex - fabIndex).abs(),
        lessThan(2000),
        reason: 'Both widgets must live in the same floating stack region',
      );
    });

    test('usage screen reads the full server-side activity inventory', () {
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
      final usageScreen = _read(
        'lib/features/profile/presentation/ai_usage_screen.dart',
      );
      for (final counter in counters) {
        expect(
          usageScreen.contains("'$counter'"),
          isTrue,
          reason: 'Usage screen must read $counter from /api/ai/usage',
        );
      }
    });
  });
}
