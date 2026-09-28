// Tests for Mode-Aware Today / Home Screen (Phase D).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/home/presentation/home_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String source;

  setUpAll(() {
    source = _read('lib/features/home/presentation/home_screen.dart');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('HomeScreen Source Verification (Phase D)', () {
    test('HomeScreen imports GochanoAppMode', () {
      expect(
        source,
        contains("import '../../../core/settings/gochano_app_mode.dart';"),
      );
    });

    test('HomeScreen reacts to GochanoAppModePreferences.current via builder', () {
      expect(
        source,
        contains('ValueListenableBuilder<GochanoAppMode>'),
      );
      expect(
        source,
        contains('valueListenable: GochanoAppModePreferences.current'),
      );
    });

    test('HomeScreen composes Study Mode cards: Tasks, StudyProgress, RecentMaterials', () {
      final studyIndex = source.indexOf('if (mode == GochanoAppMode.study)');
      expect(studyIndex, greaterThan(0));
      final studyBlock = source.substring(studyIndex, studyIndex + 500);

      expect(studyBlock, contains('_TodaysTasksCard'));
      expect(studyBlock, contains('_StudyProgressCard'));
      expect(studyBlock, contains('_RecentMaterialsCard'));
      expect(studyBlock, isNot(contains('_CommuteCard')));
      expect(studyBlock, isNot(contains('_MoneyCard')));
    });

    test('HomeScreen composes Utility Mode cards: Commute and Money (no Medicine or Tasks)', () {
      final utilityIndex = source.indexOf('// Utility Mode: Commute -> Money / Expense');
      expect(utilityIndex, greaterThan(0));
      final utilityBlock = source.substring(utilityIndex, utilityIndex + 500);

      expect(utilityBlock, contains('_CommuteCard'));
      expect(utilityBlock, contains('_MoneyCard'));
      expect(utilityBlock, isNot(contains('_MedicineScheduleCard')));
      expect(utilityBlock, isNot(contains('_TodaysTasksCard')));
      expect(utilityBlock, isNot(contains('_StudyProgressCard')));
      expect(utilityBlock, isNot(contains('_RecentMaterialsCard')));
    });

    test('Non-student role retains default cards in standard order', () {
      final nonStudentIndex = source.indexOf('if (!_isStudent)');
      expect(nonStudentIndex, greaterThan(0));
      final nonStudentBlock = source.substring(nonStudentIndex, nonStudentIndex + 600);

      final taskIdx = nonStudentBlock.indexOf('_TodaysTasksCard');
      final medIdx = nonStudentBlock.indexOf('_MedicineScheduleCard');
      final commuteIdx = nonStudentBlock.indexOf('_CommuteCard');
      final moneyIdx = nonStudentBlock.indexOf('_MoneyCard');

      expect(taskIdx, greaterThanOrEqualTo(0));
      expect(medIdx, greaterThan(taskIdx));
      expect(commuteIdx, greaterThan(medIdx));
      expect(moneyIdx, greaterThan(commuteIdx));
    });
  });

  group('HomeScreen Mode Cards Composition Unit Tests', () {
    testWidgets('study mode cards list contains task, study progress, and recent materials',
        (tester) async {
      int? navigatedDestination;
      final home = HomeScreen(
        role: 'student',
        displayName: 'Student User',
        onOpenDestination: (idx) => navigatedDestination = idx,
        onOpenProfile: () {},
      );

      final cards = cardsForMode(home, GochanoAppMode.study);
      // 7 elements: SyncStatusIndicator, SizedBox, _TodaysTasksCard, SizedBox, _StudyProgressCard, SizedBox, _RecentMaterialsCard
      expect(cards.length, equals(7));

      final typeNames = cards.map((w) => w.runtimeType.toString()).toList();
      expect(typeNames, contains('_TodaysTasksCard'));
      expect(typeNames, contains('_StudyProgressCard'));
      expect(typeNames, contains('_RecentMaterialsCard'));
      expect(typeNames, isNot(contains('_CommuteCard')));
      expect(typeNames, isNot(contains('_MoneyCard')));
    });

    testWidgets('utility mode cards list contains commute and money only (no medicine)',
        (tester) async {
      final home = HomeScreen(
        role: 'student',
        displayName: 'Student User',
        onOpenDestination: (_) {},
        onOpenProfile: () {},
      );

      final cards = cardsForMode(home, GochanoAppMode.utility);
      // 5 elements: SyncStatusIndicator, SizedBox, _CommuteCard, SizedBox, _MoneyCard
      expect(cards.length, equals(5));

      final typeNames = cards.map((w) => w.runtimeType.toString()).toList();
      expect(typeNames, contains('_CommuteCard'));
      expect(typeNames, contains('_MoneyCard'));
      expect(typeNames, isNot(contains('_MedicineScheduleCard')));
      expect(typeNames, isNot(contains('_TodaysTasksCard')));
      expect(typeNames, isNot(contains('_StudyProgressCard')));
      expect(typeNames, isNot(contains('_RecentMaterialsCard')));
    });

    testWidgets('non-student role cards contain task, medicine, commute, and money',
        (tester) async {
      final home = HomeScreen(
        role: 'teacher',
        displayName: 'Teacher User',
        onOpenDestination: (_) {},
        onOpenProfile: () {},
      );

      final cards = cardsForMode(home, GochanoAppMode.study);
      expect(cards.length, equals(9));

      final typeNames = cards.map((w) => w.runtimeType.toString()).toList();
      expect(typeNames, contains('_TodaysTasksCard'));
      expect(typeNames, contains('_MedicineScheduleCard'));
      expect(typeNames, contains('_CommuteCard'));
      expect(typeNames, contains('_MoneyCard'));
      expect(typeNames, isNot(contains('_StudyProgressCard')));
      expect(typeNames, isNot(contains('_RecentMaterialsCard')));
    });

    testWidgets('reactive switching from study to utility updates cards list immediately',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<GochanoAppMode>(
              valueListenable: GochanoAppModePreferences.current,
              builder: (context, mode, _) {
                const home = HomeScreen(
                  role: 'student',
                  displayName: 'Reactive User',
                  onOpenDestination: _dummyDestination,
                  onOpenProfile: _dummyProfile,
                );
                return ListView(
                  children: home.buildModeCards(context, mode),
                );
              },
            ),
          ),
        ),
      );

      // Initially study mode
      expect(GochanoAppModePreferences.current.value, GochanoAppMode.study);
      var currentCards = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_StudyProgressCard',
      );
      expect(currentCards, findsOneWidget);

      var commuteCards = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_CommuteCard',
      );
      expect(commuteCards, findsNothing);

      // Switch to utility mode
      GochanoAppModePreferences.current.value = GochanoAppMode.utility;
      await tester.pump();

      // Now utility mode
      currentCards = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_StudyProgressCard',
      );
      expect(currentCards, findsNothing);

      commuteCards = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_CommuteCard',
      );
      expect(commuteCards, findsOneWidget);
    });
  });
}

void _dummyDestination(int index) {}
void _dummyProfile() {}

List<Widget> cardsForMode(HomeScreen screen, GochanoAppMode mode) {
  late List<Widget> result;
  runApp(
    MaterialApp(
      home: Builder(
        builder: (ctx) {
          result = screen.buildModeCards(ctx, mode);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}
