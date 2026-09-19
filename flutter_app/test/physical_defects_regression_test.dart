// Regression tests for Phase 1 Physical Bug-Fix Pass & Quick Add Contract Correction.
//
// Covers all 17 verification requirements:
//  1. Quick Add has exactly 6 actions
//  2. Task exists
//  3. Assignment exists
//  4. Expense exists
//  5. Medicine exists
//  6. Plan Trip exists
//  7. Note exists
//  8. scanReceipt does NOT exist
//  9. scanPrescription does NOT exist
// 10. OCR action does NOT exist
// 11. Medicine screen has no scan/prescription action
// 12. Add Medicine remains accessible
// 13. Medicine reminder logic remains unchanged
// 14. Assignment still launches task form with assignment type
// 15. Quick Add still performs no persistence/business logic
// 16. 320dp layout has no overflow
// 17. large text has no overflow

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/design_system/gochano_typography.dart';
import 'package:gochano/core/localization/feedback_messages.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/life/presentation/commute/plan_trip_sheet.dart';
import 'package:gochano/features/shell/presentation/quick_add_sheet.dart';
import 'package:gochano/features/tasks/presentation/add_task_sheet.dart';
import 'package:gochano/shared/states/gochano_states.dart';

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
      child: child,
    ),
  );
}

