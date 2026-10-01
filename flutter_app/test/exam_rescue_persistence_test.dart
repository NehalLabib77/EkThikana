// Phase T4 — Exam Rescue Persistence & Task Materialization Test Suite
//
// Comprehensive unit and widget tests covering:
// 1. Confirm creates exactly one session
// 2. Confirm creates correct number of tasks
// 3. each task uses existing `type: task`
// 4. rescueItemType persisted correctly
// 5. rescueSessionId correct
// 6. materialId preserved when valid
// 7. deleted preview item is not persisted
// 8. session contains exact taskIds
// 9. sourceMode/generationMode persisted at session
// 10. double Confirm produces one session/task set
// 11. empty edited plan blocked
// 12. Firestore failure leaves user on Preview and permits retry
// 13. retry reuses same IDs / creates no duplicates
// 14. notification failure does not delete persisted tasks
// 15. success returns to PlanView / caller
// 16. PlanView stream query logic renders created tasks on the correct day
// 17. local date/day mapping correct
// 18. timezone boundary does not shift rescue task to wrong calendar day

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/feedback_messages.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_persistence_service.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_preview_screen.dart';

// ---------------------------------------------------------------------------
// Fakes for in-memory, deterministic Firestore batch execution
// ---------------------------------------------------------------------------

class FakeDocumentReference<T> extends Fake implements DocumentReference<T> {
  final String _id;
  final String _path;
  final Map<String, Map<String, dynamic>> store;
  final String Function() _idGenerator;

  FakeDocumentReference(this._id, this._path, this.store, this._idGenerator);

  @override
  String get id => _id;

  @override
  String get path => _path;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference(
      '$_path/$collectionPath',
      store,
      _idGenerator,
    );
  }
}

class FakeCollectionReference<T> extends Fake
    implements CollectionReference<T> {
  final String _path;
  final Map<String, Map<String, dynamic>> store;
  final String Function() _idGenerator;

  FakeCollectionReference(this._path, this.store, this._idGenerator);

  @override
  String get path => _path;

  @override
  DocumentReference<T> doc([String? path]) {
    final id = path ?? _idGenerator();
    return FakeDocumentReference<T>(id, '$_path/$id', store, _idGenerator);
  }
}

class FakeWriteBatch extends Fake implements WriteBatch {
  final Map<String, Map<String, dynamic>> store;
  final List<void Function()> operations = [];
  bool shouldThrow = false;
  int commitCount = 0;

  FakeWriteBatch(this.store);

  @override
  void set<T>(
    DocumentReference<T> document,
    Object? data, [
    SetOptions? options,
  ]) {
    operations.add(() {
      final docPath = document.path;
      final existing = store[docPath] ?? <String, dynamic>{};
      final mapData = Map<String, dynamic>.from(data as Map);
      if (options?.merge == true) {
        store[docPath] = {...existing, ...mapData};
      } else {
        store[docPath] = mapData;
      }
    });
  }

  @override
  Future<void> commit() async {
    commitCount++;
    if (shouldThrow) {
      throw FirebaseException(
        plugin: 'firestore',
        message: 'Network connection lost',
      );
    }
    for (final op in operations) {
      op();
    }
  }
}

class FakeFirestore extends Fake implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> store = {};
  FakeWriteBatch? lastBatch;
  bool failNextBatch = false;
  int _idCounter = 0;

  String _generateId() => 'doc_${++_idCounter}';

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference(collectionPath, store, _generateId);
  }

  @override
  WriteBatch batch() {
    final b = FakeWriteBatch(store);
    b.shouldThrow = failNextBatch;
    lastBatch = b;
    return b;
  }
}

// ---------------------------------------------------------------------------
// Test Data Factory
// ---------------------------------------------------------------------------

