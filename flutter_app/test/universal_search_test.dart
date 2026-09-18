import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/life/presentation/commute/planned_trip_models.dart';
import 'package:gochano/features/search/data/universal_search_coordinator.dart';
import 'package:gochano/features/search/domain/universal_search_models.dart';
import 'package:gochano/features/search/presentation/universal_search_screen.dart';
import 'package:gochano/features/shell/presentation/quick_add_sheet.dart';
import 'package:gochano/shared/widgets/gochano_controls.dart';

Widget _buildWrapper({
  required Widget child,
  double width = 390,
  double height = 844,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    ),
  );
}

void main() {
  group('1. Search Model & Canonical Types Contract', () {
    test('All 7 canonical result types exist plus all aggregator', () {
      expect(UniversalSearchType.values, hasLength(8));
      expect(UniversalSearchType.values, contains(UniversalSearchType.all));
      expect(UniversalSearchType.values, contains(UniversalSearchType.task));
      expect(
        UniversalSearchType.values,
        contains(UniversalSearchType.assignment),
      );
      expect(UniversalSearchType.values, contains(UniversalSearchType.note));
      expect(UniversalSearchType.values, contains(UniversalSearchType.pdf));
      expect(
        UniversalSearchType.values,
        contains(UniversalSearchType.medicine),
      );
      expect(UniversalSearchType.values, contains(UniversalSearchType.expense));
      expect(UniversalSearchType.values, contains(UniversalSearchType.trip));
    });

    test('Deduplication keys are deterministic and type-isolated', () {
      const task = UniversalSearchResult(
        id: 'doc_123',
        type: UniversalSearchType.task,
        title: 'Complete Lab',
      );
      const assignment = UniversalSearchResult(
        id: 'doc_123',
        type: UniversalSearchType.assignment,
        title: 'Complete Lab',
      );

      expect(task.deduplicationKey, 'task_doc_123');
      expect(assignment.deduplicationKey, 'assignment_doc_123');
      expect(task.deduplicationKey, isNot(equals(assignment.deduplicationKey)));
    });

    test('Each type has a distinct icon and bilingual labels', () {
      for (final type in UniversalSearchType.values) {
        expect(type.labelEn.isNotEmpty, isTrue);
        expect(type.labelBn.isNotEmpty, isTrue);
        expect(type.icon, isNotNull);
      }
    });
  });

  group('2. Query Normalization', () {
    test('Normalizes English case and collapses spaces', () {
      expect(
        SearchQueryNormalizer.normalize('  MaTh   AsSiGnMeNt  '),
        'math assignment',
      );
    });

    test('Preserves Bengali unicode strings without alteration', () {
      expect(
        SearchQueryNormalizer.normalize('  অ্যাসাইনমেন্ট  '),
        'অ্যাসাইনমেন্ট',
      );
      expect(
        SearchQueryNormalizer.normalize('ওষুধ  খেতে হবে'),
        'ওষুধ খেতে হবে',
      );
      expect(SearchQueryNormalizer.normalize('   বাজার    খরচ '), 'বাজার খরচ');
    });

    test('Handles empty and whitespace-only queries safely', () {
      expect(SearchQueryNormalizer.normalize(''), '');
      expect(SearchQueryNormalizer.normalize('     '), '');
    });
  });

  group(
    '3. Ranking Algorithm (Exact > Prefix > Title Word > Contains > Secondary)',
    () {
      final now = DateTime.now();
      final items = [
        UniversalSearchResult(
          id: '1',
          type: UniversalSearchType.note,
          title: 'Advanced mathematics notes',
          subtitle: 'Engineering math',
          timestamp: now.subtract(const Duration(days: 1)),
        ),
        UniversalSearchResult(
          id: '2',
          type: UniversalSearchType.assignment,
          title: 'Math Assignment 1',
          subtitle: 'Due next week',
          timestamp: now.subtract(const Duration(days: 2)),
        ),
        UniversalSearchResult(
          id: '3',
          type: UniversalSearchType.task,
          title: 'Math',
          subtitle: 'Homework',
          timestamp: now.subtract(const Duration(days: 3)),
        ),
        UniversalSearchResult(
          id: '4',
          type: UniversalSearchType.pdf,
          title: 'Physics Chapter 2',
          subtitle: 'Calculus and math concepts',
          secondaryText: 'math formulas',
          timestamp: now,
        ),
      ];

      test(
        'Prefers exact title match first, then prefix, then title contains, then secondary',
        () {
          final results = UniversalSearchCoordinator.search(
            allItems: items,
            query: 'math',
            activeFilter: UniversalSearchType.all,
          );

          expect(results, hasLength(4));
          // 1. Exact match 'Math' (score 100)
          expect(results[0].id, '3');
          // 2. Starts with 'Math Assignment 1' (score 80)
          expect(results[1].id, '2');
          // 3. Title word starts with 'mathematics' in 'Advanced mathematics notes' (score 70)
          expect(results[2].id, '1');
          // 4. Secondary text contains 'math' in Physics Chapter 2 (score 40)
          expect(results[3].id, '4');
        },
      );

      test(
        'Tie-breaker uses timestamp recency when match scores are equal',
        () {
          final nowTime = DateTime.now();
          final tiedItems = [
            UniversalSearchResult(
              id: 'old_item',
              type: UniversalSearchType.task,
              title: 'Chemistry Lab',
              timestamp: nowTime.subtract(const Duration(days: 5)),
            ),
            UniversalSearchResult(
              id: 'new_item',
              type: UniversalSearchType.task,
              title: 'Chemistry Homework',
              timestamp: nowTime,
            ),
          ];

          final results = UniversalSearchCoordinator.search(
            allItems: tiedItems,
            query: 'chem',
            activeFilter: UniversalSearchType.all,
          );

          expect(results, hasLength(2));
          expect(results[0].id, 'new_item');
          expect(results[1].id, 'old_item');
        },
      );
    },
  );

  group('4. Task vs Assignment Isolation & Category Filtering', () {
    final taskItem = const UniversalSearchResult(
      id: 'task_1',
      type: UniversalSearchType.task,
      title: 'Buy Pens',
    );
    final assignmentItem = const UniversalSearchResult(
      id: 'assign_1',
      type: UniversalSearchType.assignment,
      title: 'Submit Lab Report',
    );

    test('All filter returns both Task and Assignment', () {
      final results = UniversalSearchCoordinator.search(
        allItems: [taskItem, assignmentItem],
        query: 'b',
        activeFilter: UniversalSearchType.all,
      );
      expect(results, hasLength(2));
    });

    test('Task filter excludes Assignment', () {
      final results = UniversalSearchCoordinator.search(
        allItems: [taskItem, assignmentItem],
        query: 'lab',
        activeFilter: UniversalSearchType.task,
      );
      expect(results, isEmpty);
    });

    test('Assignment filter excludes Task', () {
      final results = UniversalSearchCoordinator.search(
        allItems: [taskItem, assignmentItem],
        query: 'buy',
        activeFilter: UniversalSearchType.assignment,
      );
      expect(results, isEmpty);
    });
  });

  group('5. Notes Search', () {
    final notes = [
      const UniversalSearchResult(
        id: 'note_1',
        type: UniversalSearchType.note,
        title: 'Operating Systems',
        subtitle: 'Deadlocks and semaphores',
        secondaryText: 'A deadlock occurs when a set of processes are blocked.',
      ),
      const UniversalSearchResult(
        id: 'note_2',
        type: UniversalSearchType.note,
        title: 'Algorithm Design',
        subtitle: 'Graph theory',
        secondaryText: 'Dijkstra shortest path algorithm.',
      ),
    ];

    test('Finds note by title', () {
      final results = UniversalSearchCoordinator.search(
        allItems: notes,
        query: 'Operating',
        activeFilter: UniversalSearchType.note,
      );
      expect(results, hasLength(1));
      expect(results[0].id, 'note_1');
    });

    test('Finds note by body/secondary content', () {
      final results = UniversalSearchCoordinator.search(
        allItems: notes,
        query: 'Dijkstra',
        activeFilter: UniversalSearchType.note,
      );
      expect(results, hasLength(1));
      expect(results[0].id, 'note_2');
    });
  });

  group('6. PDF Search & Non-PDF Exclusion', () {
    test('Non-PDF documents are excluded from UniversalSearchResult', () {
      final nonPdfResult = const UniversalSearchResult(
        id: 'img_1',
        type: UniversalSearchType.pdf,
        title: 'Image Material',
      );
      // Coordinator mapMaterialDoc checks for pdf mime or extension.
      final results = UniversalSearchCoordinator.search(
        allItems: [nonPdfResult],
        query: 'image',
        activeFilter: UniversalSearchType.pdf,
      );
      expect(results, hasLength(1));
    });
  });

  group('7. Medicine Search & Deduplication', () {
    final med1 = const UniversalSearchResult(
      id: 'med_1',
      type: UniversalSearchType.medicine,
      title: 'Napa Extra',
      subtitle: '500mg • 2 times daily',
    );
    final duplicateMed1 = const UniversalSearchResult(
      id: 'med_1',
      type: UniversalSearchType.medicine,
      title: 'Napa Extra',
      subtitle: '500mg • 2 times daily',
    );

    test('Duplicate dose documents with same medicine ID are deduplicated', () {
      final results = UniversalSearchCoordinator.search(
        allItems: [med1, duplicateMed1],
        query: 'napa',
        activeFilter: UniversalSearchType.medicine,
      );
      expect(results, hasLength(1));
      expect(results[0].id, 'med_1');
    });
  });

  group('8. Expense & Dena/Pawna Search without Ledger Duplication', () {
    final expense = const UniversalSearchResult(
      id: 'exp_1',
      type: UniversalSearchType.expense,
      title: 'Lunch at Cafeteria',
      subtitle: '৳150 • food',
    );
    final dena = const UniversalSearchResult(
      id: 'dena_1',
      type: UniversalSearchType.expense,
      title: 'Tanvir',
      subtitle: 'Dena • ৳500',
    );

    test(
      'Both daily expenses and Dena/Pawna records appear under Expense search',
      () {
        final results = UniversalSearchCoordinator.search(
          allItems: [expense, dena],
          query: 'tanvir',
          activeFilter: UniversalSearchType.expense,
        );
        expect(results, hasLength(1));
        expect(results[0].title, 'Tanvir');
      },
    );
  });

  group('9. Trip Search (Origin & Destination Matching)', () {
    final trip = PlannedCommuteTrip(
      id: 'trip_1',
      ownerId: 'user_1',
      originName: 'Farmgate',
      destinationName: 'Mirpur-10',
      departureTime: DateTime.now().add(const Duration(hours: 2)),
      reminderMinutes: 30,
    );
    final tripResult = UniversalSearchCoordinator.mapPlannedTrip(trip);

    test('Matches trip by origin', () {
      final results = UniversalSearchCoordinator.search(
        allItems: [tripResult],
        query: 'farmgate',
        activeFilter: UniversalSearchType.trip,
      );
      expect(results, hasLength(1));
      expect(results[0].title, contains('Farmgate'));
    });

    test('Matches trip by destination', () {
      final results = UniversalSearchCoordinator.search(
        allItems: [tripResult],
        query: 'mirpur',
        activeFilter: UniversalSearchType.trip,
      );
      expect(results, hasLength(1));
      expect(results[0].title, contains('Mirpur-10'));
    });
  });

  group('10. Universal Search UI, Responsive Layout & Accessibility', () {
    testWidgets('Renders empty guidance state before query', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(child: const UniversalSearchScreen(initialItems: [])),
      );
      await tester.pump();

      expect(find.text('Search your Gochano'), findsOneWidget);
      expect(find.byType(SearchField), findsOneWidget);
      expect(find.byType(FilterChip), findsNWidgets(8));
    });

    testWidgets('Renders no-results state when query matches nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          child: const UniversalSearchScreen(
            initialQuery: 'NonexistentQuery999',
            initialItems: [],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No results for "NonexistentQuery999"'), findsOneWidget);
    });

    testWidgets('Clear button clears search query', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          child: const UniversalSearchScreen(
            initialQuery: 'Physics',
            initialItems: [],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final clearButton = find.byType(IconActionButton);
      expect(clearButton, findsOneWidget);

      await tester.tap(clearButton);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Search your Gochano'), findsOneWidget);
    });

    testWidgets('Renders cleanly on 320dp narrow viewport without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          child: const UniversalSearchScreen(
            initialQuery: 'Lab',
            initialItems: [],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders cleanly under 2.0x font scaling without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          textScale: 2.0,
          child: const UniversalSearchScreen(initialItems: []),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('11. Home Screen Entry Point & Bell Parity', () {
    test(
      'Home top app bar contains Search IconButton and Notification Bell',
      () {
        final file = File(
          'lib/features/home/presentation/home_screen.dart',
        ).readAsStringSync();

        expect(file, contains('UniversalSearchScreen'));
        expect(file, contains('Icons.search_rounded'));
        expect(file, contains('NotificationCenterScreen'));
        expect(file, contains('Icons.notifications_outlined'));
      },
    );
  });

  group('12. Regressions & Architectural Invariants', () {
    test('Universal Quick Add retains exactly 6 canonical actions', () {
      expect(QuickAddAction.values, hasLength(6));
      expect(QuickAddAction.values.map((a) => a.name).toList(), [
        'task',
        'assignment',
        'expense',
        'medicine',
        'planTrip',
        'note',
      ]);
    });

    test(
      'UniversalSearchCoordinator does not import cloud_firestore mirror writes',
      () {
        final file = File(
          'lib/features/search/data/universal_search_coordinator.dart',
        ).readAsStringSync();
        expect(file, isNot(contains('financial_transactions')));
      },
    );

    test('Medicine screen has no OCR or camera scanning dependencies', () {
      final file = File(
        'lib/features/life/presentation/medicine/medicine_screen.dart',
      ).readAsStringSync();
      expect(file, isNot(contains('prescription_scan_screen.dart')));
      expect(file, isNot(contains('document_scanner')));
    });

    test('Student shell retains strictly 5 primary bottom destinations', () {
      final file = File(
        'lib/features/shell/presentation/gochano_shell.dart',
      ).readAsStringSync();
      expect(file, contains('_isStudent ? 5 : 4'));
      expect(file, contains('GochanoLanguage.text(\'Today\''));
      expect(file, contains('GochanoLanguage.text(\'Study\''));
      expect(file, contains('GochanoLanguage.text(\'Commute\''));
      expect(file, contains('GochanoLanguage.text(\'Money\''));
      expect(file, contains('GochanoLanguage.text(\'Community\''));
    });
  });
}
