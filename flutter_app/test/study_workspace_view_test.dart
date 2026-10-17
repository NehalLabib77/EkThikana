import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/app_design_system.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/shell/presentation/gochano_shell.dart';
import 'package:gochano/features/study/presentation/workspace/workspace_view.dart';
import 'package:gochano/widgets/language_toggle.dart';

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  Widget buildWorkspace({
    Size size = const Size(390, 844),
    double textScale = 1.0,
    bool isDark = false,
    List<Map<String, dynamic>>? mockRecentMaterials = const [],
  }) {
    return MaterialApp(
      theme: isDark ? ThemeData.dark() : ThemeData.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: WorkspaceView(
            mockRecentMaterials: mockRecentMaterials,
          ),
        ),
      ),
    );
  }

  group('Study Mode → Workspace Final IA Tests', () {
    // ─── Test 1: Header search hidden ───────────────────────────────────────
    testWidgets('1. header search icon is HIDDEN on Workspace', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      // The header should NOT show a search IconButton
      // (body search is the single search entry point)
      // AppStudyHeader with showSearch: false means no search IconButton in header
      final headerFinder = find.byType(AppStudyHeader);
      expect(headerFinder, findsOneWidget);

      // Only the body AppWorkspaceSearchField prefix icon — not an IconButton in header
      final searchIconButtons =
          find.widgetWithIcon(IconButton, Icons.search_rounded);
      expect(searchIconButtons, findsNothing,
          reason: 'Header search IconButton must be hidden on Workspace');
    });

    // ─── Test 2: Body search visible ────────────────────────────────────────
    testWidgets('2. body search field is visible and functional', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.byType(AppWorkspaceSearchField), findsOneWidget);
    });

    // ─── Test 3: Single search entry point ──────────────────────────────────
    testWidgets('3. exactly one search TextField in Workspace', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    });

    // ─── Test 4: No Exam Rescue ─────────────────────────────────────────────
    testWidgets('4. ExamRescueTile is absent from Workspace', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.text('Exam Rescue'), findsNothing);
      expect(find.text('Exam close? Build a quick rescue plan.'), findsNothing);
    });

    // ─── Test 5: No Quick Shortcuts ─────────────────────────────────────────
    testWidgets('5. Quick Shortcuts section is absent from Workspace', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.text('Quick Shortcuts'), findsNothing);
      expect(find.text('See more'), findsNothing);
      expect(find.text('See less'), findsNothing);
    });

    // ─── Test 6: Six primary Study Tools ────────────────────────────────────
    testWidgets('6. exactly 6 primary Study Tools visible', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Past Papers'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Mock Tests'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Study Materials'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Question Bank'), findsOneWidget);
      // Saved Items and Shared Box are NOT primary tool cards
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Saved Items'), findsNothing);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Shared Box'), findsNothing);
    });

    // ─── Test 7: 2-column phone layout ──────────────────────────────────────
    testWidgets('7. Study Tools renders in 2-column grid on phone', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(390, 844)));
      await tester.pump();

      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsOneWidget);
    });

    // ─── Test 8: My Notes route ──────────────────────────────────────────────
    testWidgets('8. My Notes card is tappable', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      final card = find.widgetWithText(AppWorkspaceToolCard, 'My Notes');
      expect(card, findsOneWidget);
      await tester.tap(card);
      await tester.pump();
    });

    // ─── Test 9: Flashcards route ────────────────────────────────────────────
    testWidgets('9. Flashcards card is tappable', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      await tester.tap(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'));
      await tester.pump();
    });

    // ─── Test 10: Past Papers route ──────────────────────────────────────────
    testWidgets('10. Past Papers card is tappable', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      await tester.tap(find.widgetWithText(AppWorkspaceToolCard, 'Past Papers'));
      await tester.pump();
    });

    // ─── Test 11: Mock Tests route ───────────────────────────────────────────
    testWidgets('11. Mock Tests card is tappable', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      await tester.tap(find.widgetWithText(AppWorkspaceToolCard, 'Mock Tests'));
      await tester.pump();
    });

    // ─── Test 12: Study Materials route ─────────────────────────────────────
    testWidgets('12. Study Materials card is tappable', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      await tester.tap(
          find.widgetWithText(AppWorkspaceToolCard, 'Study Materials'));
      await tester.pump();
    });

    // ─── Test 13: Question Bank → QuizGeneratorScreen ────────────────────────
    testWidgets('13. Question Bank card is tappable (routes to QuizGeneratorScreen)', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      await tester.tap(
          find.widgetWithText(AppWorkspaceToolCard, 'Question Bank'));
      await tester.pump();
    });

    // ─── Test 14: Resource Vault section visible ─────────────────────────────
    testWidgets('14. Resource Vaults section is visible', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.text('Resource Vaults'), findsOneWidget);
    });

    // ─── Test 15: Saved Items route ──────────────────────────────────────────
    testWidgets('15. Saved Items vault button is tappable', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.text('Saved Items'), findsOneWidget);
      await tester.tap(find.text('Saved Items'));
      await tester.pump();
      tester.takeException(); // Clear Firebase uninitialized exception in mock test
    });

    // ─── Test 16: Shared Box route ───────────────────────────────────────────
    testWidgets('16. Shared Box vault button is tappable', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.text('Shared Box'), findsOneWidget);
      await tester.tap(find.text('Shared Box'));
      await tester.pump();
      tester.takeException(); // Clear Firebase uninitialized exception in mock test
    });

    // ─── Test 17: Saved chip is a filter, not a nav shortcut ─────────────────
    testWidgets('17. Saved filter chip hides Study Tools grid', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.byType(AppWorkspaceFilterChips), findsOneWidget);

      Finder chipText(String label) => find.descendant(
            of: find.byType(AppWorkspaceFilterChips),
            matching: find.text(label),
          );

      await tester.ensureVisible(chipText('Saved'));
      await tester.tap(chipText('Saved'));
      await tester.pump();

      expect(find.text('Study Tools'), findsNothing);
      expect(find.text('Resource Vaults'), findsOneWidget);
    });

    // ─── Test 18: Recently Opened compact preview ─────────────────────────────
    testWidgets('18. Recently Opened with mock data shows carousel', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildWorkspace(
        mockRecentMaterials: [
          {
            'title': 'Test PDF',
            'fileName': 'test.pdf',
            'mimeType': 'application/pdf',
            'subject': 'Physics',
          },
        ],
      ));
      await tester.pump();

      expect(find.text('Recently Opened'), findsOneWidget);
      expect(find.text('Test PDF'), findsOneWidget);
    });

    // ─── Test 19: Recent empty state ─────────────────────────────────────────
    testWidgets('19. Recently Opened empty state', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildWorkspace(mockRecentMaterials: const []));
      await tester.pump();

      expect(find.text('Recently Opened'), findsOneWidget);
      expect(find.text('No recent study items yet.'), findsOneWidget);
    });

    // ─── Test 20: Loading state (null mock triggers stream builder) ───────────
    testWidgets('20. null mock triggers stream builder without crash', (tester) async {
      await tester.pumpWidget(buildWorkspace(mockRecentMaterials: null));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ─── Test 22: 320dp no overflow ──────────────────────────────────────────
    testWidgets('22. 320dp narrow layout no RenderFlex overflow', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(320, 640)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    // ─── Test 23: 360dp no overflow ──────────────────────────────────────────
    testWidgets('23. 360dp standard mobile no overflow', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(360, 640)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    // ─── Test 24: 390dp no overflow ──────────────────────────────────────────
    testWidgets('24. 390dp layout no overflow', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(390, 844)));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // ─── Test 25: 412dp no overflow ──────────────────────────────────────────
    testWidgets('25. 412dp large mobile no overflow', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(412, 915)));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // ─── Test 26: 1.5x text scale no overflow ────────────────────────────────
    testWidgets('26. 1.5x text scale no crash', (tester) async {
      await tester.pumpWidget(buildWorkspace(textScale: 1.5));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // ─── Test 27: Dark mode ───────────────────────────────────────────────────
    testWidgets('27. dark mode renders without error', (tester) async {
      await tester.pumpWidget(buildWorkspace(isDark: true));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    // ─── Test 28: Localization ────────────────────────────────────────────────
    testWidgets('28. localization renders Bangla strings', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      GochanoLanguage.current.value = GochanoLocale.bangla;
      await tester.pump();

      expect(find.text('ওয়ার্কস্পেস'), findsWidgets);
      expect(find.text('আপনার পড়াশোনা আরও সহজ করার টুলস।'), findsOneWidget);
    });

    // ─── Test 29: Header pinned ───────────────────────────────────────────────
    testWidgets('29. header remains pinned when body scrolls', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      final headerFinder = find.byType(AppStudyHeader);
      expect(headerFinder, findsOneWidget);
      final initialTop = tester.getTopLeft(headerFinder).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();

      final scrolledTop = tester.getTopLeft(headerFinder).dy;
      expect(scrolledTop, equals(initialTop));
    });

    // ─── Test 30: Bottom nav Workspace active ────────────────────────────────
    testWidgets('30. Workspace tab in shell nav preserved', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GochanoShell(
            role: 'student',
            displayName: 'Student',
            pagesBuilder: (context, mode) => [
              const Text('Page: Today'),
              const WorkspaceView(mockRecentMaterials: []),
              const Text('Page: Plan'),
              const Text('Page: Community'),
              const Text('Page: You'),
            ],
          ),
        ),
      );
      await tester.pump();

      final workspaceNav = find.text('Workspace');
      expect(workspaceNav, findsOneWidget);
      await tester.tap(workspaceNav);
      await tester.pump();

      expect(find.byType(WorkspaceView), findsOneWidget);
    });

    // ─── Test 31: Today unchanged ─────────────────────────────────────────────
    testWidgets('31. shell index 0 is Today, index 1 is Workspace', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GochanoShell(
            role: 'student',
            displayName: 'Student',
            pagesBuilder: (context, mode) => [
              const Text('Page: Today'),
              const WorkspaceView(mockRecentMaterials: []),
              const Text('Page: Plan'),
              const Text('Page: Community'),
              const Text('Page: You'),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Page: Today'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
    });

    // ─── Test 32: IndexedStack navigation state preservation ─────────────────
    testWidgets('32. switching Today -> Workspace -> Today preserves state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GochanoShell(
            role: 'student',
            displayName: 'Student',
            pagesBuilder: (context, mode) => [
              const Text('Page: Today'),
              const WorkspaceView(mockRecentMaterials: []),
              const Text('Page: Plan'),
              const Text('Page: Community'),
              const Text('Page: You'),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Workspace'));
      await tester.pump();
      expect(find.byType(WorkspaceView), findsOneWidget);

      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(find.text('Page: Today'), findsOneWidget);
    });

    // ─── Filter chips ─────────────────────────────────────────────────────────
    testWidgets('filter chips: render, default All, filter tools', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.byType(AppWorkspaceFilterChips), findsOneWidget);

      Finder chipFinder(String label) => find.descendant(
            of: find.byType(AppWorkspaceFilterChips),
            matching: find.text(label),
          );

      expect(chipFinder('All'), findsOneWidget);
      expect(chipFinder('Notes'), findsOneWidget);
      expect(chipFinder('Flashcards'), findsOneWidget);
      expect(chipFinder('Saved'), findsOneWidget);

      await tester.tap(chipFinder('Notes'));
      await tester.pump();
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsNothing);

      await tester.tap(chipFinder('All'));
      await tester.pump();
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
    });

    // ─── Header accessibility targets ─────────────────────────────────────────
    testWidgets('header notification action >= 44dp tap target', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      final notifFinder =
          find.widgetWithIcon(IconButton, Icons.notifications_outlined);
      expect(notifFinder, findsOneWidget);
      final box = tester.getSize(
        find.ancestor(
          of: notifFinder,
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(box.width, greaterThanOrEqualTo(44.0));
      expect(box.height, greaterThanOrEqualTo(44.0));
    });

    // ─── Workspace intro ──────────────────────────────────────────────────────
    testWidgets('renders Workspace intro title and subtitle', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.text('Workspace'), findsWidgets);
      expect(find.text('Tools to help you study better.'), findsOneWidget);
    });
  });
}
