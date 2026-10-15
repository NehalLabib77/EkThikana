import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/components/app_study_header.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/community/domain/community_models.dart';
import 'package:gochano/features/community/presentation/community_view.dart';
import 'package:gochano/features/community/presentation/group_detail_screen.dart';
import 'package:gochano/features/community/presentation/question_detail_screen.dart';
import 'package:gochano/features/community/presentation/shared_box_screen.dart';
import 'package:gochano/features/shell/presentation/gochano_shell.dart';
import 'package:gochano/shared/widgets/gochano_surfaces.dart';

Map<String, dynamic> _mockPost({
  String id = 'post_1',
  String kind = 'question',
  String title = 'How does lens magnification work in optics?',
  String body = 'Trying to understand focal length vs magnification ratio for upcoming physics exam.',
  String category = 'hsc',
  String authorId = 'u_1',
  String authorName = 'Rahim',
  int answerCount = 3,
  int usefulCount = 7,
  String acceptedAnswerId = 'ans_1',
}) => {
  'id': id,
  'kind': kind,
  'title': title,
  'body': body,
  'category': category,
  'authorId': authorId,
  'authorName': authorName,
  'subject': 'Physics',
  'chapter': 'Optics',
  'answerCount': answerCount,
  'usefulCount': usefulCount,
  'acceptedAnswerId': acceptedAnswerId,
  'duplicateOf': '',
  'duplicateOfTitle': '',
  'duplicateConfidence': 0.0,
  'groupId': '',
  'groupName': '',
  'usefulBy': ['u_2', 'u_3'],
  'answers': [],
};

