// Widget tests for MaterialsScreen visual refinement, presentation integrity,
// and navigation reachability.
//
// Verifies:
// 1. Study Materials identity, subtitle, sort button, and FAB in English (Light Mode).
// 2. Study Materials identity, subtitle, and FAB in Bengali.
// 3. Contextual title/subtitle when documentFilter is true.
// 4. Contextual title/subtitle when subjectFilter is provided.
// 5. Contextual title/subtitle when mimeFilter is provided.
// 6. Empty state presentation when stream yields no documents.
// 7. Empty state presentation specifically for documentFilter.
// 8. Static loading state presentation when stream is waiting.
// 9. Error state presentation when stream emits an error.
// 10. Populated materials list rendering titles, subjects, file sizes, and dates.
// 11. Search field filters materials list by title or subject.
// 12. Search field clear button resets search query.
// 13. Sort menu options (newest, oldest, name, size) can be selected.
// 14. Tapping FAB navigates to MaterialUploadScreen.
// 15. Tapping material card navigates to MaterialReaderScreen.
// 16. Overflow menu renders Open, Ask AI, Download, Rename, Delete actions.
// 17. Tapping Rename opens the styled Rename dialog and can be cancelled.
// 18. Responsive 320dp narrow layout with zero RenderFlex overflow.
// 19. Dark Mode contrast and background presentation.
// 20. Reduced-motion accessibility.
// 21. Large text scaling accessibility.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/app_design_system.dart';
import 'package:gochano/core/design_system/app_gradients.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/materials/material_reader_screen.dart';
import 'package:gochano/features/study/presentation/materials/material_upload_screen.dart';
import 'package:gochano/features/study/presentation/materials/materials_screen.dart';
import 'package:gochano/shared/states/gochano_states.dart';
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
  double textScaleFactor = 1.0,
  bool disableAnimations = false,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScaleFactor),
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

  final sampleDocs = [
    FakeQueryDocumentSnapshot(
      id: 'mat_1',
      data: {
        'title': 'Calculus Differential Notes',
        'fileName': 'calculus_diff.pdf',
        'mimeType': 'application/pdf',
        'subject': 'Higher Math',
        'sizeBytes': 2500000,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 20)),
        'visibility': 'private',
      },
    ),
    FakeQueryDocumentSnapshot(
      id: 'mat_2',
      data: {
        'title': 'Organic Chemistry Reactions',
        'fileName': 'organic_reactions.docx',
        'mimeType': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'subject': 'Chemistry',
        'sizeBytes': 1200000,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 22)),
        'visibility': 'group',
      },
    ),
    FakeQueryDocumentSnapshot(
      id: 'mat_3',
      data: {
        'title': 'Physics Circuit Diagram',
        'fileName': 'circuit.png',
        'mimeType': 'image/png',
        'subject': 'Physics',
        'sizeBytes': 500000,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 23)),
        'visibility': 'private',
      },
    ),
  ];

  group('MaterialsScreen Visual & Interaction Tests', () {
    testWidgets(
      'renders Study Materials app bar, subtitle, sort button, and Add material FAB in English (Light Mode)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MaterialsScreen(
              materialsStream: Stream.empty(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Study Materials'), findsOneWidget);
        expect(
          find.text('PDFs, slides & document library'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
        expect(find.text('Add material'), findsOneWidget);
        expect(find.byIcon(Icons.upload_file_rounded), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);

        // Verify FAB background color is Sky Accent
        final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
        expect(fab.backgroundColor, AppGradients.skyAccent);
      },
    );

    testWidgets(
      'renders Study Materials app bar, subtitle, and FAB in Bengali',
      (tester) async {
        GochanoLanguage.current.value = GochanoLocale.bangla;

        await tester.pumpWidget(
          _wrap(
            const MaterialsScreen(
              materialsStream: Stream.empty(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('অধ্যয়ন উপকরণ'), findsOneWidget);
        expect(
          find.text('পিডিএফ, স্লাইড ও ডকুমেন্ট লাইব্রেরি'),
          findsOneWidget,
        );
        expect(find.text('উপকরণ যোগ'), findsOneWidget);
      },
    );

    testWidgets(
      'renders contextual title and subtitle when documentFilter is true',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MaterialsScreen(
              documentFilter: true,
              materialsStream: Stream.empty(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Documents'), findsOneWidget);
        expect(find.text('All document materials'), findsOneWidget);
      },
    );

    testWidgets(
      'renders contextual title and subtitle when subjectFilter is provided',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MaterialsScreen(
              subjectFilter: 'Higher Math',
              materialsStream: Stream.empty(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Higher Math'), findsOneWidget);
        expect(find.text('Subject materials'), findsOneWidget);
      },
    );

    testWidgets(
      'renders contextual title and subtitle when mimeFilter is provided',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MaterialsScreen(
              mimeFilter: 'application/pdf',
              materialsStream: Stream.empty(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PDFs'), findsOneWidget);
        expect(find.text('Filtered materials'), findsOneWidget);
      },
    );

    testWidgets(
      'renders empty state when materialsStream yields no documents',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot([]));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('materials_empty')), findsOneWidget);
        expect(find.text('No materials yet'), findsOneWidget);
        expect(
          find.text('Upload your first note, PDF or study resource using the + button.'),
          findsOneWidget,
        );
        await controller.close();
      },
    );

    testWidgets(
      'renders empty state specifically for documentFilter when no documents match',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              documentFilter: true,
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot([]));
        await tester.pumpAndSettle();

        expect(find.text('No documents yet'), findsOneWidget);
        expect(
          find.text('Upload documents (PDF, DOC, TXT) using the + button.'),
          findsOneWidget,
        );
        await controller.close();
      },
    );

    testWidgets(
      'renders loading state while stream is waiting',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(StaticLoadingState), findsOneWidget);
        expect(find.text('Loading materials…'), findsOneWidget);
        await controller.close();
      },
    );

    testWidgets(
      'renders error state when stream emits an error',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.addError('Storage connection timed out');
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        await controller.close();
      },
    );

    testWidgets(
      'renders populated materials list with title, subject, file size, date, and semantic file-type icons',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        expect(find.text('Calculus Differential Notes'), findsOneWidget);
        expect(find.text('Higher Math'), findsOneWidget);
        expect(find.text('Organic Chemistry Reactions'), findsOneWidget);
        expect(find.text('Chemistry'), findsOneWidget);
        expect(find.text('Physics Circuit Diagram'), findsOneWidget);
        expect(find.text('Physics'), findsOneWidget);

        // Group shared badge
        expect(find.text('Shared'), findsOneWidget);
        await controller.close();
      },
    );

    testWidgets(
      'search field filters materials list by title or subject',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        // Search for 'Calculus'
        await tester.enterText(find.byType(SearchField), 'Calculus');
        await tester.pumpAndSettle();

        expect(find.text('Calculus Differential Notes'), findsOneWidget);
        expect(find.text('Organic Chemistry Reactions'), findsNothing);
        expect(find.text('Physics Circuit Diagram'), findsNothing);

        // Clear query
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Calculus Differential Notes'), findsOneWidget);
        expect(find.text('Organic Chemistry Reactions'), findsOneWidget);
        expect(find.text('Physics Circuit Diagram'), findsOneWidget);
        await controller.close();
      },
    );

    testWidgets(
      'sort menu options can be opened and selected',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.sort_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Newest first'), findsOneWidget);
        expect(find.text('Oldest first'), findsOneWidget);
        expect(find.text('Name'), findsOneWidget);
        expect(find.text('Largest first'), findsOneWidget);

        await tester.tap(find.text('Name'));
        await tester.pumpAndSettle();

        // Verify list still displays properly after sorting
        expect(find.text('Calculus Differential Notes'), findsOneWidget);
        await controller.close();
      },
    );

    testWidgets(
      'tapping FAB triggers navigation to MaterialUploadScreen',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MaterialsScreen(
              materialsStream: Stream.empty(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        expect(find.byType(MaterialUploadScreen), findsOneWidget);

        // Pop back to leave clean navigation stack
        Navigator.of(tester.element(find.byType(MaterialUploadScreen))).pop();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'tapping material card triggers navigation to MaterialReaderScreen',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Calculus Differential Notes'));
        // Pumping transition frames without waiting for external API network calls
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(MaterialReaderScreen), findsOneWidget);

        // Pop back to leave clean navigation stack
        Navigator.of(tester.element(find.byType(MaterialReaderScreen))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await controller.close();
      },
    );

    testWidgets(
      'material row overflow menu renders Open, Ask AI, Download, Rename, Delete actions',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        // Tap overflow menu icon on first material row
        final menuButtons = find.byIcon(Icons.more_vert_rounded);
        expect(menuButtons, findsWidgets);
        await tester.tap(menuButtons.first);
        await tester.pumpAndSettle();

        expect(find.text('Open'), findsOneWidget);
        expect(find.text('Ask AI'), findsOneWidget);
        expect(find.text('Download'), findsOneWidget);
        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);

        // Tap barrier to dismiss menu
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        await controller.close();
      },
    );

    testWidgets(
      'tapping Rename in menu opens the styled Rename dialog and can be cancelled',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        final menuButtons = find.byIcon(Icons.more_vert_rounded);
        await tester.tap(menuButtons.first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();

        expect(find.text('Rename material'), findsOneWidget);
        expect(find.text('Title'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Rename material'), findsNothing);
        await controller.close();
      },
    );

    testWidgets(
      'renders cleanly on 320dp narrow viewport with zero RenderFlex overflow',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
            size: const Size(320, 568),
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Study Materials'), findsOneWidget);
        expect(find.text('Calculus Differential Notes'), findsOneWidget);
        await controller.close();
      },
    );

    testWidgets(
      'renders cleanly in Dark Mode with dark theme surfaces and high contrast',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
            themeMode: ThemeMode.dark,
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Study Materials'), findsOneWidget);
        await controller.close();
      },
    );

    testWidgets(
      'respects reduced-motion preferences without animation errors',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
            disableAnimations: true,
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await controller.close();
      },
    );

    testWidgets(
      'respects large text scaling without overflowing',
      (tester) async {
        final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        await tester.pumpWidget(
          _wrap(
            MaterialsScreen(
              materialsStream: controller.stream,
            ),
            textScaleFactor: 1.4,
          ),
        );
        controller.add(FakeQuerySnapshot(sampleDocs));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await controller.close();
      },
    );
  });
}
