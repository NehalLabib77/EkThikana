import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/study/presentation/rescue/exam_rescue_models.dart';

void main() {
  group('ExamRescueItem', () {
    test('parses full camelCase JSON correctly', () {
      final json = {
        'title': 'Review Chapter 1: Relational Algebra',
        'type': 'study',
        'estimatedMinutes': 45,
        'materialId': 'mat-123',
        'actionNote': 'Focus on selection and projection operators.',
      };

      final item = ExamRescueItem.fromJson(json);

      expect(item.title, 'Review Chapter 1: Relational Algebra');
      expect(item.type, 'study');
      expect(item.estimatedMinutes, 45);
      expect(item.materialId, 'mat-123');
      expect(item.actionNote, 'Focus on selection and projection operators.');
      expect(item.isStudy, isTrue);
      expect(item.isPractice, isFalse);
      expect(item.isQuiz, isFalse);
      expect(item.isRevision, isFalse);
      expect(item.hasMaterial, isTrue);
    });

    test('parses snake_case keys as fallback', () {
      final json = {
        'title': 'Solve Practice Problems',
        'type': 'practice',
        'estimated_minutes': 60,
        'material_id': 'mat-456',
        'action_note': 'Solve questions 1-5.',
      };

      final item = ExamRescueItem.fromJson(json);

      expect(item.title, 'Solve Practice Problems');
      expect(item.type, 'practice');
      expect(item.estimatedMinutes, 60);
      expect(item.materialId, 'mat-456');
      expect(item.actionNote, 'Solve questions 1-5.');
      expect(item.isPractice, isTrue);
    });

    test('normalizes type synonyms accurately', () {
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'test'}).type, 'quiz');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'mcq'}).type, 'quiz');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'exam'}).type, 'quiz');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'assessment'}).type, 'quiz');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'review'}).type, 'revision');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'recap'}).type, 'revision');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'exercise'}).type, 'practice');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'problem'}).type, 'practice');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'homework'}).type, 'practice');
      expect(ExamRescueItem.fromJson({'title': 'T', 'type': 'unknown_type'}).type, 'study');
    });

    test('handles missing or malformed fields safely', () {
      final item = ExamRescueItem.fromJson({});
      expect(item.title, '');
      expect(item.type, 'study');
      expect(item.estimatedMinutes, 30);
      expect(item.materialId, '');
      expect(item.actionNote, '');
      expect(item.hasMaterial, isFalse);
    });

    test('serializes to JSON correctly', () {
      const item = ExamRescueItem(
        title: 'Mock Quiz 1',
        type: 'quiz',
        estimatedMinutes: 25,
        materialId: 'mat-789',
        actionNote: 'Check score afterwards.',
      );

      final json = item.toJson();
      expect(json['title'], 'Mock Quiz 1');
      expect(json['type'], 'quiz');
      expect(json['estimatedMinutes'], 25);
      expect(json['materialId'], 'mat-789');
      expect(json['actionNote'], 'Check score afterwards.');
    });
  });

  group('ExamRescueDay', () {
    test('parses day with items and computes aggregations', () {
      final json = {
        'dayNumber': 1,
        'dateOffset': 0,
        'theme': 'Core Concepts & Diagnostic',
        'targetMinutes': 120,
        'items': [
          {
            'title': 'Chapter 1 Theory',
            'type': 'study',
            'estimatedMinutes': 60,
          },
          {
            'title': 'Practice Set 1',
            'type': 'practice',
            'estimatedMinutes': 30,
          },
          {
            'title': 'Diagnostic Quiz',
            'type': 'quiz',
            'estimatedMinutes': 30,
          },
        ],
      };

      final day = ExamRescueDay.fromJson(json);

      expect(day.dayNumber, 1);
      expect(day.dateOffset, 0);
      expect(day.theme, 'Core Concepts & Diagnostic');
      expect(day.targetMinutes, 120);
      expect(day.items.length, 3);
      expect(day.totalMinutes, 120);
      expect(day.quizCount, 1);
    });

    test('handles empty or missing items list', () {
      final day = ExamRescueDay.fromJson({
        'dayNumber': 2,
        'theme': 'Revision',
      });

      expect(day.dayNumber, 2);
      expect(day.dateOffset, 0);
      expect(day.theme, 'Revision');
      expect(day.targetMinutes, 120);
      expect(day.items, isEmpty);
      expect(day.totalMinutes, 0);
      expect(day.quizCount, 0);
    });
  });

  group('ExamRescuePlan', () {
    test('parses full plan response and verifies getters', () {
      final json = {
        'examTitle': 'Operating Systems Final',
        'daysRemaining': 3,
        'totalEstimatedMinutes': 360,
        'strategySummary': '3-day rapid preparation covering processes, memory, and storage.',
        'sourceMode': 'materials',
        'generationMode': 'ai',
        'days': [
          {
            'dayNumber': 1,
            'dateOffset': 0,
            'theme': 'Processes and Threads',
            'targetMinutes': 120,
            'items': [
              {
                'title': 'Process Scheduling',
                'type': 'study',
                'estimatedMinutes': 60,
                'materialId': 'mat-os-1',
              },
              {
                'title': 'Checkpoint Quiz',
                'type': 'quiz',
                'estimatedMinutes': 30,
              },
            ],
          },
          {
            'dayNumber': 2,
            'dateOffset': 1,
            'theme': 'Memory Management',
            'targetMinutes': 120,
            'items': [
              {
                'title': 'Virtual Memory Review',
                'type': 'study',
                'estimatedMinutes': 60,
                'materialId': 'mat-os-2',
              },
              {
                'title': 'Page Replacement Problems',
                'type': 'practice',
                'estimatedMinutes': 60,
              },
            ],
          },
          {
            'dayNumber': 3,
            'dateOffset': 2,
            'theme': 'Comprehensive Mock & Final Review',
            'targetMinutes': 120,
            'items': [
              {
                'title': 'Full Mock Exam',
                'type': 'quiz',
                'estimatedMinutes': 60,
              },
              {
                'title': 'Formula & Cheat Sheet Polish',
                'type': 'revision',
                'estimatedMinutes': 60,
              },
            ],
          },
        ],
      };

      final plan = ExamRescuePlan.fromJson(json);

      expect(plan.examTitle, 'Operating Systems Final');
      expect(plan.daysRemaining, 3);
      expect(plan.totalEstimatedMinutes, 360);
      expect(plan.strategySummary, contains('3-day rapid preparation'));
      expect(plan.sourceMode, 'materials');
      expect(plan.generationMode, 'ai');
      expect(plan.isGroundedInMaterials, isTrue);
      expect(plan.isFallback, isFalse);

      expect(plan.days.length, 3);
      expect(plan.totalItemsCount, 6);
      expect(plan.totalQuizzesCount, 2);

      // Verify serialization round trip
      final serialized = plan.toJson();
      expect(serialized['examTitle'], 'Operating Systems Final');
      expect(serialized['daysRemaining'], 3);
      expect((serialized['days'] as List).length, 3);

      final roundTrip = ExamRescuePlan.fromJson(serialized);
      expect(roundTrip.examTitle, plan.examTitle);
      expect(roundTrip.totalItemsCount, plan.totalItemsCount);
      expect(roundTrip.totalQuizzesCount, plan.totalQuizzesCount);
    });

    test('correctly identifies fallback and general subject flags', () {
      final json = {
        'examTitle': 'Physics',
        'daysRemaining': 1,
        'totalEstimatedMinutes': 120,
        'strategySummary': 'Fallback emergency cram plan.',
        'sourceMode': 'general_subject',
        'generationMode': 'fallback',
        'days': [],
      };

      final plan = ExamRescuePlan.fromJson(json);

      expect(plan.isGroundedInMaterials, isFalse);
      expect(plan.isFallback, isTrue);
      expect(plan.totalItemsCount, 0);
      expect(plan.totalQuizzesCount, 0);
    });
  });
}