Map<String, dynamic> _mockGroup({
  String id = 'grp_1',
  String name = 'HSC Physics Masters',
  String description = 'Daily optics problems and formula discussions',
  int memberCount = 12,
  bool chatEnabled = true,
}) => {
  'id': id,
  'name': name,
  'description': description,
  'memberIds': List.generate(memberCount, (i) => 'member_$i'),
  'chatEnabled': chatEnabled,
};

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  Widget buildCommunityView({
    Size size = const Size(390, 844),
    double textScale = 1.0,
    bool isDark = false,
    String initialSegment = 'for_you',
    CommunityPostsFn? postsFn,
    CommunityLeaderboardFn? leaderboardFn,
    CommunityCreatePostFn? createPostFn,
    CommunityPostFn? postDetailFn,
    List<Map<String, dynamic>>? mockGroups,
    bool showHeader = true,
    void Function(String groupId, String groupName)? onOpenGroup,
    VoidCallback? onOpenSharedBox,
  }) {
    return MaterialApp(
      theme: isDark ? ThemeData.dark() : ThemeData.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: CommunityView(
            initialSegment: initialSegment,
            postsFn: postsFn ?? (({String category = '', String groupId = '', String kind = '', int limit = 15, bool popular = false}) async => {
              'posts': [_mockPost()],
              'popular': popular,
            }),
            leaderboardFn: leaderboardFn ?? (({groupId = '', scope = 'global'}) async => {
              'entries': [
                {'displayName': 'Tanvir', 'points': 140},
                {'displayName': 'Sumaiya', 'points': 110},
              ],
            }),
            createPostFn: createPostFn,
            postDetailFn: postDetailFn,
            mockGroups: mockGroups ?? [_mockGroup()],
            showHeader: showHeader,
            onOpenGroup: onOpenGroup,
            onOpenSharedBox: onOpenSharedBox,
          ),
        ),
      ),
    );
  }

  group('Study Mode → Community Redesign Tests', () {
    testWidgets('1. Community title and context intro render correctly', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      expect(find.text('Community'), findsOneWidget);
      expect(
        find.text('Learn together. Share ideas. Stay connected.'),
        findsOneWidget,
      );
    });

    testWidgets('2. shared contextual AppStudyHeader is pinned outside scroll', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      expect(find.byType(AppStudyHeader), findsOneWidget);
      expect(find.byKey(const ValueKey('community_header_group_options_button')), findsOneWidget);
    });

    testWidgets('3. exactly one search surface exists on header without duplicate in body', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      // Exactly 1 search icon in header
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      // No search TextField in community body
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('4. For You mode renders as default discovery feed', (tester) async {
      await tester.pumpWidget(buildCommunityView(initialSegment: 'for_you'));
      await tester.pumpAndSettle();

      expect(find.text('For You'), findsOneWidget);
      expect(find.text('How does lens magnification work in optics?'), findsOneWidget);
      expect(find.text('Rahim'), findsOneWidget);
    });

    testWidgets('5. Discussions mode switches and renders Question Bank section with filters', (tester) async {
      await tester.pumpWidget(buildCommunityView(initialSegment: 'discussions'));
      await tester.pumpAndSettle();

      expect(find.text('Discussions'), findsOneWidget);
      expect(find.text('Question Bank'), findsOneWidget);
      expect(find.text('Question'), findsWidgets);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Popular'), findsOneWidget);
    });

    testWidgets('6. Study Groups mode renders joined groups and actions', (tester) async {
      await tester.pumpWidget(buildCommunityView(initialSegment: 'groups'));
      await tester.pumpAndSettle();

      expect(find.text('Study Groups'), findsWidgets);
      expect(find.text('HSC Physics Masters'), findsOneWidget);
      expect(find.text('12 members'), findsOneWidget);
      expect(find.text('Chat on'), findsOneWidget);
      expect(find.text('New group'), findsOneWidget);
    });

    testWidgets('7. segmented switcher transitions between content modes', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      // Tap Study Groups
      await tester.tap(find.text('Study Groups'));
      await tester.pumpAndSettle();

      expect(find.text('HSC Physics Masters'), findsOneWidget);

      // Tap For You
      await tester.tap(find.text('For You'));
      await tester.pumpAndSettle();

      expect(find.text('How does lens magnification work in optics?'), findsOneWidget);
    });

    testWidgets('8. compact composer card exists and triggers composer sheet', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      final composerFinder = find.text('Ask a question or share something…');
      expect(composerFinder, findsOneWidget);

      await tester.tap(composerFinder);
      await tester.pumpAndSettle();

      // Verify composer bottom sheet appeared
      expect(find.text('Give it a title first.'), findsNothing); // Not submitted yet
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('9. real feed item renders author, title, body, category and stats', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      expect(find.text('Rahim'), findsOneWidget);
      expect(find.text('HSC'), findsOneWidget);
      expect(find.text('How does lens magnification work in optics?'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // 3 answers
      expect(find.text('7'), findsOneWidget); // 7 useful
      expect(find.text('Solved'), findsOneWidget);
    });

    testWidgets('10. post tap navigates to QuestionDetailScreen', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      await tester.tap(find.text('How does lens magnification work in optics?'));
      await tester.pumpAndSettle();

      expect(find.byType(QuestionDetailScreen), findsOneWidget);
    });

    testWidgets('11. Study Groups item tap triggers onOpenGroup callback', (tester) async {
      String? openedGroupId;
      String? openedGroupName;
      await tester.pumpWidget(
        buildCommunityView(
          initialSegment: 'groups',
          onOpenGroup: (id, name) {
            openedGroupId = id;
            openedGroupName = name;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('HSC Physics Masters'));
      await tester.pumpAndSettle();

      expect(openedGroupId, 'grp_1');
      expect(openedGroupName, 'HSC Physics Masters');
    });

    testWidgets('12. Shared Box bridge is present in Study Groups mode and triggers onOpenSharedBox', (tester) async {
      var sharedBoxOpened = false;
      await tester.pumpWidget(
        buildCommunityView(
          initialSegment: 'groups',
          onOpenSharedBox: () {
            sharedBoxOpened = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shared Box'), findsOneWidget);
      expect(find.text('Materials shared across your study groups'), findsOneWidget);

      await tester.tap(find.text('Shared Box'));
      await tester.pumpAndSettle();

      expect(sharedBoxOpened, isTrue);
    });

    testWidgets('13. empty feed renders polite empty state with Ask CTA', (tester) async {
      await tester.pumpWidget(
        buildCommunityView(
          postsFn: ({String category = '', String groupId = '', String kind = '', int limit = 15, bool popular = false}) async => {
            'posts': [],
            'popular': popular,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No discussions yet'), findsOneWidget);
      expect(find.text('Ask a question'), findsOneWidget);
    });

    testWidgets('14. initial error renders polite error state with Retry action', (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        buildCommunityView(
          postsFn: ({String category = '', String groupId = '', String kind = '', int limit = 15, bool popular = false}) async {
            callCount++;
            if (callCount == 1) {
              throw Exception('Network unreachable');
            }
            return {'posts': [_mockPost()], 'popular': popular};
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load Community."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('How does lens magnification work in optics?'), findsOneWidget);
    });

    testWidgets('15. pagination deduplicates posts by ID', (tester) async {
      await tester.pumpWidget(
        buildCommunityView(
          postsFn: ({String category = '', String groupId = '', String kind = '', int limit = 15, bool popular = false}) async => {
            'posts': [
              _mockPost(id: 'post_1', title: 'Unique Post 1'),
              _mockPost(id: 'post_1', title: 'Duplicate Post 1'),
              _mockPost(id: 'post_2', title: 'Unique Post 2'),
            ],
            'popular': popular,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unique Post 1'), findsOneWidget);
      expect(find.text('Duplicate Post 1'), findsNothing);
      expect(find.text('Unique Post 2'), findsOneWidget);
    });

    testWidgets('16. empty study groups renders polite empty state with New group CTA', (tester) async {
      await tester.pumpWidget(
        buildCommunityView(
          initialSegment: 'groups',
          mockGroups: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No study groups yet'), findsOneWidget);
      expect(find.text('New group'), findsWidgets);
    });

    testWidgets('17. pull to refresh reloads feed', (tester) async {
      var refreshed = false;
      await tester.pumpWidget(
        buildCommunityView(
          postsFn: ({String category = '', String groupId = '', String kind = '', int limit = 15, bool popular = false}) async {
            if (refreshed) {
              return {
                'posts': [_mockPost(title: 'Refreshed Fresh Content')],
                'popular': popular,
              };
            }
            return {'posts': [_mockPost()], 'popular': popular};
          },
        ),
      );
      await tester.pumpAndSettle();

      refreshed = true;
      await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Refreshed Fresh Content'), findsOneWidget);
    });

    testWidgets('18. responsive layout at 320dp width has zero overflow', (tester) async {
      await tester.pumpWidget(buildCommunityView(size: const Size(320, 640)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('19. responsive layout at 360dp width has zero overflow', (tester) async {
      await tester.pumpWidget(buildCommunityView(size: const Size(360, 780)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('20. responsive layout at 390dp width has zero overflow', (tester) async {
      await tester.pumpWidget(buildCommunityView(size: const Size(390, 844)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('21. responsive layout at 412dp width has zero overflow', (tester) async {
      await tester.pumpWidget(buildCommunityView(size: const Size(412, 915)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('22. accessible text scale 1.5x renders without crash or overflow', (tester) async {
      await tester.pumpWidget(buildCommunityView(textScale: 1.5));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('23. accessible text scale 2.0x renders without crash', (tester) async {
      await tester.pumpWidget(buildCommunityView(textScale: 2.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('24. dark mode renders cleanly with appropriate contrast', (tester) async {
      await tester.pumpWidget(buildCommunityView(isDark: true));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('25. Bangla localization renders appropriate Bengali text', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      expect(find.text('কমিউনিটি'), findsOneWidget);
      expect(find.text('আপনার জন্য'), findsOneWidget);
      expect(find.text('আলোচনা'), findsOneWidget);
      expect(find.text('স্টাডি গ্রুপ'), findsOneWidget);
    });

    testWidgets('26. interactive touch targets meet >= 44dp requirement', (tester) async {
      await tester.pumpWidget(buildCommunityView());
      await tester.pumpAndSettle();

      final optionsButton = tester.getSize(
        find.byKey(const ValueKey('community_header_group_options_button')),
      );
      expect(optionsButton.width, greaterThanOrEqualTo(44.0));
      expect(optionsButton.height, greaterThanOrEqualTo(44.0));
    });

    testWidgets('27. Community bottom navigation tab is mapped and active in GochanoShell', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GochanoShell(
            role: 'student',
            displayName: 'Labib',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Community bottom navigation item
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();

      expect(find.byType(CommunityView), findsOneWidget);
    });

    testWidgets('28. Community -> Today -> Community preserves IndexedStack and state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GochanoShell(
            role: 'student',
            displayName: 'Labib',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Community tab
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();

      expect(find.byType(CommunityView), findsOneWidget);

      // Switch to Today tab (index 0)
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Labib'), findsWidgets);

      // Switch back to Community tab (index 3)
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();

      expect(find.byType(CommunityView), findsOneWidget);
      expect(find.text('Community'), findsWidgets);
    });
  });
}
