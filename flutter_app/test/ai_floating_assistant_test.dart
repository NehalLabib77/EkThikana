import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/study/presentation/ai/ai_conversation_service.dart';
import 'package:gochano/features/study/presentation/ai/ziku_assistant_panel.dart';
import 'package:gochano/features/study/presentation/ai/ziku_markdown_text.dart';
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

  // ---- AI-FLOAT-1.2: assistant markdown rendering ----

  group('ZikuMarkdownText parsing', () {
    test('paragraphs, bullets and numbered lists parse into blocks', () {
      final blocks = parseZikuMarkdown(
        'Think of it like a **perfect mirror**.\n'
        '\n'
        '- Light is trapped\n'
        '- It bounces back\n'
        '\n'
        '1. First step\n'
        '2. Second step',
      );

      expect(blocks, hasLength(3));
      expect(blocks[0].type, ZikuMarkdownBlockType.paragraph);
      expect(blocks[0].lines.single, contains('**perfect mirror**'));
      expect(blocks[1].type, ZikuMarkdownBlockType.bulletList);
      expect(blocks[1].lines, ['Light is trapped', 'It bounces back']);
      expect(blocks[2].type, ZikuMarkdownBlockType.numberedList);
      expect(blocks[2].numberStart, 1);
      expect(blocks[2].lines, ['First step', 'Second step']);
    });

    test('plain text (no markdown) is one paragraph block', () {
      final blocks = parseZikuMarkdown('hello there');
      expect(blocks, hasLength(1));
      expect(blocks.single.type, ZikuMarkdownBlockType.paragraph);
      expect(blocks.single.lines, ['hello there']);
    });

    test('plain visible text never contains **bold** markers', () {
      final visible = zikuMarkdownPlainText(
        'Think of it like a **perfect mirror**.\n\n'
        '- Light is trapped\n'
        '- It bounces back\n\n'
        '1. First\n'
        '2. Second',
      );

      expect(visible.contains('**'), isFalse);
      expect(visible, contains('perfect mirror'));
      expect(visible, contains('• Light is trapped'));
      expect(visible, contains('1. First'));
      expect(visible, contains('2. Second'));
    });

    test('HTML is never interpreted — it stays literal text', () {
      final blocks = parseZikuMarkdown('<b>bold?</b> and <script>alert(1)</script>');
      expect(blocks.single.type, ZikuMarkdownBlockType.paragraph);
      final visible = zikuMarkdownPlainText('<b>bold?</b>');
      expect(visible, contains('<b>bold?</b>'));
    });
  });

  group('ZikuMarkdownText Widget Tests', () {
    testWidgets(
      'assistant reply renders bold/lists without visible ** markers',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ZikuMarkdownText(
                'Think of it like a **perfect mirror**.\n\n'
                '- Light is trapped\n'
                '- It bounces back\n\n'
                '1. First step\n'
                '2. Second step',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        );

        // Collect every visible character the user can read — both the rich
        // message spans and the plain list-marker Text widgets.
        final visible = [
          ...tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((w) => (w.textSpan?.toPlainText() ?? w.data ?? '')),
          ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
        ].join();

        expect(visible.contains('**'), isFalse,
            reason: 'Supported markdown must be rendered, not shown raw');
        expect(visible, contains('perfect mirror'));
        expect(visible, contains('Light is trapped'));
        expect(visible, contains('1.'));

        // The bold span is actually bold.
        final rich = tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        );
        final hasBold = rich.any((w) {
          final span = w.textSpan;
          if (span == null) return false;
          return span.children?.any(
                (c) =>
                    c is TextSpan &&
                    c.style?.fontWeight == FontWeight.bold &&
                    c.toPlainText() == 'perfect mirror',
              ) ??
              false;
        });
        expect(hasBold, isTrue, reason: '**perfect mirror** must render bold');
      },
    );

    testWidgets('single-paragraph reply renders without blocks', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ZikuMarkdownText(
              'Light stays inside the denser medium.',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      );

      final visible = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => (w.textSpan?.toPlainText() ?? w.data ?? ''))
          .join();
      expect(visible, contains('Light stays inside the denser medium.'));
      expect(visible.contains('**'), isFalse);
    });
  });

  group('Static Code Verifications - Phase AI-FLOAT-1.2', () {
    final panelFile = _read(
      'lib/features/study/presentation/ai/ziku_assistant_panel.dart',
    );
    final shellFile = _read('lib/features/shell/presentation/gochano_shell.dart');
    final launcherFile = _read('lib/shared/widgets/ziku_floating_launcher.dart');

    test('assistant replies use ZikuMarkdownText, user text stays plain', () {
      expect(panelFile.contains("import 'ziku_markdown_text.dart';"), isTrue);
      expect(panelFile.contains('ZikuMarkdownText('), isTrue);
      expect(
        panelFile.contains('!isUser && !isError'),
        isTrue,
        reason: 'Only assistant replies (not user text, not errors) may be '
            'parsed as markdown',
      );
      // The user branch must still render the raw string as plain text.
      expect(
        panelFile.contains('SelectableText('),
        isTrue,
        reason: 'User messages must remain plain selectable text',
      );
    });

    test('right-side panel behavior is unchanged', () {
      expect(panelFile.contains('showGeneralDialog'), isTrue);
      expect(panelFile.contains('Alignment.centerRight'), isTrue);
      expect(panelFile.contains('begin: const Offset(1, 0)'), isTrue);
      expect(panelFile.contains('Offset(0, 1)'), isFalse);
      expect(panelFile.contains('Alignment.bottomCenter'), isFalse);
    });

    test('Ziku launcher remains stacked above Quick Add', () {
      expect(launcherFile.contains('ziku_floating_launcher'), isTrue);
      expect(shellFile.contains('ZikuFloatingLauncher('), isTrue);
      expect(shellFile.contains('universal_quick_add_fab'), isTrue);
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
  });
}
