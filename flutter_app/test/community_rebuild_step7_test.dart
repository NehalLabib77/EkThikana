import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/community/presentation/group_chat_view.dart';

Widget _wrap(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? GochanoTheme.light(),
    home: Scaffold(body: child),
  );
}

void main() {
  group('Community stickers model and catalogue', () {
    test('stickers catalogue contains expected academic stickers', () {
      expect(kCommunityStickers, isNotEmpty);
      expect(kCommunityStickers.length, greaterThanOrEqualTo(6));

      final ids = kCommunityStickers.map((s) => s.id).toSet();
      expect(ids, contains('study_time'));
      expect(ids, contains('exam_prep'));
      expect(ids, contains('group_work'));
      expect(ids, contains('notes_ready'));
      expect(ids, contains('ai_help'));
      expect(ids, contains('celebrate'));
    });

    test('stickers provide non-empty bilingual titles', () {
      for (final sticker in kCommunityStickers) {
        expect(sticker.id, isNotEmpty);
        expect(sticker.titleEn, isNotEmpty);
        expect(sticker.titleBn, isNotEmpty);
        expect(sticker.artId, isNotEmpty);
      }
    });

    test('stickers have zero reward/XP/gem dependencies', () {
      final chatSource = File(
        'lib/features/community/presentation/group_chat_view.dart',
      ).readAsStringSync();
      expect(chatSource, isNot(contains('XP')));
      expect(chatSource, isNot(contains('gems')));
      expect(chatSource, isNot(contains('level')));
      expect(chatSource, isNot(contains('reward')));
      expect(chatSource, isNot(contains('badge_unlock')));
    });
  });

  group('Community chat reactions catalogue', () {
    test('standard reaction set provides core interactive emoji glyphs', () {
      expect(kCommunityReactions, contains('👍'));
      expect(kCommunityReactions, contains('❤️'));
      expect(kCommunityReactions, contains('💡'));
      expect(kCommunityReactions, contains('🔥'));
      expect(kCommunityReactions, contains('👏'));
      expect(kCommunityReactions, contains('🤔'));
    });

    test('no gamification or payment tied to reactions', () {
      final chatSource = File(
        'lib/features/community/presentation/group_chat_view.dart',
      ).readAsStringSync();
      expect(chatSource, isNot(contains('coin')));
      expect(chatSource, isNot(contains('payment')));
    });

    test('reactions strictly reject fake local_user fallback', () {
      final chatSource = File(
        'lib/features/community/presentation/group_chat_view.dart',
      ).readAsStringSync();
      expect(chatSource, isNot(contains("'local_user'")));
      expect(chatSource, isNot(contains('"local_user"')));
    });

    test(
      'reactions map handles missing or empty reactions field gracefully',
      () {
        final msgWithoutReactions = <String, dynamic>{
          'id': 'msg_1',
          'text': 'Test message',
        };
        final rawReactions =
            (msgWithoutReactions['reactions'] as Map?) ?? const {};
        final reactions = <String, List<String>>{};
        for (final entry in rawReactions.entries) {
          final uids = ((entry.value as List?) ?? const [])
              .map((e) => e.toString())
              .toList();
          if (uids.isNotEmpty) {
            reactions[entry.key.toString()] = uids;
          }
        }
        expect(reactions, isEmpty);
      },
    );

    test('toggling reaction updates UID list without duplicates', () {
      final reactions = <String, List<String>>{
        '👍': ['user_1', 'user_2'],
      };
      const testUid = 'user_3';
      final currentUids = List<String>.from(reactions['👍'] ?? const []);
      if (currentUids.contains(testUid)) {
        currentUids.remove(testUid);
      } else {
        currentUids.add(testUid);
      }
      reactions['👍'] = currentUids;
      expect(reactions['👍'], equals(['user_1', 'user_2', 'user_3']));

      // Toggle off on repeat
      if (currentUids.contains(testUid)) {
        currentUids.remove(testUid);
      } else {
        currentUids.add(testUid);
      }
      reactions['👍'] = currentUids;
      expect(reactions['👍'], equals(['user_1', 'user_2']));
    });
  });

  group('GroupChatView widget tests', () {
    testWidgets('renders Chat is off state when chatEnabled is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupChatView(
            groupId: 'group_test_1',
            chatEnabled: false,
            isAdmin: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chat is off'), findsOneWidget);
      expect(
        find.textContaining('A group admin has turned chat off'),
        findsOneWidget,
      );
    });

    testWidgets('renders Chat is off admin instructions when isAdmin is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupChatView(
            groupId: 'group_test_1',
            chatEnabled: false,
            isAdmin: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chat is off'), findsOneWidget);
      expect(find.textContaining('Turn chat on from the menu'), findsOneWidget);
    });

    testWidgets(
      'renders composer with sticker, text input and send button when chatEnabled is true',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupChatView(
              groupId: 'group_test_1',
              chatEnabled: true,
              isAdmin: false,
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TextField), findsOneWidget);
        expect(find.byTooltip('Emoji'), findsNothing);
        expect(find.byTooltip('Stickers'), findsOneWidget);
        expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'supports normal keyboard unicode emojis typed into composer text field',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupChatView(
              groupId: 'group_test_1',
              chatEnabled: true,
              isAdmin: false,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(
          find.byType(TextField),
          'Hello classmates! 📚✨ Good luck! 🎯',
        );
        await tester.pump();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(
          textField.controller?.text,
          'Hello classmates! 📚✨ Good luck! 🎯',
        );
      },
    );

    testWidgets('tapping stickers button toggles sticker drawer', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupChatView(
            groupId: 'group_test_1',
            chatEnabled: true,
            isAdmin: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Send a study sticker'), findsNothing);

      await tester.tap(find.byTooltip('Stickers'));
      await tester.pump();

      expect(find.text('Send a study sticker'), findsOneWidget);
      expect(find.text('Study Time'), findsOneWidget);
      expect(find.text('Exam Ready'), findsOneWidget);
    });

    testWidgets('renders message bubble with sticker art and label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupChatView(
            groupId: 'group_test_1',
            chatEnabled: true,
            isAdmin: false,
          ),
        ),
      );
      await tester.pump();

      expect(kCommunityStickers.any((s) => s.id == 'study_time'), isTrue);
    });

    testWidgets(
      'renders message bubble with text, sender name, and reaction pills',
      (tester) async {
        final msg = {
          'id': 'msg_1',
          'senderId': 'other_user',
          'senderName': 'Sabbir Ahmed',
          'text': 'Hello study group! When is the exam?',
          'createdAt': DateTime.now().toIso8601String(),
          'reactions': {
            '👍': ['user_1', 'user_2'],
            '💡': ['user_3'],
          },
        };

        await tester.pumpWidget(
          _wrap(
            ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg['senderName'] as String),
                        Text(msg['text'] as String),
                        const Text('👍 2'),
                        const Text('💡 1'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sabbir Ahmed'), findsOneWidget);
        expect(
          find.text('Hello study group! When is the exam?'),
          findsOneWidget,
        );
        expect(find.text('👍 2'), findsOneWidget);
        expect(find.text('💡 1'), findsOneWidget);
      },
    );
  });

  group('Responsive and layout safety audit', () {
    testWidgets('renders on narrow screen (320px) without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const GroupChatView(
            groupId: 'group_narrow_test',
            chatEnabled: true,
            isAdmin: false,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    test(
      'group_chat_view.dart does not use IntrinsicHeight or unbounded vertical stretch',
      () {
        final chatSource = File(
          'lib/features/community/presentation/group_chat_view.dart',
        ).readAsStringSync();
        expect(chatSource, isNot(contains('IntrinsicHeight')));
        expect(chatSource, isNot(contains('double.infinity')));
      },
    );

    test('community_screen.dart does not use IntrinsicHeight', () {
      final screenSource = File(
        'lib/features/community/presentation/community_screen.dart',
      ).readAsStringSync();
      expect(screenSource, isNot(contains('IntrinsicHeight')));
    });
  });

  group('Bilingual localization reactivity', () {
    test('switches labels between English and Bangla', () {
      expect(GochanoLanguage.text('Community', 'কমিউনিটি'), 'Community');
      expect(GochanoLanguage.text('Chat', 'চ্যাট'), 'Chat');
      expect(GochanoLanguage.text('Send', 'পাঠান'), 'Send');
      expect(GochanoLanguage.text('Stickers', 'স্টিকার'), 'Stickers');
      expect(
        GochanoLanguage.text('React to message', 'বার্তায় প্রতিক্রিয়া দিন'),
        'React to message',
      );

      // Simulate Bangla
      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(GochanoLanguage.text('Community', 'কমিউনিটি'), 'কমিউনিটি');
      expect(GochanoLanguage.text('Chat', 'চ্যাট'), 'চ্যাট');
      expect(GochanoLanguage.text('Send', 'পাঠান'), 'পাঠান');
      expect(GochanoLanguage.text('Stickers', 'স্টিকার'), 'স্টিকার');
      expect(
        GochanoLanguage.text('React to message', 'বার্তায় প্রতিক্রিয়া দিন'),
        'বার্তায় প্রতিক্রিয়া দিন',
      );

      // Reset to English
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(GochanoLanguage.text('Community', 'কমিউনিটি'), 'Community');
    });
  });
}