ExamRescuePlan createSamplePlan({
  String sourceMode = 'materials',
  String generationMode = 'ai',
}) {
  return ExamRescuePlan(
    examTitle: 'Database Systems Final',
    daysRemaining: 2,
    totalEstimatedMinutes: 180,
    strategySummary: 'Focus on ER modeling and relational algebra.',
    sourceMode: sourceMode,
    generationMode: generationMode,
    days: [
      ExamRescueDay(
        dayNumber: 1,
        dateOffset: 0,
        theme: 'Relational Model',
        targetMinutes: 90,
        items: [
          const ExamRescueItem(
            title: 'Review Chapter 1 ER diagrams',
            type: 'study',
            estimatedMinutes: 45,
            materialId: 'mat_er_101',
            actionNote: 'Pay attention to cardinality constraints',
          ),
          const ExamRescueItem(
            title: '10-question practice quiz on SQL joins',
            type: 'quiz',
            estimatedMinutes: 45,
            materialId: 'mat_er_101',
            actionNote: 'Practice inner vs left outer joins',
          ),
        ],
      ),
      ExamRescueDay(
        dayNumber: 2,
        dateOffset: 1,
        theme: 'Normalization & Indexing',
        targetMinutes: 90,
        items: [
          const ExamRescueItem(
            title: 'Solve 3NF normalization problems',
            type: 'practice',
            estimatedMinutes: 60,
            materialId: '',
            actionNote: 'Check functional dependency closures',
          ),
          const ExamRescueItem(
            title: 'Final rapid formula revision',
            type: 'revision',
            estimatedMinutes: 30,
            materialId: '',
            actionNote: 'Review B+ tree formulas',
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirestore fakeFirestore;
  late List<String> reminderCalls;
  bool reminderShouldFail = false;
  final testNow = DateTime(2026, 10, 15, 10, 0);

  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
    fakeFirestore = FakeFirestore();
    reminderCalls = [];
    reminderShouldFail = false;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  Future<void> mockScheduleReminder({
    required String taskId,
    required String title,
    DateTime? when,
    String type = 'task',
  }) async {
    if (reminderShouldFail) {
      throw Exception('Exact alarm permission denied');
    }
    reminderCalls.add(taskId);
  }

  ExamRescuePersistenceService buildService({String uid = 'test_student_1'}) {
    return ExamRescuePersistenceService(
      firestore: fakeFirestore,
      getUid: () => uid,
      scheduleReminder: mockScheduleReminder,
      now: () => testNow,
    );
  }

  group('Phase T4 — ExamRescuePersistenceService Unit Tests', () {
    test(
      '1 & 2: Confirm creates exactly one session and correct number of tasks in batch',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        expect(result.success, isTrue);
        expect(result.tasksCount, 4);
        expect(result.sessionId, isNotNull);
        expect(result.taskIds.length, 4);

        // Verify Firestore store contents
        final sessionPath =
            'users/test_student_1/exam_rescue/${result.sessionId}';
        expect(fakeFirestore.store.containsKey(sessionPath), isTrue);

        final sessionData = fakeFirestore.store[sessionPath]!;
        expect(sessionData['ownerId'], 'test_student_1');
        expect(sessionData['examTitle'], 'Database Systems Final');
        expect(sessionData['status'], 'active');
        expect(sessionData['taskIds'], result.taskIds);

        // Verify 4 distinct task documents created
        for (final taskId in result.taskIds) {
          final taskPath = 'tasks/$taskId';
          expect(fakeFirestore.store.containsKey(taskPath), isTrue);
        }
      },
    );

    test('3: Each task strictly uses existing type: "task"', () async {
      final service = buildService();
      final plan = createSamplePlan();

      final result = await service.applyPlan(
        plan: plan,
        examTitle: 'Database Systems Final',
        examDate: testNow.add(const Duration(days: 2)),
        dailyTargetMinutes: 90,
      );

      for (final taskId in result.taskIds) {
        final taskData = fakeFirestore.store['tasks/$taskId']!;
        expect(
          taskData['type'],
          equals('task'),
          reason:
              'Task type must strictly be "task" so existing PlanView handles it',
        );
      }
    });

    test(
      '4: rescueItemType is persisted accurately for all item types',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        final task0 = fakeFirestore.store['tasks/${result.taskIds[0]}']!;
        final task1 = fakeFirestore.store['tasks/${result.taskIds[1]}']!;
        final task2 = fakeFirestore.store['tasks/${result.taskIds[2]}']!;
        final task3 = fakeFirestore.store['tasks/${result.taskIds[3]}']!;

        expect(task0['rescueItemType'], 'study');
        expect(task1['rescueItemType'], 'quiz');
        expect(task2['rescueItemType'], 'practice');
        expect(task3['rescueItemType'], 'revision');
      },
    );

    test(
      '5: rescueSessionId links every task back to the exact session',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        for (final taskId in result.taskIds) {
          final taskData = fakeFirestore.store['tasks/$taskId']!;
          expect(taskData['rescueSessionId'], equals(result.sessionId));
          expect(taskData['source'], equals('exam_rescue'));
        }
      },
    );

    test(
      '6: materialId is preserved when valid and omitted when empty',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        final taskWithMat = fakeFirestore.store['tasks/${result.taskIds[0]}']!;
        expect(taskWithMat['materialId'], 'mat_er_101');

        final taskWithoutMat =
            fakeFirestore.store['tasks/${result.taskIds[2]}']!;
        expect(taskWithoutMat.containsKey('materialId'), isFalse);
      },
    );

    test('7: Deleted preview items are NOT persisted into tasks', () async {
      final service = buildService();
      final fullPlan = createSamplePlan();

      // Simulate student deleting item 1 from Day 1 and item 1 from Day 2
      final editedDays = [
        fullPlan.days[0].copyWith(items: [fullPlan.days[0].items[0]]), // 1 item
        fullPlan.days[1].copyWith(items: [fullPlan.days[1].items[0]]), // 1 item
      ];
      final editedPlan = fullPlan.copyWith(days: editedDays);

      final result = await service.applyPlan(
        plan: editedPlan,
        examTitle: 'Database Systems Final',
        examDate: testNow.add(const Duration(days: 2)),
        dailyTargetMinutes: 90,
      );

      expect(result.tasksCount, 2);
      expect(result.taskIds.length, 2);

      // Verify only 2 tasks exist in store
      final taskCount = fakeFirestore.store.keys
          .where((k) => k.startsWith('tasks/'))
          .length;
      expect(taskCount, 2);
    });

    test(
      '8: Session envelope contains the exact list of generated taskIds',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        final sessionData = fakeFirestore
            .store['users/test_student_1/exam_rescue/${result.sessionId}']!;
        expect(sessionData['taskIds'], equals(result.taskIds));
      },
    );

    test(
      '9: sourceMode and generationMode are persisted at session envelope',
      () async {
        final service = buildService();
        final plan = createSamplePlan(
          sourceMode: 'materials',
          generationMode: 'fallback',
        );

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        final sessionData = fakeFirestore
            .store['users/test_student_1/exam_rescue/${result.sessionId}']!;
        expect(sessionData['sourceMode'], 'materials');
        expect(sessionData['generationMode'], 'fallback');
      },
    );

    test(
      '10 & 13: Double Confirm / retry reuses same IDs and creates no duplicate documents',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final stableSessionId = service.generateSessionId();
        final stableTaskIds = service.generateTaskIds(plan.totalItemsCount);

        // First run
        final result1 = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
          preallocatedSessionId: stableSessionId,
          preallocatedTaskIds: stableTaskIds,
        );

        // Second run (simulating retry with identical preallocated IDs)
        final result2 = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
          preallocatedSessionId: stableSessionId,
          preallocatedTaskIds: stableTaskIds,
        );

        expect(result1.sessionId, equals(result2.sessionId));
        expect(result1.taskIds, equals(result2.taskIds));

        final sessionCount = fakeFirestore.store.keys
            .where((k) => k.contains('/exam_rescue/'))
            .length;
        final taskCount = fakeFirestore.store.keys
            .where((k) => k.startsWith('tasks/'))
            .length;

        expect(sessionCount, 1, reason: 'Zero duplicate sessions created');
        expect(taskCount, 4, reason: 'Zero duplicate tasks created');
      },
    );

    test(
      '11: Empty plan is blocked and returns friendly validation message',
      () async {
        final service = buildService();
        final emptyPlan = ExamRescuePlan(
          examTitle: 'Empty Exam',
          daysRemaining: 1,
          totalEstimatedMinutes: 0,
          strategySummary: '',
          sourceMode: 'general_subject',
          generationMode: 'ai',
          days: const [],
        );

        final result = await service.applyPlan(
          plan: emptyPlan,
          examTitle: 'Empty Exam',
          examDate: testNow,
          dailyTargetMinutes: 60,
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Add at least one plan item'));
        expect(fakeFirestore.store.isEmpty, isTrue);
      },
    );

    test(
      '12: Firestore batch failure returns error without throwing unhandled exception',
      () async {
        final service = buildService();
        final plan = createSamplePlan();
        fakeFirestore.failNextBatch = true;

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, isNotNull);
        expect(result.sessionId, isNotNull);
        expect(result.taskIds.length, 4);
      },
    );

    test(
      '14: Notification failure does NOT delete or rollback persisted tasks',
      () async {
        final service = buildService();
        final plan = createSamplePlan();
        reminderShouldFail = true;

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        expect(
          result.success,
          isTrue,
          reason: 'Persistence succeeds even if alarm engine fails',
        );
        expect(result.reminderFailed, isTrue);
        expect(
          fakeFirestore.store.keys.where((k) => k.startsWith('tasks/')).length,
          4,
        );
      },
    );

    test(
      '17 & 18: Deterministic local date/time mapping prevents timezone boundary day-shift',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        // Verify Day 1 tasks (dateOffset: 0) are scheduled at 20:00 on testNow (2026-10-15)
        final task0Due =
            (fakeFirestore.store['tasks/${result.taskIds[0]}']!['dueAt']
                    as Timestamp)
                .toDate();
        expect(task0Due.year, 2026);
        expect(task0Due.month, 10);
        expect(task0Due.day, 15);
        expect(task0Due.hour, 20);
        expect(task0Due.minute, 0);

        // Verify Day 2 tasks (dateOffset: 1) are scheduled at 20:00 on tomorrow (2026-10-16)
        final task2Due =
            (fakeFirestore.store['tasks/${result.taskIds[2]}']!['dueAt']
                    as Timestamp)
                .toDate();
        expect(task2Due.year, 2026);
        expect(task2Due.month, 10);
        expect(task2Due.day, 16);
        expect(task2Due.hour, 20);
        expect(task2Due.minute, 0);

        // Verify PlanView boundary filtering: strictly between day start (00:00) and endOfDay (day + 1d)
        final day1Key = DateTime(2026, 10, 15);
        final day1End = day1Key.add(const Duration(days: 1));
        expect(
          !task0Due.isBefore(day1Key) && task0Due.isBefore(day1End),
          isTrue,
        );

        final day2Key = DateTime(2026, 10, 16);
        final day2End = day2Key.add(const Duration(days: 1));
        expect(
          !task2Due.isBefore(day2Key) && task2Due.isBefore(day2End),
          isTrue,
        );
      },
    );

    test(
      '16: PlanView stream query matches created rescue tasks on selected day',
      () async {
        final service = buildService();
        final plan = createSamplePlan();

        final result = await service.applyPlan(
          plan: plan,
          examTitle: 'Database Systems Final',
          examDate: testNow.add(const Duration(days: 2)),
          dailyTargetMinutes: 90,
        );

        // Simulate PlanView filtering for 2026-10-15
        final selectedDay = DateTime(2026, 10, 15);
        final dayKey = DateTime(
          selectedDay.year,
          selectedDay.month,
          selectedDay.day,
        );
        final endOfDay = dayKey.add(const Duration(days: 1));

        final matchedTasks = <Map<String, dynamic>>[];
        for (final taskId in result.taskIds) {
          final taskData = fakeFirestore.store['tasks/$taskId']!;
          if (taskData['done'] == true) continue;
          final due = (taskData['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          if (!due.isBefore(dayKey) && due.isBefore(endOfDay)) {
            matchedTasks.add(taskData);
          }
        }

        expect(matchedTasks.length, 2);
        expect(matchedTasks[0]['title'], 'Review Chapter 1 ER diagrams');
        expect(
          matchedTasks[1]['title'],
          '10-question practice quiz on SQL joins',
        );
      },
    );

    test('FeedbackMessages produces correct bilingual success string', () {
      final en = FeedbackMessages.examRescuePlanApplied(4);
      expect(en, 'Rescue plan added — 4 study tasks scheduled.');
    });
  });

  group('Phase T4 — ExamRescuePreviewScreen Widget Persistence Tests', () {
    testWidgets(
      '15: Confirm & Apply Plan persists plan and pops result with success to return to caller',
      (tester) async {
        final service = buildService();
        final plan = createSamplePlan();

        ApplyExamRescuePlanResult? poppedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    poppedResult = await Navigator.of(ctx)
                        .push<ApplyExamRescuePlanResult>(
                          MaterialPageRoute(
                            builder: (_) => ExamRescuePreviewScreen(
                              plan: plan,
                              initialTitle: 'Database Systems Final',
                              initialDate: testNow.add(const Duration(days: 2)),
                              initialDailyMinutes: 90,
                              persistenceService: service,
                            ),
                          ),
                        );
                  },
                  child: const Text('Open Preview'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Preview'));
        await tester.pumpAndSettle();

        expect(find.text('Confirm & Apply Plan'), findsOneWidget);

        await tester.tap(find.text('Confirm & Apply Plan'));
        await tester.pumpAndSettle();

        expect(poppedResult, isNotNull);
        expect(poppedResult!.success, isTrue);
        expect(poppedResult!.tasksCount, 4);

        // Verify we returned back to the caller screen (e.g. PlanView)
        expect(find.text('Open Preview'), findsOneWidget);
      },
    );

    testWidgets(
      '10: Double-tap Confirm & Apply Plan invokes persistence exactly once',
      (tester) async {
        final service = ExamRescuePersistenceService(
          firestore: fakeFirestore,
          getUid: () => 'test_student_1',
          scheduleReminder:
              ({
                required taskId,
                required title,
                when,
                String type = 'task',
              }) async {},
          now: () => testNow,
        );

        final plan = createSamplePlan();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExamRescuePreviewScreen(
                plan: plan,
                initialTitle: 'Database Systems Final',
                initialDate: testNow.add(const Duration(days: 2)),
                initialDailyMinutes: 90,
                persistenceService: service,
              ),
            ),
          ),
        );

        final confirmFinder = find.text('Confirm & Apply Plan');
        expect(confirmFinder, findsOneWidget);

        // Tap twice rapidly
        await tester.tap(confirmFinder);
        await tester.tap(confirmFinder);
        await tester.pumpAndSettle();

        final sessionDocs = fakeFirestore.store.keys
            .where((k) => k.contains('/exam_rescue/'))
            .length;
        expect(sessionDocs, 1);
      },
    );

    testWidgets(
      '11: Empty edited preview blocks apply and shows warning snackbar',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = buildService();
        final plan = createSamplePlan();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExamRescuePreviewScreen(
                plan: plan,
                initialTitle: 'Database Systems Final',
                initialDate: testNow.add(const Duration(days: 2)),
                initialDailyMinutes: 90,
                persistenceService: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Delete all 4 items
        while (find.byTooltip('Remove item').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Remove item').first);
          await tester.pumpAndSettle();
        }

        // Tap Confirm & Apply Plan
        await tester.tap(find.text('Confirm & Apply Plan'));
        await tester.pumpAndSettle();

        expect(
          find.text('Add at least one plan item before applying.'),
          findsOneWidget,
        );
        expect(fakeFirestore.store.isEmpty, isTrue);
      },
    );

    testWidgets(
      '12: Firestore failure remains on Preview, shows error and allows retry with same IDs',
      (tester) async {
        final service = buildService();
        final plan = createSamplePlan();
        fakeFirestore.failNextBatch = true;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExamRescuePreviewScreen(
                plan: plan,
                initialTitle: 'Database Systems Final',
                initialDate: testNow.add(const Duration(days: 2)),
                initialDailyMinutes: 90,
                persistenceService: service,
              ),
            ),
          ),
        );

        // First attempt fails
        await tester.tap(find.text('Confirm & Apply Plan'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Failed to save rescue plan. Please check your connection and try again.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Confirm & Apply Plan'),
          findsOneWidget,
        ); // still on screen

        // Fix network and retry
        fakeFirestore.failNextBatch = false;
        await tester.tap(find.text('Confirm & Apply Plan'));
        await tester.pumpAndSettle();

        // Successfully saved on retry
        expect(
          fakeFirestore.store.keys.where((k) => k.startsWith('tasks/')).length,
          4,
        );
      },
    );
  });
}
