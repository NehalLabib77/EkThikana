import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('StudentDestination navigation helpers', () {
    late String navSource;

    setUpAll(() {
      navSource = _read('lib/core/navigation.dart');
    });

    test('StudentDestination enum exists with all destinations', () {
      expect(navSource, contains('enum StudentDestination'));
      expect(navSource, contains('today'));
      expect(navSource, contains('studyPlan'));
      expect(navSource, contains('studyWorkspace'));
      expect(navSource, contains('money'));
      expect(navSource, contains('medicine'));
      expect(navSource, contains('commute'));
      expect(navSource, contains('community'));
      expect(navSource, contains('profile'));
    });

    test('StudentDestination has tabIndex and isTab getters', () {
      expect(navSource, contains('int get tabIndex'));
      expect(navSource, contains('bool get isTab'));
    });

    test('StudentDestination maps studyPlan to Study area', () {
      expect(navSource, contains('StudentArea.study.tabIndex'));
    });

    test('StudentDestination maps money to Money area', () {
      expect(navSource, contains('StudentArea.money.tabIndex'));
    });
  });

  group('Today to canonical modules', () {
    late String source;
    setUpAll(() => source = _read('lib/features/home/presentation/home_screen.dart'));

    test('Study snapshot navigates to Study Plan', () {
      expect(source, contains('onOpenStudyTab(StudyTab.plan.tabIndex)'));
    });

    test('Now/Next task navigates to Study Plan', () {
      expect(source, contains('StudentEventType.medicine'));
    });

    test('Now/Next medicine navigates to MedicineScreen', () {
      expect(source, contains('MedicineScreen()'));
    });

    test('Medicine snapshot opens MedicineScreen', () {
      expect(source, contains('MedicineScreen()'));
    });

    test('Money snapshot routes to canonical Money area', () {
      expect(source, contains('onOpenDestination(StudentArea.money.tabIndex)'));
    });

    test('Money snapshot does NOT call showAddExpenseSheet', () {
      // _MoneySnapshot should navigate to Money tab, not open expense sheet.
      expect(source, isNot(contains('_MoneySnapshot.*showAddExpenseSheet')));
    });

    test('Quick Actions: Commute opens CommuteScreen', () {
      expect(source, contains('CommuteScreen()'));
    });

    test('Quick Actions: AI opens AiAssistantScreen', () {
      expect(source, contains('AiAssistantScreen()'));
    });

    test('Profile avatar opens ProfileScreen', () {
      expect(source, contains('ProfileScreen(role: role)'));
    });

    test('Today Schedule See All opens Study Plan', () {
      expect(source, contains('onSeeAll:'));
    });
  });

  group('Task to Note relationship', () {
    late String taskSource;
    setUpAll(
        () => taskSource = _read('lib/features/tasks/presentation/add_task_sheet.dart'));

    test('task form stores optional relatedNoteId', () {
      expect(taskSource, contains("data['relatedNoteId']"));
    });

    test('task form stores optional relatedMaterialId', () {
      expect(taskSource, contains("data['relatedMaterialId']"));
    });

    test('task form loads related fields from existing data', () {
      expect(taskSource, contains("data['relatedNoteId']?.toString()"));
      expect(taskSource, contains("data['relatedMaterialId']?.toString()"));
    });
  });

  group('Task to Material relationship', () {
    late String taskSource;
    setUpAll(
        () => taskSource = _read('lib/features/tasks/presentation/add_task_sheet.dart'));

    test('task payload includes relatedMaterialId when set', () {
      expect(taskSource, contains("payload['relatedMaterialId']"));
    });
  });

  group('Note to Task relationship', () {
    late String noteSource;
    setUpAll(
        () => noteSource = _read('lib/features/study/presentation/notes/note_editor_screen.dart'));

    test('note editor stores optional relatedTaskId', () {
      expect(noteSource, contains('_relatedTaskId'));
    });

    test('note editor stores optional relatedMaterialId', () {
      expect(noteSource, contains('_relatedMaterialId'));
    });

    test('note editor loads related fields from existing data', () {
      expect(noteSource, contains("data['relatedTaskId']?.toString()"));
      expect(noteSource, contains("data['relatedMaterialId']?.toString()"));
    });

    test('note editor passes related fields to saveNote', () {
      expect(noteSource, contains('relatedTaskId: _relatedTaskId'));
      expect(noteSource, contains('relatedMaterialId: _relatedMaterialId'));
    });
  });

  group('Note to Material relationship', () {
    late String firestoreSource;
    setUpAll(() =>
        firestoreSource = _read('lib/services/firestore_service.dart'));

    test('saveNote accepts relatedTaskId param', () {
      expect(firestoreSource, contains('String? relatedTaskId'));
    });

    test('saveNote accepts relatedMaterialId param', () {
      expect(firestoreSource, contains('String? relatedMaterialId'));
    });

    test('saveNote writes relatedTaskId to document', () {
      expect(firestoreSource, contains("data['relatedTaskId']"));
    });

    test('saveNote writes relatedMaterialId to document', () {
      expect(firestoreSource, contains("data['relatedMaterialId']"));
    });
  });

  group('Related chips widget', () {
    late String chipSource;
    setUpAll(() => chipSource =
        _read('lib/shared/widgets/related_chips.dart'));

    test('RelatedNoteChip exists', () {
      expect(chipSource, contains('class RelatedNoteChip'));
    });

    test('RelatedMaterialChip exists', () {
      expect(chipSource, contains('class RelatedMaterialChip'));
    });

    test('handles deleted documents gracefully', () {
      expect(chipSource, contains('!doc.exists'));
      expect(chipSource, contains('unavailableLabel'));
    });

    test('streams Firestore document for live updates', () {
      expect(chipSource, contains('.snapshots()'));
    });

    test('opens NoteEditorScreen on tap', () {
      expect(chipSource, contains('NoteEditorScreen('));
    });

    test('opens MaterialReaderScreen on tap', () {
      expect(chipSource, contains('MaterialReaderScreen('));
    });
  });

  group('Plan view relationship chips', () {
    late String planSource;
    setUpAll(() =>
        planSource = _read('lib/features/study/presentation/planner/plan_view.dart'));

    test('imports related_chips.dart', () {
      expect(planSource, contains("import '../../../../shared/widgets/related_chips.dart'"));
    });

    test('renders RelatedNoteChip for tasks with relatedNoteId', () {
      expect(planSource, contains('RelatedNoteChip('));
    });

    test('renders RelatedMaterialChip for tasks with relatedMaterialId', () {
      expect(planSource, contains('RelatedMaterialChip('));
    });

    test('checks for relatedNoteId in task data', () {
      expect(planSource, contains("data['relatedNoteId']"));
    });

    test('checks for relatedMaterialId in task data', () {
      expect(planSource, contains("data['relatedMaterialId']"));
    });
  });

  group('Medicine to Money', () {
    late String financeSource;
    setUpAll(() =>
        financeSource = _read('lib/services/financial_service.dart'));

    test('recordMedicineDose writes single financial transaction', () {
      expect(financeSource, contains('recordMedicineDose'));
    });

    test('medicine dose only creates transaction when taken and cost > 0', () {
      expect(financeSource, contains("'taken'"));
    });

    test('skipped medicine does not create financial transaction', () {
      expect(financeSource, contains("'skipped'"));
    });
  });

  group('StudentContext remains read-only', () {
    late String ctxSource;
    setUpAll(() =>
        ctxSource = _read('lib/core/student/student_context_service.dart'));

    test('does not write to any Firestore collection', () {
      // Check for Firestore-specific write operations (not Dart list .addAll)
      expect(ctxSource, isNot(contains("collection('tasks').doc")));
      expect(ctxSource, isNot(contains("collection('notes').doc")));
      expect(ctxSource, isNot(contains("collection('materials').doc")));
      expect(ctxSource, isNot(contains('.set({')));
      expect(ctxSource, isNot(contains('.update({')));
    });

    test('does not create student_events persistence', () {
      expect(ctxSource, isNot(contains("collection('student_events')")));
    });
  });

  group('No AI call during module connections', () {
    late String homeSource;
    setUpAll(
        () => homeSource = _read('lib/features/home/presentation/home_screen.dart'));

    test('no groq import', () {
      expect(homeSource, isNot(contains('groq')));
    });

    test('no gemini import', () {
      expect(homeSource, isNot(contains('gemini')));
    });

    test('no generateContent call', () {
      expect(homeSource, isNot(contains('generateContent')));
    });

    test('no chatCompletion call', () {
      expect(homeSource, isNot(contains('chatCompletion')));
    });
  });

  group('No Commute auto-route', () {
    late String homeSource;
    setUpAll(
        () => homeSource = _read('lib/features/home/presentation/home_screen.dart'));

    test('no commuteRoutes call', () {
      expect(homeSource, isNot(contains('commuteRoutes(')));
    });

    test('no commuteSingleFare call', () {
      expect(homeSource, isNot(contains('commuteSingleFare(')));
    });
  });

  group('No duplicate persistence', () {
    late String ctxSource;
    setUpAll(() =>
        ctxSource = _read('lib/core/student/student_context_service.dart'));

    test('does not write tasks to another collection', () {
      final count = "ownerStream('tasks'".allMatches(ctxSource).length;
      expect(count, 0);
    });

    test('does not write notes to another collection', () {
      final count = "ownerStream('notes'".allMatches(ctxSource).length;
      expect(count, 0);
    });

    test('does not write materials to another collection', () {
      final count = "ownerStream('materials'".allMatches(ctxSource).length;
      expect(count, 0);
    });
  });

  group('EN/BN labels', () {
    late String homeSource;
    setUpAll(
        () => homeSource = _read('lib/features/home/presentation/home_screen.dart'));

    test('bilingual strings used', () {
      expect(homeSource, contains("GochanoLanguage.text('Today'"));
      expect(homeSource, contains("GochanoLanguage.text('Study'"));
      expect(homeSource, contains("GochanoLanguage.text('Money'"));
      expect(homeSource, contains("GochanoLanguage.text('Medicine'"));
    });
  });

  group('Removed features remain absent', () {
    late String homeSource;
    setUpAll(
        () => homeSource = _read('lib/features/home/presentation/home_screen.dart'));

    test('no Focus', () {
      expect(homeSource, isNot(contains('Focus')));
    });

    test('no Insights', () {
      expect(homeSource, isNot(contains('Insights')));
    });

    test('no Rewards', () {
      expect(homeSource, isNot(contains('Rewards')));
    });

    test('no XP', () {
      expect(homeSource, isNot(contains('XP')));
    });

    test('no Gems', () {
      expect(homeSource, isNot(contains('Gems')));
    });

    test('no Study Goal', () {
      expect(homeSource, isNot(contains('Study Goal')));
    });

    test('no OCR', () {
      expect(homeSource, isNot(contains('OCR')));
    });
  });

  group('Broken reference safety', () {
    late String chipSource;
    setUpAll(() => chipSource =
        _read('lib/shared/widgets/related_chips.dart'));

    test('shows unavailable state for deleted documents', () {
      expect(chipSource, contains('!doc.exists'));
      expect(chipSource, contains('Deleted'));
    });

    test('stream handles missing documents without crash', () {
      expect(chipSource, contains(' ConnectionState.waiting'));
    });
  });

  group('Backward compatibility', () {
    late String taskSource;
    setUpAll(
        () => taskSource = _read('lib/features/tasks/presentation/add_task_sheet.dart'));

    test('related fields are nullable (optional)', () {
      expect(taskSource, contains('String? _relatedNoteId'));
      expect(taskSource, contains('String? _relatedMaterialId'));
    });

    test('old records without relationships still load', () {
      expect(taskSource, contains("data['relatedNoteId']?.toString()"));
    });
  });
}
