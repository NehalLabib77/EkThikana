import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/shell/presentation/quick_add_sheet.dart';

Widget _buildTestWrapper({
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
  group('Universal Quick Add — Static Architecture & Purity Guards', () {
    test(
      'quick_add_sheet.dart is a pure coordinator and does not import write services',
      () {
        final content = File(
          'lib/features/shell/presentation/quick_add_sheet.dart',
        ).readAsStringSync();

        expect(content, isNot(contains('cloud_firestore')));
        expect(content, isNot(contains('firebase_auth')));
        expect(content, isNot(contains('firebase_core')));
        expect(content, isNot(contains('firestore_service.dart')));
        expect(content, isNot(contains('financial_service.dart')));
        expect(content, isNot(contains('commute_trip_service.dart')));
      },
    );

    test('gochano_shell.dart student destinations remain strictly 5', () {
      final content = File(
        'lib/features/shell/presentation/gochano_shell.dart',
      ).readAsStringSync();

      final studentStart = content.indexOf(
        'List<_Destination> _buildDestinations',
      );
      final firstReturn = content.indexOf('\n      return [', studentStart);
      final generalStart = content.indexOf('\n    return [', firstReturn + 1);
      final studentSection = content.substring(studentStart, generalStart);

      final studentDestinations = RegExp(
        r"label:\s*GochanoLanguage\.text\('([^']+)'",
      ).allMatches(studentSection).map((m) => m.group(1)).toList();

      expect(
        studentDestinations,
        equals(['Today', 'Study', 'Commute', 'Money', 'Community']),
        reason:
            'The authenticated student shell must have strictly 5 bottom-navigation destinations',
      );
      expect(studentDestinations.length, equals(5));
    });

    test(
      'gochano_shell.dart includes universal quick add FAB for students',
      () {
        final content = File(
          'lib/features/shell/presentation/gochano_shell.dart',
        ).readAsStringSync();

        expect(
          content,
          contains("key: const ValueKey('universal_quick_add_fab')"),
        );
        expect(content, contains("heroTag: 'universal_quick_add_fab'"));
        expect(content, contains('showQuickAddSheet(context)'));
      },
    );
  });

  group('Universal Quick Add — Widget Presentation & Touch Targets', () {
    testWidgets('renders all 6 canonical action cards in English', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildTestWrapper(child: QuickAddSheet(onSelectAction: (_) {})),
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

      expect(find.text('Task'), findsOneWidget);
      expect(find.text('Assignment'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Medicine'), findsOneWidget);
      expect(find.text('Plan Trip'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
    });

    testWidgets('renders all 6 canonical action cards in Bengali', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildTestWrapper(child: QuickAddSheet(onSelectAction: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('কাজ'), findsOneWidget);
      expect(find.text('অ্যাসাইনমেন্ট'), findsOneWidget);
      expect(find.text('খরচ'), findsOneWidget);
      expect(find.text('ওষুধ'), findsOneWidget);
      expect(find.text('যাত্রা পরিকল্পনা'), findsOneWidget);
      expect(find.text('নোট'), findsOneWidget);

      GochanoLanguage.current.value = GochanoLocale.english;
    });

    testWidgets('all 6 action cards meet Android minimum 48dp touch target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWrapper(child: QuickAddSheet(onSelectAction: (_) {})),
      );
      await tester.pumpAndSettle();

      final keys = [
        'quick_add_task',
        'quick_add_assignment',
        'quick_add_expense',
        'quick_add_medicine',
        'quick_add_plan_trip',
        'quick_add_note',
      ];

      for (final key in keys) {
        final finder = find.byKey(ValueKey(key));
        final size = tester.getSize(finder);
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason: '$key height (${size.height}) is under 48dp minimum',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(48.0),
          reason: '$key width (${size.width}) is under 48dp minimum',
        );
      }
    });

    testWidgets('renders smoothly on 320dp narrow device without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWrapper(
          width: 320,
          child: QuickAddSheet(onSelectAction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_add_note')), findsOneWidget);
    });

    testWidgets('renders smoothly with 2.0x font scaling without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWrapper(
          width: 360,
          textScaleFactor: 2.0,
          child: QuickAddSheet(onSelectAction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'tapping each action invokes onSelectAction with canonical type',
      (tester) async {
        QuickActionType? selected;

        await tester.pumpWidget(
          _buildTestWrapper(
            child: QuickAddSheet(onSelectAction: (type) => selected = type),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('quick_add_task')));
        expect(selected, equals(QuickActionType.task));

        await tester.tap(find.byKey(const ValueKey('quick_add_assignment')));
        expect(selected, equals(QuickActionType.assignment));

        await tester.tap(find.byKey(const ValueKey('quick_add_expense')));
        expect(selected, equals(QuickActionType.expense));

        await tester.tap(find.byKey(const ValueKey('quick_add_medicine')));
        expect(selected, equals(QuickActionType.medicine));

        await tester.tap(find.byKey(const ValueKey('quick_add_plan_trip')));
        expect(selected, equals(QuickActionType.planTrip));

        await tester.tap(find.byKey(const ValueKey('quick_add_note')));
        expect(selected, equals(QuickActionType.note));
      },
    );
  });
}
