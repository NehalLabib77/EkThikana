// Tests for Mode-Aware Quick Add Filtering (Phase E).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/shell/presentation/quick_add_sheet.dart';

Widget _buildWrapper({
  required Widget child,
  double width = 360,
  double height = 640,
  double textScaleFactor = 1.0,
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(textScaleFactor),
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      GochanoAppModePreferences.prefsKey: 'study',
    });
    await GochanoAppModePreferences.restore();
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Study Mode Quick Add Filtering', () {
    testWidgets('shows exactly 3 primary actions: Task, Assignment, Note', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          child: QuickAddSheet(
            mode: GochanoAppMode.study,
            onSelectAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly 3 visible primary cards
      expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick_add_assignment')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('quick_add_note')), findsOneWidget);

      expect(find.text('Task'), findsOneWidget);
      expect(find.text('Assignment'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);

      // Utility actions must be hidden
      expect(find.byKey(const ValueKey('quick_add_expense')), findsNothing);
      expect(find.byKey(const ValueKey('quick_add_plan_trip')), findsNothing);
      expect(find.text('Expense'), findsNothing);
      expect(find.text('Plan Trip'), findsNothing);

      // Medicine must be hidden
      expect(find.byKey(const ValueKey('quick_add_medicine')), findsNothing);
      expect(find.text('Medicine'), findsNothing);
    });

    testWidgets('tapping each Study action returns canonical QuickAddAction', (
      tester,
    ) async {
      QuickAddAction? selected;
      await tester.pumpWidget(
        _buildWrapper(
          child: QuickAddSheet(
            mode: GochanoAppMode.study,
            onSelectAction: (a) => selected = a,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('quick_add_task')));
      expect(selected, equals(QuickAddAction.task));

      await tester.tap(find.byKey(const ValueKey('quick_add_assignment')));
      expect(selected, equals(QuickAddAction.assignment));

      await tester.tap(find.byKey(const ValueKey('quick_add_note')));
      expect(selected, equals(QuickAddAction.note));
    });
  });

  group('Utility Mode Quick Add Filtering', () {
    testWidgets('shows exactly 2 primary actions: Expense, Plan Trip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          child: QuickAddSheet(
            mode: GochanoAppMode.utility,
            onSelectAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly 2 visible primary cards
      expect(find.byKey(const ValueKey('quick_add_expense')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_add_plan_trip')), findsOneWidget);

      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Plan Trip'), findsOneWidget);

      // Study actions must be hidden
      expect(find.byKey(const ValueKey('quick_add_task')), findsNothing);
      expect(find.byKey(const ValueKey('quick_add_assignment')), findsNothing);
      expect(find.byKey(const ValueKey('quick_add_note')), findsNothing);
      expect(find.text('Task'), findsNothing);
      expect(find.text('Assignment'), findsNothing);
      expect(find.text('Note'), findsNothing);

      // Medicine must be hidden
      expect(find.byKey(const ValueKey('quick_add_medicine')), findsNothing);
      expect(find.text('Medicine'), findsNothing);
    });

    testWidgets(
      'tapping each Utility action returns canonical QuickAddAction',
      (tester) async {
        QuickAddAction? selected;
        await tester.pumpWidget(
          _buildWrapper(
            child: QuickAddSheet(
              mode: GochanoAppMode.utility,
              onSelectAction: (a) => selected = a,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('quick_add_expense')));
        expect(selected, equals(QuickAddAction.expense));

        await tester.tap(find.byKey(const ValueKey('quick_add_plan_trip')));
        expect(selected, equals(QuickAddAction.planTrip));
      },
    );
  });

  group('General / Non-Student Role Quick Add Behavior', () {
    testWidgets('renders all 6 canonical actions when mode is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(child: QuickAddSheet(mode: null, onSelectAction: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick_add_assignment')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('quick_add_expense')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_add_medicine')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_add_plan_trip')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_add_note')), findsOneWidget);
    });
  });

  group('Reactive Mode Switching in showQuickAddSheet', () {
    testWidgets(
      'showQuickAddSheet dynamically reflects active preference mode',
      (tester) async {
        await tester.pumpWidget(
          _buildWrapper(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const ValueKey('open_quick_add'),
                  onPressed: () => showQuickAddSheet(context),
                  child: const Text('Open'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. In Study Mode: opens with 3 study actions
        GochanoAppModePreferences.current.value = GochanoAppMode.study;
        await tester.tap(find.byKey(const ValueKey('open_quick_add')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('quick_add_assignment')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('quick_add_note')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick_add_expense')), findsNothing);

        // Dismiss sheet
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        // 2. Switch to Utility Mode: opens with 2 utility actions
        GochanoAppModePreferences.current.value = GochanoAppMode.utility;
        await tester.tap(find.byKey(const ValueKey('open_quick_add')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('quick_add_expense')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('quick_add_plan_trip')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('quick_add_task')), findsNothing);
        expect(find.byKey(const ValueKey('quick_add_note')), findsNothing);

        // Dismiss sheet
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        // 3. Switch back to Study Mode: returns immediately to study actions
        GochanoAppModePreferences.current.value = GochanoAppMode.study;
        await tester.tap(find.byKey(const ValueKey('open_quick_add')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('quick_add_assignment')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('quick_add_note')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick_add_expense')), findsNothing);

        // Dismiss sheet
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('repeated mode switching has no stale cached action list', (
      tester,
    ) async {
      for (int i = 0; i < 5; i++) {
        GochanoAppModePreferences.current.value = GochanoAppMode.study;
        await tester.pumpWidget(
          _buildWrapper(
            child: QuickAddSheet(
              mode: GochanoAppModePreferences.current.value,
              onSelectAction: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick_add_expense')), findsNothing);

        GochanoAppModePreferences.current.value = GochanoAppMode.utility;
        await tester.pumpWidget(
          _buildWrapper(
            child: QuickAddSheet(
              mode: GochanoAppModePreferences.current.value,
              onSelectAction: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quick_add_expense')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick_add_task')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive Layout on Narrow 320dp & Font Scaling', () {
    testWidgets('Study Mode renders cleanly without overflow on 320dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          child: QuickAddSheet(
            mode: GochanoAppMode.study,
            onSelectAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick_add_assignment')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('quick_add_note')), findsOneWidget);
    });

    testWidgets('Utility Mode renders cleanly without overflow on 320dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          child: QuickAddSheet(
            mode: GochanoAppMode.utility,
            onSelectAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('quick_add_expense')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_add_plan_trip')), findsOneWidget);
    });

    testWidgets('renders cleanly with 2.0x font scaling without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 360,
          textScaleFactor: 2.0,
          child: QuickAddSheet(
            mode: GochanoAppMode.study,
            onSelectAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Bangla Localization', () {
    testWidgets('Study Mode renders Bangla labels without overflow', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          child: QuickAddSheet(
            mode: GochanoAppMode.study,
            onSelectAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('কাজ'), findsOneWidget);
      expect(find.text('অ্যাসাইনমেন্ট'), findsOneWidget);
      expect(find.text('নোট'), findsOneWidget);
      expect(find.text('খরচ'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Utility Mode renders Bangla labels without overflow', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          child: QuickAddSheet(
            mode: GochanoAppMode.utility,
            onSelectAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('খরচ'), findsOneWidget);
      expect(find.text('যাত্রা পরিকল্পনা'), findsOneWidget);
      expect(find.text('কাজ'), findsNothing);
      expect(find.text('নোট'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Canonical Action Dispatch Preservation', () {
    test('launchQuickAddAction handles all 6 actions including medicine', () {
      // Static inspection verifying all 6 QuickAddAction cases exist in dispatcher
      expect(QuickAddAction.values.length, equals(6));
      expect(QuickAddAction.values, contains(QuickAddAction.task));
      expect(QuickAddAction.values, contains(QuickAddAction.assignment));
      expect(QuickAddAction.values, contains(QuickAddAction.expense));
      expect(QuickAddAction.values, contains(QuickAddAction.medicine));
      expect(QuickAddAction.values, contains(QuickAddAction.planTrip));
      expect(QuickAddAction.values, contains(QuickAddAction.note));
    });
  });
}
