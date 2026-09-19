import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/life/presentation/expense/add_expense_sheet.dart';
import 'package:gochano/features/life/presentation/medicine/medicine_form_screen.dart';
import 'package:gochano/features/life/presentation/commute/plan_trip_sheet.dart';
import 'package:gochano/features/life/presentation/commute/planned_trip_models.dart';
import 'package:gochano/features/study/presentation/notes/note_editor_screen.dart';
import 'package:gochano/features/tasks/presentation/add_task_sheet.dart';

Widget _buildTestWrapper({required Widget child, double? textScaleFactor}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    builder: (context, widget) {
      if (textScaleFactor != null) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: widget!,
        );
      }
      return widget!;
    },
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Progressive Forms — Task Form', () {
    testWidgets(
      'New task form starts collapsed and reveals reminders on toggle',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWrapper(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAddTaskSheet(context),
                child: const Text('Open Task'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Task'));
        await tester.pumpAndSettle();

        // Primary upfront fields are visible
        expect(find.text('What needs doing?'), findsOneWidget);
        expect(find.text('Due'), findsOneWidget);

        // Collapsible toggle exists
        final toggleFinder = find.byKey(
          const ValueKey('task_more_options_toggle'),
        );
        expect(toggleFinder, findsOneWidget);

        // Reminders are hidden when collapsed
        expect(find.text('10 min before'), findsNothing);

        // Tap toggle to expand
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        // Reminder section is now visible
        expect(find.text('Reminder'), findsOneWidget);
        expect(
          find.text('Select a due date above to set reminders.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Progressive Forms — Expense Form', () {
    testWidgets(
      'New expense starts collapsed and reveals Note and Date on toggle',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWrapper(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAddExpenseSheet(context),
                child: const Text('Open Expense'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Expense'));
        await tester.pumpAndSettle();

        // Primary upfront fields are visible
        expect(find.text('Amount'), findsOneWidget);
        expect(find.text('Category'), findsOneWidget);

        // Collapsible toggle exists
        final toggleFinder = find.byKey(
          const ValueKey('expense_more_options_toggle'),
        );
        expect(toggleFinder, findsOneWidget);

        // Note and Date are hidden by default
        expect(find.text('Note (optional)'), findsNothing);
        expect(find.text('Date'), findsNothing);

        // Tap toggle to expand
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        // Secondary fields are now visible
        expect(find.text('Note (optional)'), findsOneWidget);
        expect(find.text('Date'), findsOneWidget);
      },
    );

    testWidgets('Edit expense with existing note auto-expands on open', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWrapper(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAddExpenseSheet(
                context,
                expenseId: 'exp_123',
                initialAmount: 150,
                initialTitle: 'Canteen meal with friends',
              ),
              child: const Text('Edit Expense'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit Expense'));
      await tester.pumpAndSettle();

      // Note field is auto-expanded because note was provided
      expect(find.text('Note (optional)'), findsOneWidget);
      expect(find.text('Canteen meal with friends'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
    });
  });

  group('Progressive Forms — Medicine Form', () {
    testWidgets(
      'New medicine starts with Name and Reminders primary, secondary collapsed',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWrapper(child: const MedicineFormScreen()),
        );
        await tester.pumpAndSettle();

        // Primary fields are visible
        expect(find.text('Medicine name'), findsOneWidget);
        expect(find.text('Reminder times'), findsOneWidget);

        // Toggle exists
        final toggleFinder = find.byKey(
          const ValueKey('medicine_more_options_toggle'),
        );
        expect(toggleFinder, findsOneWidget);

        // Secondary fields are hidden by default
        expect(find.text('Strength (optional)'), findsNothing);
        expect(find.text('Instruction (optional)'), findsNothing);
        expect(find.text('Each dose'), findsNothing);

        // Tap toggle to expand
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        // Secondary fields are now revealed
        expect(find.text('Strength (optional)'), findsOneWidget);
        expect(find.text('Instruction (optional)'), findsOneWidget);
        expect(find.text('Each dose'), findsOneWidget);
      },
    );

    testWidgets('Edit medicine with secondary data auto-expands on open', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWrapper(
          child: const MedicineFormScreen(
            medicineId: 'med_123',
            initialData: {
              'name': 'Paracetamol',
              'strength': '650 mg',
              'instruction': 'With warm water',
              'times': ['08:00', '20:00'],
              'quantityPerDose': 1,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-expanded
      expect(find.text('Strength (optional)'), findsOneWidget);
      expect(find.widgetWithText(TextField, '650 mg'), findsOneWidget);
      expect(find.text('Instruction (optional)'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'With warm water'), findsOneWidget);
    });
  });

  group('Progressive Forms — Plan Trip Form', () {
    testWidgets(
      'New trip starts with origin, destination, time primary and reminder collapsed',
      (tester) async {
        await tester.pumpWidget(_buildTestWrapper(child: const PlanTripForm()));
        await tester.pumpAndSettle();

        // Primary fields are visible
        expect(find.text('Pick starting place'), findsOneWidget);
        expect(find.text('Pick destination'), findsOneWidget);

        // Toggle exists
        final toggleFinder = find.byKey(
          const ValueKey('trip_more_options_toggle'),
        );
        expect(toggleFinder, findsOneWidget);

        // Leave-by reminder is hidden when collapsed
        expect(find.text('Leave-by Reminder'), findsNothing);

        // Tap toggle to expand
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        // Reminder section is now revealed
        expect(find.text('Leave-by Reminder'), findsOneWidget);
        expect(find.text('30 min before'), findsOneWidget);
      },
    );

    testWidgets('Edit trip with custom reminder auto-expands on open', (
      tester,
    ) async {
      final trip = PlannedCommuteTrip(
        id: 'trip_123',
        ownerId: 'user_123',
        originName: 'Farmgate',
        destinationName: 'Mirpur-10',
        departureTime: DateTime.now().add(const Duration(hours: 3)),
        reminderMinutes: 10,
      );

      await tester.pumpWidget(
        _buildTestWrapper(child: PlanTripForm(existingTrip: trip)),
      );
      await tester.pumpAndSettle();

      // Auto-expanded because reminderMinutes is non-default (10 min != 30 min)
      expect(find.text('Leave-by Reminder'), findsOneWidget);
      expect(find.text('10 min before'), findsOneWidget);
    });
  });

  group('Progressive Forms — Note Editor', () {
    testWidgets(
      'New note starts with Title and Note primary, visibility collapsed',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWrapper(child: const NoteEditorScreen()),
        );
        await tester.pumpAndSettle();

        // Primary fields are visible
        expect(find.text('Title'), findsOneWidget);
        expect(find.text('Note'), findsOneWidget);

        // Toggle exists
        final toggleFinder = find.byKey(
          const ValueKey('note_more_options_toggle'),
        );
        expect(toggleFinder, findsOneWidget);

        // Visibility is hidden when collapsed
        expect(find.text('Visibility'), findsNothing);

        // Tap toggle to expand
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        // Visibility section revealed
        expect(find.text('Visibility'), findsOneWidget);
        expect(find.text('Share to group'), findsOneWidget);
      },
    );

    testWidgets('Edit note with group visibility auto-expands on open', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWrapper(
          child: const NoteEditorScreen(
            noteId: 'note_123',
            initialVisibility: 'group',
            initialGroupId: 'group_456',
            initialGroupName: 'CSE 301 Study Group',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-expanded because visibility is group
      expect(find.text('Visibility'), findsOneWidget);
      expect(find.text('Sharing with: CSE 301 Study Group'), findsOneWidget);
    });
  });

  group('Progressive Forms — Touch Target & Responsive Acceptance', () {
    testWidgets(
      'All more_options_toggle buttons meet Android 48dp minimum touch target',
      (tester) async {
        // 1. Plan Trip toggle
        await tester.pumpWidget(_buildTestWrapper(child: const PlanTripForm()));
        await tester.pumpAndSettle();
        final tripToggle = tester.getSize(
          find.byKey(const ValueKey('trip_more_options_toggle')),
        );
        expect(tripToggle.height, greaterThanOrEqualTo(48.0));

        // 2. Note Editor toggle
        await tester.pumpWidget(
          _buildTestWrapper(child: const NoteEditorScreen()),
        );
        await tester.pumpAndSettle();
        final noteToggle = tester.getSize(
          find.byKey(const ValueKey('note_more_options_toggle')),
        );
        expect(noteToggle.height, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets(
      'PlanTripForm and NoteEditorScreen render smoothly on 320dp narrow device',
      (tester) async {
        tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildTestWrapper(child: const PlanTripForm()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _buildTestWrapper(child: const NoteEditorScreen()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PlanTripForm and NoteEditorScreen render smoothly with 2.0x font scaling',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWrapper(textScaleFactor: 2.0, child: const PlanTripForm()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _buildTestWrapper(
            textScaleFactor: 2.0,
            child: const NoteEditorScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
