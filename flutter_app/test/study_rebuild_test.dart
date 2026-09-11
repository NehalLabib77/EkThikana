import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String study;
  late String workspace;
  late String plan;
  late String taskForm;

  setUpAll(() {
    study = _read('lib/features/study/presentation/study_screen.dart');
    workspace = _read(
      'lib/features/study/presentation/workspace/workspace_view.dart',
    );
    plan = _read('lib/features/study/presentation/planner/plan_view.dart');
    taskForm = _read('lib/features/tasks/presentation/add_task_sheet.dart');
  });

  test('Study root exposes exactly Workspace and Plan tabs', () {
    expect(study, contains('TabController(length: 2'));
    expect(study, contains("'Workspace'"));
    expect(study, contains("'Plan'"));
    expect(study, isNot(contains('FocusView')));
    expect(study, isNot(contains('DistractionView')));
    expect(study, isNot(contains("'Focus'")));
    expect(study, isNot(contains("'Distraction'")));
  });

  test('Workspace Quick Access includes all required destinations', () {
    for (final label in const [
      'AI Assistant',
      'Notes',
      'PDFs',
      'Saved Images',
      'Docs',
      'Semester',
      'Shared Box',
    ]) {
      expect(workspace, contains("'$label'"));
    }
    expect(workspace, contains('constraints.maxWidth < 360 ? 3 : 4'));
    expect(workspace, contains('SavedMaterialsScreen'));
    expect(workspace, isNot(contains('_collapsedCount')));
  });

  test('DOCX reader path preserves the original file name', () {
    expect(workspace, contains('fileName: doc.data()[\'fileName\']'));
    expect(workspace, contains('MaterialReaderScreen'));
  });

  test('Plan uses one reactive Task and Assignment source', () {
    expect(plan, contains("ownerStream('tasks'"));
    expect(plan, contains("data['type']?.toString() == 'assignment'"));
    expect(plan, contains("type: 'task'"));
    expect(plan, contains("type: 'assignment'"));
    expect(plan, contains('initialDate: selectedDay'));
    expect(plan, contains('No tasks or assignments for this day.'));
  });

  test('History visibility is based on completed records across all dates', () {
    expect(plan, contains('class _HistoryEntry'));
    expect(plan, contains("data()['done'] == true"));
    expect(plan, contains('_PlanHistoryScreen'));
    expect(plan, contains('Mark not done'));
  });

  test('editing an existing assignment preserves its type', () {
    expect(taskForm, contains("existing?.data()?['type']?.toString()"));
    expect(taskForm, contains("resolvedType = existingType == 'assignment'"));
  });

  test('removed Study navigation has no OCR entry point', () {
    expect(study, isNot(contains('PrescriptionScan')));
    expect(workspace, isNot(contains('PrescriptionScan')));
  });
}
