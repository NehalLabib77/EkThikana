import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/navigation.dart';
import 'package:gochano/features/study/presentation/exam_ecosystem/exam_ecosystem_models.dart';
import 'package:gochano/features/study/presentation/exam_ecosystem/exam_hub_screen.dart';
import 'package:gochano/shared/widgets/gochano_controls.dart';

void main() {
  group('Phase 15 Exam Ecosystem Models Test', () {
    test('ExamPlan deserialization and countdown calculation', () {
      final futureDate =
          DateTime.now().add(const Duration(days: 15)).toIso8601String().substring(0, 10);
      final json = {
        'planId': 'plan_test_1',
        'examName': 'HSC Physics 2026',
        'examDate': futureDate,
        'durationDays': 30,
        'dailyMinutes': 120,
        'status': 'active',
        'subjects': ['Physics', 'Chemistry'],
      };

      final plan = ExamPlan.fromJson(json);
      expect(plan.planId, 'plan_test_1');
      expect(plan.examName, 'HSC Physics 2026');
      expect(plan.durationDays, 30);
      expect(plan.dailyMinutes, 120);
      expect(plan.subjects.length, 2);
      expect(plan.daysRemaining, inInclusiveRange(14, 15));
    });

    test('ExamPlan handles past dates safely', () {
      final pastDate = '2020-01-01';
      final json = {
        'planId': 'plan_past',
        'examName': 'Past Exam',
        'examDate': pastDate,
        'durationDays': 7,
        'dailyMinutes': 60,
        'status': 'expired',
      };

      final plan = ExamPlan.fromJson(json);
      expect(plan.daysRemaining, 0);
    });

    test('PriorityTopic deserialization and priority labels', () {
      final json = {
        'topic': "Newton's Law",
        'priority': 'critical',
        'priorityScore': 91.5,
        'components': {
          'historicalFrequency': 88.0,
          'masteryGap': 74.0,
          'mistakePressure': 100.0,
          'revisionUrgency': 95.0,
          'recentPerformanceGap': 82.0,
        },
      };

      final topic = PriorityTopic.fromJson(json);
      expect(topic.topic, "Newton's Law");
      expect(topic.priority, 'critical');
      expect(topic.priorityLabel, 'CRITICAL');
      expect(topic.priorityScore, 91.5);
      expect(topic.historicalFrequency, 88.0);
      expect(topic.masteryGap, 74.0);
      expect(topic.mistakePressure, 100.0);
      expect(topic.revisionUrgency, 95.0);
      expect(topic.recentPerformanceGap, 82.0);
    });

    test('ExamReadiness deserialization with 5 components', () {
      final json = {
        'overallReadiness': 78.4,
        'label': 'Good',
        'trend': 3.2,
        'components': {
          'masteryCoverage': 80.0,
          'mockExamPerformance': 75.0,
          'recentPractice': 85.0,
          'revisionCoverage': 70.0,
          'focusConsistency': 90.0,
        },
        'recommendedNextAction': 'Clear overdue spaced-repetition items',
        'dataCoverage': 1.0,
        'criticalTopics': ['Optics', 'Thermodynamics'],
        'strongTopics': ['Vectors'],
      };

      final readiness = ExamReadiness.fromJson(json);
      expect(readiness.overallReadiness, 78.4);
      expect(readiness.label, 'Good');
      expect(readiness.trend, 3.2);
      expect(readiness.components.length, 5);
      expect(readiness.components['masteryCoverage'], 80.0);
      expect(readiness.components['focusConsistency'], 90.0);
      expect(readiness.criticalTopics, contains('Optics'));
      expect(readiness.strongTopics, contains('Vectors'));
      expect(readiness.recommendedNextAction,
          'Clear overdue spaced-repetition items');
    });

    test('StudyBlock deserialization and block type label', () {
      final json = {
        'itemId': 'block_1',
        'blockType': 'mistake_revision',
        'topic': 'Kinematics',
        'durationMinutes': 25,
        'priority': 'critical',
        'status': 'completed',
        'reason': 'Review 3 repeat mistakes',
        'phase': 'Foundation',
      };

      final block = StudyBlock.fromJson(json);
      expect(block.itemId, 'block_1');
      expect(block.blockType, 'mistake_revision');
      expect(block.blockTypeLabel, 'Mistakes');
      expect(block.topic, 'Kinematics');
      expect(block.durationMinutes, 25);
      expect(block.isCompleted, isTrue);
      expect(block.reason, 'Review 3 repeat mistakes');
      expect(block.phase, 'Foundation');
    });

    test('PastPaperInsight deserialization', () {
      final json = {
        'papersAnalyzed': 5,
        'yearsCovered': [2021, 2022, 2023, 2024],
        'subjects': ['Physics', 'Chemistry'],
        'totalQuestions': 142,
        'topicStats': [
          {
            'topic': 'Electromagnetism',
            'historicalFrequencyScore': 85,
            'questionCount': 18,
          }
        ],
      };

      final insight = PastPaperInsight.fromJson(json);
      expect(insight.papersAnalyzed, 5);
      expect(insight.yearsCovered.length, 4);
      expect(insight.subjects.length, 2);
      expect(insight.totalQuestions, 142);
      expect(insight.topicStats.length, 1);
    });

    test('CoachingItem deserialization', () {
      final json = {
        'type': 'study_recommendation',
        'topic': 'Nuclear Physics',
        'action': 'Review core definitions and formulas',
        'durationMinutes': 30,
        'priority': 'high',
        'reason': 'Frequently tested in past papers',
      };

      final item = CoachingItem.fromJson(json);
      expect(item.type, 'study_recommendation');
      expect(item.topic, 'Nuclear Physics');
      expect(item.action, 'Review core definitions and formulas');
      expect(item.durationMinutes, 30);
      expect(item.priority, 'high');
      expect(item.reason, 'Frequently tested in past papers');
    });
  });

  group('Phase 15 Exam Ecosystem Navigation Integration Tests', () {
    test('Study screen source exposes Exam Prep AppBar action linking to ExamHubScreen', () {
      final studySrc = File('lib/features/study/presentation/study_screen.dart').readAsStringSync();
      expect(studySrc, contains('ExamHubScreen'));
      expect(studySrc, contains("'Exam Prep'"));
      expect(studySrc, contains('const ExamHubScreen()'));
    });

    test('WorkspaceView source exposes Exam Prep Quick Access item linking to ExamHubScreen', () {
      final workspaceSrc = File('lib/features/study/presentation/workspace/workspace_view.dart').readAsStringSync();
      expect(workspaceSrc, contains('ExamHubScreen'));
      expect(workspaceSrc, contains("'Exam Prep'"));
      expect(workspaceSrc, contains('const ExamHubScreen()'));
    });

    test('Student shell retains strictly 5 primary bottom destinations (no new tab added)', () {
      expect(StudentArea.values.length, 5);
      expect(StudentArea.count, 5);
      final content = File(
        'lib/features/shell/presentation/gochano_shell.dart',
      ).readAsStringSync();
      final destStart = content.indexOf('List<_Destination> _buildDestinations');
      final studyStart = content.indexOf(
        'if (mode == GochanoAppMode.study) {',
        destStart,
      );
      final studyEnd = content.indexOf('// Utility Mode', studyStart);
      final studySection = content.substring(studyStart, studyEnd);
      final studentDestinations = RegExp(
        r"label:\s*GochanoLanguage\.text\('([^']+)'",
      ).allMatches(studySection).map((m) => m.group(1)).toList();
      expect(studentDestinations.length, 5);
      expect(studentDestinations, equals(['Today', 'Workspace', 'Plan', 'Community', 'Profile']));
    });

    testWidgets('Tapping Exam Prep IconActionButton triggers navigation', (tester) async {
      var navigated = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                IconActionButton(
                  icon: Icons.fact_check_outlined,
                  label: 'Exam Prep',
                  onPressed: () {
                    navigated = true;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byTooltip('Exam Prep'), findsOneWidget);
      await tester.tap(find.byTooltip('Exam Prep'));
      expect(navigated, isTrue);
    });
  });
}
