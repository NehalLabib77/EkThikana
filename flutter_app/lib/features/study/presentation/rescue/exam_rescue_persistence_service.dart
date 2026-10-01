// Phase T4 — Exam Rescue Persistence Service
//
// Converts an in-memory ExamRescuePlan into:
// 1. ONE Exam Rescue session envelope (users/{uid}/exam_rescue/{sessionId})
// 2. Standard top-level tasks (tasks/{taskId})
//
// All operations are executed atomically in a single Firestore WriteBatch.
// Task reminders are scheduled best-effort via NotificationService without
// failing task persistence if notifications or alarm permissions fail.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/localization/gochano_language.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/notification_service.dart';
import 'exam_rescue_models.dart';

/// Result envelope returned by [ExamRescuePersistenceService.applyPlan].
@immutable
class ApplyExamRescuePlanResult {
  final bool success;
  final String? sessionId;
  final List<String> taskIds;
  final int tasksCount;
  final bool reminderFailed;
  final String? errorMessage;

  const ApplyExamRescuePlanResult({
    required this.success,
    this.sessionId,
    this.taskIds = const [],
    this.tasksCount = 0,
    this.reminderFailed = false,
    this.errorMessage,
  });
}

/// Internal representation of a materialized task ready for batch write and reminders.
class _MaterializedTask {
  final String taskId;
  final String title;
  final DateTime dueAt;
  final Map<String, dynamic> payload;

  const _MaterializedTask({
    required this.taskId,
    required this.title,
    required this.dueAt,
    required this.payload,
  });
}

class ExamRescuePersistenceService {
  final FirebaseFirestore? _firestore;
  final String? Function()? _getUid;
  final Future<void> Function({
    required String taskId,
    required String title,
    DateTime? when,
    String type,
  })?
  _scheduleReminder;
  final DateTime Function()? _now;

  const ExamRescuePersistenceService({
    FirebaseFirestore? firestore,
    String? Function()? getUid,
    Future<void> Function({
      required String taskId,
      required String title,
      DateTime? when,
      String type,
    })?
    scheduleReminder,
    DateTime Function()? now,
  }) : _firestore = firestore,
       _getUid = getUid,
       _scheduleReminder = scheduleReminder,
       _now = now;

  FirebaseFirestore get firestore => _firestore ?? FirestoreService.db;
  String? get uid => _getUid != null ? _getUid() : FirestoreService.uid;
  DateTime get now => _now != null ? _now() : DateTime.now();

  /// Generates a stable session ID upfront for idempotency.
  String generateSessionId([String? customUid]) {
    final effectiveUid = customUid ?? uid ?? 'anonymous';
    return firestore
        .collection('users')
        .doc(effectiveUid)
        .collection('exam_rescue')
        .doc()
        .id;
  }

  /// Generates stable task document IDs upfront for idempotency.
  List<String> generateTaskIds(int count) {
    return List.generate(count, (_) => firestore.collection('tasks').doc().id);
  }

