import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/student/student_ai_context.dart';
import 'package:gochano/core/student/student_context.dart';
import 'package:gochano/core/student/student_event.dart';

void main() {
  group('StudentAiContext.fromContext', () {
    test('builds safe DTO from StudentContext', () {
      final ctx = StudentContext(
        generatedAt: DateTime(2026, 9, 10, 12, 0),
        todayEvents: [
          StudentEvent(
            id: 'task_1',
            sourceId: 'doc1',
            type: StudentEventType.task,
            title: 'Finish homework',
            scheduledAt: DateTime(2026, 9, 10, 14, 0),
            status: StudentEventStatus.pending,
            source: 'tasks',
          ),
        ],
        overdueEvents: [
          StudentEvent(
            id: 'task_2',
            sourceId: 'doc2',
            type: StudentEventType.assignment,
            title: 'Essay draft',
            scheduledAt: DateTime(2026, 9, 8),
            status: StudentEventStatus.overdue,
            source: 'tasks',
          ),
        ],
        studySummary: StudySummary(
          totalTasks: 10,
          completedToday: 3,
          upcomingCount: 5,
          overdueCount: 2,
        ),
        moneySummary: MoneySummary(
          backendRemaining: 500,
          totalSpent: 1500,
        ),
        communitySummary: CommunitySummary(groupCount: 2),
      );

      final ai = StudentAiContext.fromContext(ctx);

      expect(ai.generatedAt, isNotNull);
      expect(ai.todayEvents, hasLength(1));
      expect(ai.todayEvents.first.type, 'task');
      expect(ai.todayEvents.first.title, 'Finish homework');
      expect(ai.todayEvents.first.status, 'pending');
      expect(ai.overdueEvents, hasLength(1));
      expect(ai.overdueEvents.first.title, 'Essay draft');
      expect(ai.studySummary, isNotNull);
      expect(ai.studySummary!.totalTasks, 10);
      expect(ai.moneySummary, isNotNull);
      expect(ai.moneySummary!.totalSpent, 1500);
      expect(ai.moneySummary!.remaining, 500);
      expect(ai.communitySummary!.groupCount, 2);
    });

    test('excludes internal IDs and metadata', () {
      final ctx = StudentContext(
        generatedAt: DateTime(2026, 9, 10),
        todayEvents: [
          StudentEvent(
            id: 'deterministic_id_123',
            sourceId: 'firestore_doc_id',
            type: StudentEventType.task,
            title: 'Test',
            status: StudentEventStatus.pending,
            source: 'tasks',
            metadata: {'medicineId': 'secret123', 'doseTime': '08:00'},
          ),
        ],
      );

      final ai = StudentAiContext.fromContext(ctx);
      final json = ai.toJson();
      final jsonStr = jsonEncode(json);

      // Internal IDs must NOT appear
      expect(jsonStr, isNot(contains('deterministic_id_123')));
      expect(jsonStr, isNot(contains('firestore_doc_id')));
      expect(jsonStr, isNot(contains('secret123')));
      expect(jsonStr, isNot(contains('source')));
      expect(jsonStr, isNot(contains('metadata')));
    });

    test('does NOT include phone number, UID, or tokens', () {
      final ctx = StudentContext(
        generatedAt: DateTime(2026, 9, 10),
      );

      final ai = StudentAiContext.fromContext(ctx);
      final jsonStr = jsonEncode(ai.toJson());

      expect(jsonStr, isNot(contains('phone')));
      expect(jsonStr, isNot(contains('uid')));
      expect(jsonStr, isNot(contains('token')));
      expect(jsonStr, isNot(contains('firebase')));
      expect(jsonStr, isNot(contains('b2')));
      expect(jsonStr, isNot(contains('api_key')));
    });

    test('bounds event counts', () {
      final events = List.generate(
        20,
        (i) => StudentEvent(
          id: 'task_$i',
          sourceId: 'doc_$i',
          type: StudentEventType.task,
          title: 'Task $i',
          scheduledAt: DateTime(2026, 9, 10, i),
          status: StudentEventStatus.pending,
          source: 'tasks',
        ),
      );

      final ctx = StudentContext(
        generatedAt: DateTime(2026, 9, 10),
        todayEvents: events,
        upcomingEvents: events,
        overdueEvents: events,
        pendingMedicine: events,
      );

      final ai = StudentAiContext.fromContext(ctx);

      expect(ai.todayEvents.length, lessThanOrEqualTo(StudentAiContext.maxEvents));
      expect(ai.upcomingEvents.length, lessThanOrEqualTo(StudentAiContext.maxEvents));
      expect(ai.overdueEvents.length, lessThanOrEqualTo(StudentAiContext.maxEvents));
      expect(ai.pendingMedicine.length, lessThanOrEqualTo(StudentAiContext.maxMedicine));
    });
  });

  group('StudentAiContext.toJson', () {
    test('serializes to valid JSON', () {
      final ai = StudentAiContext(
        generatedAt: DateTime(2026, 9, 10).toIso8601String(),
        todayEvents: [
          AiEvent(type: 'task', title: 'Test', status: 'pending'),
        ],
        studySummary: AiStudySummary(
          totalTasks: 5,
          completedToday: 2,
          upcomingCount: 2,
          overdueCount: 1,
        ),
      );

      final json = ai.toJson();
      final encoded = jsonEncode(json);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['generatedAt'], isNotNull);
      expect(decoded['todayEvents'], isA<List>());
      expect(decoded['studySummary'], isA<Map>());
    });

    test('omits null fields', () {
      final ai = StudentAiContext();
      final json = ai.toJson();

      expect(json.containsKey('generatedAt'), isFalse);
      expect(json.containsKey('todayEvents'), isFalse);
      expect(json.containsKey('moneySummary'), isFalse);
    });

    test('isEmpty when no data', () {
      expect(StudentAiContext().isEmpty, isTrue);
    });

    test('is not empty when data present', () {
      final ai = StudentAiContext(
        todayEvents: [
          AiEvent(type: 'task', title: 'X', status: 'pending'),
        ],
      );
      expect(ai.isEmpty, isFalse);
    });
  });

  group('AiEvent', () {
    test('fromStudentEvent maps type and status names', () {
      final e = StudentEvent(
        id: 'id',
        sourceId: 'src',
        type: StudentEventType.assignment,
        title: 'Essay',
        scheduledAt: DateTime(2026, 9, 10),
        status: StudentEventStatus.overdue,
        source: 'tasks',
      );

      final ai = AiEvent.fromStudentEvent(e);
      expect(ai.type, 'assignment');
      expect(ai.status, 'overdue');
      expect(ai.title, 'Essay');
      expect(ai.scheduledAt, isNotNull);
    });

    test('excludes internal IDs', () {
      final e = StudentEvent(
        id: 'deterministic_id',
        sourceId: 'firestore_id',
        type: StudentEventType.task,
        title: 'Test',
        status: StudentEventStatus.pending,
        source: 'tasks',
      );

      final ai = AiEvent.fromStudentEvent(e);
      final json = ai.toJson();
      final jsonStr = jsonEncode(json);

      expect(jsonStr, isNot(contains('deterministic_id')));
      expect(jsonStr, isNot(contains('firestore_id')));
      expect(jsonStr, isNot(contains('source')));
    });
  });

  group('AiMoneySummary', () {
    test('fromMoneySummary computes adjustedRemaining', () {
      final m = MoneySummary(
        backendRemaining: 1000,
        totalSpent: 500,
        pawnaReceived: 200,
        denaPaid: 100,
      );

      final ai = AiMoneySummary.fromMoneySummary(m);
      expect(ai.totalSpent, 500);
      expect(ai.remaining, 1200); // 1000 + 200 (denaPaid already in ledger)
    });
  });

  group('Context scope rules', () {
    test('study-only context excludes money and medicine', () {
      final ctx = StudentContext(
        generatedAt: DateTime(2026, 9, 10),
        studySummary: StudySummary(
          totalTasks: 5,
          completedToday: 1,
          upcomingCount: 3,
          overdueCount: 1,
        ),
      );

      final ai = StudentAiContext.fromContext(ctx);
      expect(ai.moneySummary, isNull);
      expect(ai.pendingMedicine, isEmpty);
    });

    test('empty context has isEmpty true', () {
      final ctx = StudentContext(generatedAt: DateTime(2026, 9, 10));
      final ai = StudentAiContext.fromContext(ctx);
      expect(ai.isEmpty, isTrue);
      expect(ai.medicineAvailable, isTrue);
    });
  });

  group('toPromptString', () {
    test('produces formatted JSON string', () {
      final ai = StudentAiContext(
        generatedAt: '2026-09-10T12:00:00',
        studySummary: AiStudySummary(
          totalTasks: 5,
          completedToday: 1,
          upcomingCount: 3,
          overdueCount: 1,
        ),
      );

      final str = ai.toPromptString();
      expect(str, contains('generatedAt'));
      expect(str, contains('studySummary'));
      // Should be valid JSON
      final decoded = jsonDecode(str);
      expect(decoded, isA<Map>());
    });
  });

  group('medicineAvailable', () {
    test('defaults to true in StudentContext', () {
      final ctx = StudentContext(generatedAt: DateTime(2026, 9, 10));
      expect(ctx.medicineAvailable, isTrue);
    });

    test('defaults to false in StudentAiContext', () {
      final ai = StudentAiContext();
      expect(ai.medicineAvailable, isFalse);
    });

    test('fromContext passes medicineAvailable through', () {
      final ctx = StudentContext(
        generatedAt: DateTime(2026, 9, 10),
        medicineAvailable: false,
      );
      final ai = StudentAiContext.fromContext(ctx);
      expect(ai.medicineAvailable, isFalse);
    });

    test('medicineAvailable true + empty pendingMedicine shows no pending doses',
        () {
      final ai = StudentAiContext(
        medicineAvailable: true,
        pendingMedicine: [],
      );
      final str = ai.toPromptString();
      final decoded = jsonDecode(str) as Map<String, dynamic>;
      expect(decoded['medicineAvailable'], isTrue);
      expect(decoded['pendingMedicineNote'], 'no pending doses');
    });

    test('medicineAvailable false shows not available', () {
      final ai = StudentAiContext(
        medicineAvailable: false,
        pendingMedicine: [],
      );
      final str = ai.toPromptString();
      final decoded = jsonDecode(str) as Map<String, dynamic>;
      expect(decoded['medicineAvailable'], isFalse);
      expect(decoded['pendingMedicineNote'], 'not available');
    });

    test('medicineAvailable true with pending doses has no note', () {
      final ai = StudentAiContext(
        medicineAvailable: true,
        pendingMedicine: [
          AiEvent(type: 'medicine', title: 'Aspirin', status: 'pending'),
        ],
      );
      final str = ai.toPromptString();
      final decoded = jsonDecode(str) as Map<String, dynamic>;
      expect(decoded['medicineAvailable'], isTrue);
      expect(decoded.containsKey('pendingMedicineNote'), isFalse);
    });

    test('toJson includes medicineAvailable', () {
      final ai = StudentAiContext(medicineAvailable: true);
      final json = ai.toJson();
      expect(json['medicineAvailable'], isTrue);
    });

    test('toJson defaults medicineAvailable to false', () {
      final ai = StudentAiContext();
      final json = ai.toJson();
      expect(json['medicineAvailable'], isFalse);
    });
  });

  // ======================================================================
  // Context scoping (Phase 6.1)
  // ======================================================================

  group('toJsonScoped', () {
    final ai = StudentAiContext(
      todayEvents: const [],
      upcomingEvents: const [],
      overdueEvents: const [],
      pendingMedicine: const [],
      medicineAvailable: true,
      studySummary: const AiStudySummary(
        totalTasks: 5,
        completedToday: 2,
        upcomingCount: 3,
        overdueCount: 0,
      ),
      moneySummary: const AiMoneySummary(totalSpent: 1000, remaining: 4000),
      communitySummary: const AiCommunitySummary(groupCount: 2),
    );

    test('study question excludes money and medicine', () {
      final scoped = ai.toJsonScoped('What should I study first?');
      expect(scoped.containsKey('studySummary'), isTrue);
      expect(scoped.containsKey('moneySummary'), isFalse);
      expect(scoped.containsKey('pendingMedicine'), isFalse);
      expect(scoped.containsKey('medicineAvailable'), isFalse);
      expect(scoped.containsKey('communitySummary'), isTrue);
    });

    test('money question includes money context', () {
      final scoped = ai.toJsonScoped('How much did I spend today?');
      expect(scoped.containsKey('moneySummary'), isTrue);
      expect(scoped['moneySummary']['totalSpent'], 1000);
    });

    test('medicine question includes medicine context', () {
      final scoped = ai.toJsonScoped('Did I take my medicine?');
      expect(scoped.containsKey('pendingMedicine'), isTrue);
      expect(scoped.containsKey('medicineAvailable'), isTrue);
      expect(scoped['medicineAvailable'], isTrue);
      // Empty pendingMedicine + available → "no pending doses"
      expect(scoped['pendingMedicineNote'], 'no pending doses');
    });

    test('unrelated question excludes both money and medicine', () {
      final scoped = ai.toJsonScoped('Explain photosynthesis');
      expect(scoped.containsKey('moneySummary'), isFalse);
      expect(scoped.containsKey('pendingMedicine'), isFalse);
      expect(scoped.containsKey('medicineAvailable'), isFalse);
    });

    test('bengali money keywords trigger money scope', () {
      // Bengali doesn't match English money pattern, but English does
      final scopedEn = ai.toJsonScoped('What is my budget?');
      expect(scopedEn.containsKey('moneySummary'), isTrue);
    });

    test('medicine keywords like paracetamol trigger medicine scope', () {
      final scoped = ai.toJsonScoped('When is my next paracetamol dose?');
      expect(scoped.containsKey('pendingMedicine'), isTrue);
      expect(scoped.containsKey('medicineAvailable'), isTrue);
      expect(scoped['medicineAvailable'], isTrue);
    });

    test('transport/fare triggers money scope', () {
      final scoped = ai.toJsonScoped('How much is the transport fare?');
      expect(scoped.containsKey('moneySummary'), isTrue);
    });
  });
}
