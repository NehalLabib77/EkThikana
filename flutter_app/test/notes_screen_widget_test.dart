// Widget tests for NotesScreen visual polish and interaction integrity.
//
// Verifies:
// 1. My Notes identity, subtitle, and FAB in English (Light Mode).
// 2. My Notes identity, subtitle, and FAB in Bengali.
// 3. Empty state display with guidance referencing the + button.
// 4. Populated notes list rendering titles, subtitles, date metadata, and badges.
// 5. Overflow menu actions (Edit, Delete) on note cards.
// 6. Responsive 320dp narrow layout with zero RenderFlex overflow.
// 7. Dark Mode contrast and background presentation.
// 8. Reduced-motion accessibility.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/app_design_system.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/notes/notes_screen.dart';
import 'package:gochano/shared/widgets/gochano_controls.dart';

class FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  FakeQuerySnapshot(this._docs);
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  int get size => _docs.length;
}

class FakeQueryDocumentSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FakeQueryDocumentSnapshot({
    required this.id,
    required Map<String, dynamic> data,
  }) : _data = data;

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  bool get exists => true;
}

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

  group('NotesScreen Visual & Interaction Tests', () {
    testWidgets('renders My Notes app bar, subtitle, and FAB in English (Light Mode)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NotesScreen(
            notesStream: Stream.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Notes'), findsOneWidget);
      expect(find.text('Create & organize lecture notes'), findsOneWidget);
      expect(find.text('New note'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('renders My Notes app bar and subtitle in Bengali', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _wrap(
          const NotesScreen(
            notesStream: Stream.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('আমার নোট'), findsOneWidget);
      expect(find.text('লেকচার নোট তৈরি ও সাজান'), findsOneWidget);
      expect(find.text('নতুন নোট'), findsOneWidget);
    });

    testWidgets('renders EmptyState when notes stream is empty', (
      tester,
    ) async {
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _wrap(
          NotesScreen(
            notesStream: controller.stream,
          ),
        ),
      );
      // Emit empty snapshot
      controller.add(FakeQuerySnapshot([]));
      await tester.pumpAndSettle();

      expect(find.text('No notes yet'), findsOneWidget);
      expect(
        find.text('Tap the + button to write your first note.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('notes_empty')), findsOneWidget);
    });

    testWidgets('renders populated note cards with title, content preview, date, and shared badge', (
      tester,
    ) async {
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _wrap(
          NotesScreen(
            notesStream: controller.stream,
          ),
        ),
      );

      final noteDate = DateTime(2026, 10, 20, 14, 30);
      final testDocs = [
        FakeQueryDocumentSnapshot(
          id: 'note_1',
          data: {
            'title': 'Operating Systems Lecture 4',
            'content': 'Virtual memory and page replacement algorithms detailed explanation.',
            'visibility': 'private',
            'updatedAt': Timestamp.fromDate(noteDate),
          },
        ),
        FakeQueryDocumentSnapshot(
          id: 'note_2',
          data: {
            'title': 'Database Systems Group Note',
            'content': 'ACID properties and isolation levels summary for group project.',
            'visibility': 'group',
            'groupId': 'study_group_alpha',
            'updatedAt': Timestamp.fromDate(noteDate),
          },
        ),
      ];

      controller.add(FakeQuerySnapshot(testDocs));
      await tester.pumpAndSettle();

      expect(find.text('Operating Systems Lecture 4'), findsOneWidget);
      expect(
        find.text('Virtual memory and page replacement algorithms detailed explanation.'),
        findsOneWidget,
      );
      expect(find.text('20 Oct 2026'), findsNWidgets(2));

      expect(find.text('Database Systems Group Note'), findsOneWidget);
      expect(find.text('Shared'), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
    });

    testWidgets('note card overflow menu reveals Edit and Delete options', (
      tester,
    ) async {
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _wrap(
          NotesScreen(
            notesStream: controller.stream,
          ),
        ),
      );

      controller.add(
        FakeQuerySnapshot([
          FakeQueryDocumentSnapshot(
            id: 'note_1',
            data: {
              'title': 'Physics Quantum Mechanics',
              'content': 'Schrodinger wave equation notes.',
              'visibility': 'private',
              'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 15)),
            },
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Find the overflow menu button
      final menuFinder = find.byType(GochanoOverflowMenu);
      expect(menuFinder, findsOneWidget);

      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('renders cleanly on 320dp narrow viewport with zero overflow', (
      tester,
    ) async {
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _wrap(
          NotesScreen(
            notesStream: controller.stream,
          ),
          size: const Size(320, 600),
        ),
      );

      controller.add(
        FakeQuerySnapshot([
          FakeQueryDocumentSnapshot(
            id: 'note_narrow',
            data: {
              'title': 'Very Long Lecture Note Title Exceeding Width Boundary On Narrow Device Viewports',
              'content': 'Very long body content snippet that tests wrapping, truncation, and layout margins.',
              'visibility': 'group',
              'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
            },
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NotesScreen), findsOneWidget);
    });

    testWidgets('renders cleanly in Dark Mode with dark theme background', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NotesScreen(
            notesStream: Stream.empty(),
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('My Notes'), findsOneWidget);
    });

    testWidgets('respects reduced-motion preferences without animation errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NotesScreen(
            notesStream: Stream.empty(),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
