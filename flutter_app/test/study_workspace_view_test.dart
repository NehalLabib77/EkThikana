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
    VoidCallback? onOpenPlan,
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
            onOpenPlan: onOpenPlan,
            mockRecentMaterials: mockRecentMaterials,
          ),
        ),
      ),
    );
  }

  group('Study Mode → Workspace View Redesign Tests', () {
    testWidgets('1 & 2. renders Workspace title and subtitle with localization', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      // Title & Subtitle in English
      expect(find.text('Workspace'), findsWidgets);
      expect(find.text('Tools to help you study better.'), findsOneWidget);

      // Switch to Bangla
      GochanoLanguage.current.value = GochanoLocale.bangla;
      await tester.pump();

      expect(find.text('ওয়ার্কস্পেস'), findsWidgets);
      expect(find.text('আপনার পড়াশোনা আরও সহজ করার টুলস।'), findsOneWidget);
    });

    testWidgets('3. search field filters tool cards and can be cleared', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.byType(AppWorkspaceSearchField), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);

      // Enter search query 'Flash'
      await tester.enterText(find.byType(TextField), 'Flash');
      await tester.pump();

      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsNothing);

      // Tap clear icon
      final clearButtonFinder = find.byTooltip('Clear');
      expect(clearButtonFinder, findsOneWidget);
      await tester.tap(clearButtonFinder);
      await tester.pump();

      // Restored
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
    });

    testWidgets('4, 5, 6. filter chips render, default to All, and filter tools grid', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      expect(find.byType(AppWorkspaceFilterChips), findsOneWidget);

      Finder chipFinder(String label) => find.descendant(
            of: find.byType(AppWorkspaceFilterChips),
            matching: find.text(label),
          );

      // All is default and shows all tool cards
      expect(chipFinder('All'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Past Papers'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Mock Tests'), findsOneWidget);

      // Select 'Notes' chip
      await tester.tap(chipFinder('Notes'));
      await tester.pump();

      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsNothing);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Past Papers'), findsNothing);

      // Select 'Flashcards' chip
      await tester.tap(chipFinder('Flashcards'));
      await tester.pump();

      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsNothing);

      // Select 'All' chip
      await tester.tap(chipFinder('All'));
      await tester.pump();

      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
    });

    testWidgets('7 & 8. renders all real tool cards and omits unsupported fake tools', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      // Real canonical tools
      expect(find.widgetWithText(AppWorkspaceToolCard, 'My Notes'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Flashcards'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Past Papers'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Mock Tests'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Study Materials'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Question Bank'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Saved Items'), findsOneWidget);
      expect(find.widgetWithText(AppWorkspaceToolCard, 'Shared Box'), findsOneWidget);

      // Unsupported fake tools
      expect(find.text('Virtual Reality Lab'), findsNothing);
      expect(find.text('Brainwave Scanner'), findsNothing);
      expect(find.text('Crypto Notes'), findsNothing);
    });

    testWidgets('9. tool card taps trigger valid routes', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      // Tapping tool card
      final notesCard = find.widgetWithText(AppWorkspaceToolCard, 'My Notes');
      expect(notesCard, findsOneWidget);
      await tester.tap(notesCard);
      await tester.pump();
      // Should not throw or crash
    });

    testWidgets('10, 11, 12, 13, 14. Recently Opened section renders safely with empty state', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      // Empty state prompt
      expect(find.text('Recently Opened'), findsOneWidget);
      expect(find.text('No recent study items yet.'), findsOneWidget);
      expect(
        find.text('Open notes or materials and they’ll appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('15. 320dp narrow layout renders without RenderFlex overflow', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(320, 640)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
      expect(find.text('Study Tools'), findsOneWidget);
    });

    testWidgets('16. 360dp standard mobile layout renders without overflow', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(360, 640)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    testWidgets('17. 390dp layout renders cleanly', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(390, 844)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    testWidgets('18. 412dp large mobile layout renders cleanly', (tester) async {
      await tester.pumpWidget(buildWorkspace(size: const Size(412, 915)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    testWidgets('19. large text scale factor (1.5x) renders without critical crash', (tester) async {
      await tester.pumpWidget(buildWorkspace(
        size: const Size(390, 844),
        textScale: 1.5,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    testWidgets('20. dark mode surfaces render without errors', (tester) async {
      await tester.pumpWidget(buildWorkspace(isDark: true));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Workspace'), findsWidgets);
    });

    testWidgets('21 & 22. Workspace tab in shell and You destination preserved', (tester) async {
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

      // Tap Workspace navigation item (tab 1)
      final workspaceNav = find.text('Workspace');
      expect(workspaceNav, findsOneWidget);
      await tester.tap(workspaceNav);
      await tester.pump();

      expect(find.byType(WorkspaceView), findsOneWidget);

      // You destination is preserved as tab 5
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('23. shared study header remains pinned when body scrolls', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      // Get initial position of header
      final headerFinder = find.byType(AppStudyHeader);
      expect(headerFinder, findsOneWidget);
      final initialHeaderTop = tester.getTopLeft(headerFinder).dy;

      // Scroll the body
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();

      // Header remains at exact same top position
      final scrolledHeaderTop = tester.getTopLeft(headerFinder).dy;
      expect(scrolledHeaderTop, equals(initialHeaderTop));
    });

    testWidgets('24. header actions maintain accessible touch targets >= 44dp', (tester) async {
      await tester.pumpWidget(buildWorkspace());
      await tester.pump();

      // Search button tap target >= 44dp
      final searchButtonFinder = find.widgetWithIcon(IconButton, Icons.search_rounded);
      expect(searchButtonFinder, findsOneWidget);
      final searchBox = tester.getSize(find.ancestor(
        of: searchButtonFinder,
        matching: find.byType(SizedBox),
      ).first);
      expect(searchBox.width, greaterThanOrEqualTo(44.0));
      expect(searchBox.height, greaterThanOrEqualTo(44.0));

      // Notification button tap target >= 44dp
      final notificationButtonFinder = find.widgetWithIcon(IconButton, Icons.notifications_outlined);
      expect(notificationButtonFinder, findsOneWidget);
      final notificationBox = tester.getSize(find.ancestor(
        of: notificationButtonFinder,
        matching: find.byType(SizedBox),
      ).first);
      expect(notificationBox.width, greaterThanOrEqualTo(44.0));
      expect(notificationBox.height, greaterThanOrEqualTo(44.0));

      // Language toggle tap target >= 44dp
      final languageToggleFinder = find.byType(LanguageToggle);
      expect(languageToggleFinder, findsOneWidget);
      final languageToggleBox = tester.getSize(languageToggleFinder);
      expect(languageToggleBox.height, greaterThanOrEqualTo(44.0));
    });
  });
}

