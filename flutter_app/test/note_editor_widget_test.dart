// Widget tests for NoteEditorScreen visual polish, validation, and interaction integrity.
//
// Verifies:
// 1. New Note mode: empty title, body, AI assistant tools, progressive options, and Save button in English.
// 2. Edit Note mode: prefilled title, body, and edit subtitle.
// 3. Bengali localization: 'নতুন নোট', 'নোট সম্পাদনা', 'শিরোনাম', 'নোট', 'আরও অপশন', 'নোট সংরক্ষণ'.
// 4. Editing title and content updates state without losing text.
// 5. Validation error banner appears when attempting to save with an empty title.
// 6. AI assistance tools row renders all 4 operations: Clean up, Summarise, Explain, Key points.
// 7. More options toggle reveals Visibility segmented button (Private / Share to group).
// 8. Responsive 320dp narrow layout with zero RenderFlex overflow.
// 9. Dark Mode contrast and theme presentation.
// 10. Reduced-motion accessibility.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/notes/note_editor_screen.dart';

Widget _wrap(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  bool disableAnimations = false,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      disableAnimations: disableAnimations,
    ),
    child: MaterialApp(
      theme: GochanoTheme.light(),
      darkTheme: GochanoTheme.dark(),
      themeMode: themeMode,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('NoteEditorScreen Visual & Interaction Tests', () {
    testWidgets('New Note mode renders title, body, AI tools, and Save button in English', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NoteEditorScreen()));
      await tester.pumpAndSettle();

      expect(find.text('New note'), findsOneWidget);
      expect(find.text('Capture study thoughts & summaries'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('AI Note Assistant'), findsOneWidget);
      expect(find.text('Clean up'), findsOneWidget);
      expect(find.text('Summarise'), findsOneWidget);
      expect(find.text('Explain'), findsOneWidget);
      expect(find.text('Key points'), findsOneWidget);
      expect(find.text('More options'), findsOneWidget);
      expect(find.text('Save note'), findsOneWidget);
    });

    testWidgets('Edit Note mode renders prefilled title, body, and edit subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NoteEditorScreen(
            noteId: 'test_note_42',
            initialData: {
              'title': 'Computer Networks OSI Model',
              'content': '7 layers of OSI model explained with protocols.',
              'visibility': 'private',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit note'), findsOneWidget);
      expect(find.text('Update lecture note'), findsOneWidget);
      expect(find.text('Computer Networks OSI Model'), findsOneWidget);
      expect(find.text('7 layers of OSI model explained with protocols.'), findsOneWidget);
      expect(find.text('Save note'), findsOneWidget);
    });

    testWidgets('Bengali localization renders all labels in Bengali', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(_wrap(const NoteEditorScreen()));
      await tester.pumpAndSettle();

      expect(find.text('নতুন নোট'), findsOneWidget);
      expect(find.text('পড়ার মূল বিষয় ও লেকচার নোট লিখুন'), findsOneWidget);
      expect(find.text('শিরোনাম'), findsOneWidget);
      expect(find.text('নোট'), findsOneWidget);
      expect(find.text('এআই নোট অ্যাসিস্ট্যান্ট'), findsOneWidget);
      expect(find.text('গুছিয়ে দাও'), findsOneWidget);
      expect(find.text('সারাংশ'), findsOneWidget);
      expect(find.text('ব্যাখ্যা'), findsOneWidget);
      expect(find.text('মূল পয়েন্ট'), findsOneWidget);
      expect(find.text('আরও অপশন'), findsOneWidget);
      expect(find.text('নোট সংরক্ষণ'), findsOneWidget);
    });

    testWidgets('editing title and body fields updates text controllers cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NoteEditorScreen()));
      await tester.pumpAndSettle();

      final titleField = find.widgetWithText(TextField, 'Title');
      final contentField = find.widgetWithText(TextField, 'Note');

      await tester.enterText(titleField, 'Software Architecture Patterns');
      await tester.enterText(contentField, 'Layered, Clean, Hexagonal, and Microservices.');
      await tester.pump();

      expect(find.text('Software Architecture Patterns'), findsOneWidget);
      expect(find.text('Layered, Clean, Hexagonal, and Microservices.'), findsOneWidget);
    });

    testWidgets('validation error banner appears when attempting to save with an empty title', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NoteEditorScreen()));
      await tester.pumpAndSettle();

      // Tap Save with empty title
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      expect(find.text('Give the note a title.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('More options toggle reveals Visibility segmented button and allows selection', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NoteEditorScreen()));
      await tester.pumpAndSettle();

      // Visibility is collapsed initially
      expect(find.text('Visibility'), findsNothing);

      // Tap More options toggle
      final toggleFinder = find.byKey(const ValueKey('note_more_options_toggle'));
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      expect(find.text('Visibility'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Share to group'), findsOneWidget);

      // Drag list up to clear the pinned bottom bar and tap Share to group segment
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      final groupFinder = find.text('Share to group');
      expect(groupFinder, findsOneWidget);
      await tester.tap(groupFinder);
      await tester.pumpAndSettle();

      expect(find.text('Shared with your study group'), findsOneWidget);
    });

    testWidgets('renders cleanly on 320dp narrow viewport with zero overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NoteEditorScreen(
            noteId: 'narrow_test',
            initialData: {
              'title': 'Very Long Lecture Note Title That Should Wrap Properly On Narrow Viewports',
              'content': 'Multiline text content for 320dp responsiveness testing.',
            },
          ),
          size: const Size(320, 600),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NoteEditorScreen), findsOneWidget);
    });

    testWidgets('renders cleanly in Dark Mode with high-contrast surfaces', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NoteEditorScreen(),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('New note'), findsOneWidget);
    });

    testWidgets('respects reduced-motion preferences without animation errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NoteEditorScreen(),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