  /// Persists [plan] by creating one session document in `users/{uid}/exam_rescue/{sessionId}`
  /// and standard tasks in `tasks/{taskId}`.
  ///
  /// Respects in-memory preview edits: only items present in [plan.days] are persisted.
  /// Reuses [preallocatedSessionId] and [preallocatedTaskIds] on retry so repeated calls
  /// are strictly idempotent.
  Future<ApplyExamRescuePlanResult> applyPlan({
    required ExamRescuePlan plan,
    required String examTitle,
    required DateTime examDate,
    required int dailyTargetMinutes,
    List<Map<String, String>> materials = const [],
    String? preallocatedSessionId,
    List<String>? preallocatedTaskIds,
  }) async {
    final totalItems = plan.totalItemsCount;
    if (totalItems == 0) {
      return ApplyExamRescuePlanResult(
        success: false,
        errorMessage: GochanoLanguage.text(
          'Add at least one plan item before applying.',
          'প্ল্যান যোগ করার আগে অন্তত একটি আইটেম রাখুন।',
        ),
      );
    }

    if (totalItems > 50) {
      return ApplyExamRescuePlanResult(
        success: false,
        errorMessage: GochanoLanguage.text(
          'Plan contains too many items (maximum 50).',
          'প্ল্যানে অতিরিক্ত আইটেম রয়েছে (সর্বোচ্চ ৫০টি)।',
        ),
      );
    }

    final currentUid = uid;
    if (currentUid == null || currentUid.isEmpty) {
      return ApplyExamRescuePlanResult(
        success: false,
        errorMessage: GochanoLanguage.text(
          'User must be signed in to apply a rescue plan.',
          'প্ল্যান যোগ করতে লগইন থাকতে হবে।',
        ),
      );
    }

    // Allocate or reuse stable IDs
    final sessionId = preallocatedSessionId ?? generateSessionId(currentUid);
    final taskIds =
        (preallocatedTaskIds != null &&
            preallocatedTaskIds.length == totalItems)
        ? preallocatedTaskIds
        : generateTaskIds(totalItems);

    final sessionRef = firestore
        .collection('users')
        .doc(currentUid)
        .collection('exam_rescue')
        .doc(sessionId);

    final sessionPayload = <String, dynamic>{
      'ownerId': currentUid,
      'examTitle': examTitle.trim(),
      'examDate': Timestamp.fromDate(examDate),
      'dailyTargetMinutes': dailyTargetMinutes,
      'materialIds': materials
          .map((m) => m['id'] ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
      'materialTitles': materials
          .map((m) => m['title'] ?? '')
          .where((t) => t.isNotEmpty)
          .toList(),
      'sourceMode': plan.sourceMode,
      'generationMode': plan.generationMode,
      'strategySummary': plan.strategySummary,
      'status': 'active',
      'taskIds': taskIds,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final currentNow = now;
    final baseDate = DateTime(
      currentNow.year,
      currentNow.month,
      currentNow.day,
    );

    final materializedTasks = <_MaterializedTask>[];
    var taskIdx = 0;

    for (final day in plan.days) {
      final dayDate = baseDate.add(Duration(days: day.dateOffset));
      // Standard local study target time: 20:00 (8:00 PM) local device time
      final dueAt = DateTime(dayDate.year, dayDate.month, dayDate.day, 20, 0);

      for (int itemOrder = 0; itemOrder < day.items.length; itemOrder++) {
        final item = day.items[itemOrder];
        final taskId = taskIds[taskIdx];

        final payload = <String, dynamic>{
          'ownerId': currentUid,
          'title': item.title,
          'type': 'task',
          'dueAt': Timestamp.fromDate(dueAt),
          'remindAt': Timestamp.fromDate(dueAt),
          'done': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          // Exam Rescue traceability metadata
          'source': 'exam_rescue',
          'rescueSessionId': sessionId,
          'rescueItemType': item.type,
          if (item.materialId.isNotEmpty) 'materialId': item.materialId,
          'estimatedMinutes': item.estimatedMinutes,
          if (item.actionNote.isNotEmpty) 'actionNote': item.actionNote,
          'rescueDayNumber': day.dayNumber,
          'rescueOrder': itemOrder,
        };

        materializedTasks.add(
          _MaterializedTask(
            taskId: taskId,
            title: item.title,
            dueAt: dueAt,
            payload: payload,
          ),
        );

        taskIdx++;
      }
    }

    // Execute atomic batch write
    try {
      final batch = firestore.batch();
      batch.set(sessionRef, sessionPayload, SetOptions(merge: true));

      for (final task in materializedTasks) {
        final taskRef = firestore.collection('tasks').doc(task.taskId);
        batch.set(taskRef, task.payload, SetOptions(merge: true));
      }

      await batch.commit();
      if (kDebugMode) {
        debugPrint(
          '[ExamRescuePersistence] Batch committed successfully. '
          'Session: $sessionId, Tasks: ${materializedTasks.length}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ExamRescuePersistence] Batch commit error: $e');
      }
      return ApplyExamRescuePlanResult(
        success: false,
        sessionId: sessionId,
        taskIds: taskIds,
        errorMessage: GochanoLanguage.text(
          'Failed to save rescue plan. Please check your connection and try again.',
          'রেসকিউ প্ল্যান সংরক্ষণ করতে ব্যর্থ হয়েছে। ইন্টারনেট সংযোগ পরীক্ষা করে পুনরায় চেষ্টা করুন।',
        ),
      );
    }

    // Schedule reminders best-effort (non-fatal if notification engine fails)
    var reminderFailed = false;
    final scheduleFn = _scheduleReminder ?? NotificationService.rescheduleTask;

    for (final task in materializedTasks) {
      try {
        await scheduleFn(
          taskId: task.taskId,
          title: task.title,
          when: task.dueAt,
          type: 'task',
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[ExamRescuePersistence] Reminder schedule failed for task ${task.taskId}: $e',
          );
        }
        reminderFailed = true;
      }
    }

    return ApplyExamRescuePlanResult(
      success: true,
      sessionId: sessionId,
      taskIds: taskIds,
      tasksCount: materializedTasks.length,
      reminderFailed: reminderFailed,
    );
  }
}