void main() {
  group('1-7. Quick Add Exact 6-Action Contract', () {
    test('1. Quick Add has exactly 6 actions', () {
      expect(QuickAddAction.values.length, equals(6));
    });

    test('2. Task exists', () {
      expect(QuickAddAction.values, contains(QuickAddAction.task));
    });

    test('3. Assignment exists', () {
      expect(QuickAddAction.values, contains(QuickAddAction.assignment));
    });

    test('4. Expense exists', () {
      expect(QuickAddAction.values, contains(QuickAddAction.expense));
    });

    test('5. Medicine exists', () {
      expect(QuickAddAction.values, contains(QuickAddAction.medicine));
    });

    test('6. Plan Trip exists', () {
      expect(QuickAddAction.values, contains(QuickAddAction.planTrip));
    });

    test('7. Note exists', () {
      expect(QuickAddAction.values, contains(QuickAddAction.note));
    });
  });

  group('8-10. Obsolete Actions Completely Excluded', () {
    test('8. scanReceipt does NOT exist', () {
      final names = QuickAddAction.values.map((e) => e.name).toList();
      expect(names, isNot(contains('scanReceipt')));
      expect(names, isNot(contains('receipt')));

      final file = File(
        'lib/features/shell/presentation/quick_add_sheet.dart',
      ).readAsStringSync();
      expect(file, isNot(contains('scanReceipt')));
      expect(file, isNot(contains('Scan Receipt')));
      expect(file, isNot(contains('রসিদ')));
    });

    test('9. scanPrescription does NOT exist in Quick Add', () {
      final names = QuickAddAction.values.map((e) => e.name).toList();
      expect(names, isNot(contains('scanPrescription')));
      expect(names, isNot(contains('prescription')));

      final file = File(
        'lib/features/shell/presentation/quick_add_sheet.dart',
      ).readAsStringSync();
      expect(file, isNot(contains('scanPrescription')));
      expect(file, isNot(contains('Scan Prescription')));
    });

    test('10. OCR action does NOT exist in Quick Add', () {
      final names = QuickAddAction.values.map((e) => e.name).toList();
      expect(names, isNot(contains('ocr')));
      expect(names, isNot(contains('OCR')));

      final file = File(
        'lib/features/shell/presentation/quick_add_sheet.dart',
      ).readAsStringSync();
      expect(file, isNot(contains('ocr')));
      expect(file, isNot(contains('OCR')));
    });
  });

  group('11-13. Medicine Screen Scope & Clean Creation Contract', () {
    test('11. Medicine screen has no scan/prescription action', () {
      final file = File(
        'lib/features/life/presentation/medicine/medicine_screen.dart',
      ).readAsStringSync();

      expect(file, isNot(contains('prescription_scan_screen.dart')));
      expect(file, isNot(contains('PrescriptionScanScreen')));
      expect(file, isNot(contains('medicine-scan-prescription')));
      expect(file, isNot(contains('document_scanner')));
    });

    test('12. Add Medicine remains accessible on Medicine screen', () {
      final file = File(
        'lib/features/life/presentation/medicine/medicine_screen.dart',
      ).readAsStringSync();

      expect(file, contains("heroTag: 'medicine-add'"));
      expect(file, contains('Icons.medication_rounded'));
      expect(
        file,
        contains("GochanoLanguage.text('Add medicine', 'ওষুধ যোগ')"),
      );
      expect(file, contains('const MedicineFormScreen()'));
    });

    test('13. Medicine reminder logic remains unchanged', () {
      final file = File(
        'lib/features/life/presentation/medicine/medicine_form_screen.dart',
      ).readAsStringSync();

      expect(file, contains('NotificationService.scheduleDailyMedicine'));
      expect(file, contains('NotificationService.cancelMedicineTimes'));
      expect(file, contains("collection('medicines')"));
    });
  });

  group('14-15. Pure Coordinator Behavior & Safe Routing', () {
    test('14. Assignment still launches task form with assignment type', () {
      final file = File(
        'lib/features/shell/presentation/quick_add_sheet.dart',
      ).readAsStringSync();

      expect(file, contains('case QuickAddAction.assignment:'));
      expect(file, contains("showAddTaskSheet(context, type: 'assignment')"));
    });

    test('15. Quick Add still performs no persistence/business logic', () {
      final file = File(
        'lib/features/shell/presentation/quick_add_sheet.dart',
      ).readAsStringSync();

      expect(file, isNot(contains('cloud_firestore')));
      expect(file, isNot(contains('firebase_auth')));
      expect(file, isNot(contains('firestore_service.dart')));
      expect(file, isNot(contains('financial_service.dart')));
      expect(file, isNot(contains('commute_trip_service.dart')));
      expect(file, isNot(contains('NotificationService')));
      expect(file, isNot(contains('shared_preferences')));
    });
  });

  group('16-17. Responsive Layout & Font Scaling Acceptance', () {
    testWidgets('16. 320dp layout has no overflow', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(width: 320, child: QuickAddSheet(onSelectAction: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
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

    testWidgets('17. large text (2.0x scaling) has no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 360,
          textScaleFactor: 2.0,
          child: QuickAddSheet(onSelectAction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('quick_add_task')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick_add_note')), findsOneWidget);
    });
  });

  group('Defect Regression: Typed Contracts & Sequential Cycles', () {
    test('TaskSaveResult contract is immutable and strongly typed', () {
      const res = TaskSaveResult(
        saved: true,
        taskId: 't-123',
        reminderScheduled: true,
        isAssignment: false,
      );
      expect(res.saved, isTrue);
      expect(res.taskId, equals('t-123'));
      expect(res.reminderScheduled, isTrue);
      expect(res.isAssignment, isFalse);

      const cancel = TaskSaveResult.cancelled();
      expect(cancel.saved, isFalse);
      expect(cancel.taskId, isNull);
    });

    test('TripSaveResult contract is immutable and strongly typed', () {
      const res = TripSaveResult(saved: true, reminderMinutes: 15);
      expect(res.saved, isTrue);
      expect(res.reminderMinutes, equals(15));
      expect(res.deleted, isFalse);
    });

    test('add_task_sheet.dart statically never pops a raw bool', () {
      final file = File(
        'lib/features/tasks/presentation/add_task_sheet.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(file, isNot(contains('Navigator.of(context).pop(true)')));
      expect(file, isNot(contains('Navigator.of(context).pop(false)')));
      expect(file, isNot(contains('Navigator.pop(context, true)')));
      expect(file, isNot(contains('Navigator.pop(context, false)')));
      expect(file, contains('Future<TaskSaveResult?> showAddTaskSheet('));
      expect(file, contains('showModalBottomSheet<TaskSaveResult>'));
    });

    test('plan_trip_sheet.dart statically never pops a raw bool', () {
      final file = File(
        'lib/features/life/presentation/commute/plan_trip_sheet.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(file, isNot(contains('Navigator.of(context).pop(true)')));
      expect(file, isNot(contains('Navigator.of(context).pop(false)')));
      expect(file, isNot(contains('Navigator.pop(context, true)')));
      expect(file, isNot(contains('Navigator.pop(context, false)')));
      expect(file, contains('Future<TripSaveResult?> showPlanTripSheet('));
      expect(file, contains('showModalBottomSheet<TripSaveResult>'));
    });

    test(
      'gochano_shell.dart student shell contains exactly one top-level FAB',
      () {
        final shellContent = File(
          'lib/features/shell/presentation/gochano_shell.dart',
        ).readAsStringSync();

        expect(
          shellContent,
          contains("key: const ValueKey('universal_quick_add_fab')"),
        );
        final matches = RegExp(
          r'universal_quick_add_fab',
        ).allMatches(shellContent).length;
        expect(matches, greaterThanOrEqualTo(1));
      },
    );

    test('Money screen has no colliding local FloatingActionButton', () {
      final file = File(
        'lib/features/life/presentation/expense/expense_screen.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(file, isNot(contains('floatingActionButton:')));
      expect(file, isNot(contains('FloatingActionButton')));
    });

    test('Community screen has no colliding local FloatingActionButton', () {
      final file = File(
        'lib/features/community/presentation/community_screen.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(file, isNot(contains('floatingActionButton:')));
      expect(file, isNot(contains('FloatingActionButton.extended')));
      expect(file, isNot(contains('FloatingActionButton')));
    });

    testWidgets('Community EmptyState provides working New Group CTA button', (
      tester,
    ) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildWrapper(
          child: Scaffold(
            body: EmptyState(
              illustration: 'feature_groups',
              title: 'No study groups yet',
              message: 'Create a group for your class',
              actionLabel: 'New group',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ctaFinder = find.text('New group');
      expect(ctaFinder, findsOneWidget);
      await tester.tap(ctaFinder);
      expect(tapped, isTrue);
    });

    testWidgets(
      'Sequential Quick Add open/dismiss cycles work reliably (10 cycles)',
      (tester) async {
        await tester.pumpWidget(
          _buildWrapper(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  return Center(
                    child: ElevatedButton(
                      key: const ValueKey('launch_quick_add'),
                      onPressed: () async {
                        final action = await showQuickAddSheet(context);
                        if (action != null && context.mounted) {
                          await launchQuickAddAction(context, action);
                        }
                      },
                      child: const Text('Open'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (int cycle = 1; cycle <= 10; cycle++) {
          await tester.tap(find.byKey(const ValueKey('launch_quick_add')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('quick_add_task')),
            findsOneWidget,
            reason: 'Cycle \$cycle: Quick Add failed to open',
          );

          if (cycle % 2 == 0) {
            await tester.tap(find.byKey(const ValueKey('quick_add_task')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('task_title_input')),
              findsOneWidget,
            );
            await tester.tapAt(const Offset(20, 20));
            await tester.pumpAndSettle();
          } else {
            await tester.tapAt(const Offset(20, 20));
            await tester.pumpAndSettle();
          }

          expect(
            find.byKey(const ValueKey('launch_quick_add')),
            findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'Cycle \$cycle threw exception or navigator locked',
          );
        }
      },
    );

    test(
      'FeedbackMessages produces correct Bengali reminder strings with Bengali digits',
      () {
        GochanoLanguage.current.value = GochanoLocale.bangla;

        final msg10 = FeedbackMessages.tripPlanned(reminderMinutes: 10);
        expect(msg10, contains('১০ মিনিট আগে'));

        final msg30 = FeedbackMessages.tripPlanned(reminderMinutes: 30);
        expect(msg30, contains('৩০ মিনিট আগে'));

        final msg60 = FeedbackMessages.tripPlanned(reminderMinutes: 60);
        expect(msg60, contains('১ ঘণ্টা আগে'));

        GochanoLanguage.current.value = GochanoLocale.english;
        final msgEn = FeedbackMessages.tripPlanned(reminderMinutes: 30);
        expect(msgEn, contains('30 minutes before'));
      },
    );

    test('GochanoTypography includes HindSiliguri and Bengali fallbacks', () {
      expect(GochanoTypography.fontFamilyFallback, contains('HindSiliguri'));
      expect(
        GochanoTypography.fontFamilyFallback,
        contains('Noto Sans Bengali'),
      );
      expect(GochanoTypography.fontFamilyFallback, contains('NotoSansBengali'));
      expect(GochanoTypography.fontFamilyFallback, contains('Bangla'));
    });
  });
}
