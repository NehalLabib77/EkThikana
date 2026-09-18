import 'package:flutter/foundation.dart';

/// Supported types of local-first offline reminders.
enum LocalReminderType {
  task,
  assignment,
  medicine,
  expenseDue,
  commuteTrip,
  custom;

  String get id => name;

  static LocalReminderType fromString(String? value) {
    for (final type in LocalReminderType.values) {
      if (type.name == value) return type;
    }
    return LocalReminderType.task;
  }
}

/// Lifecycle status of a local reminder.
enum LocalReminderStatus {
  pending,
  completed,
  skipped,
  cancelled,
  missed;

  String get id => name;

  static LocalReminderStatus fromString(String? value) {
    for (final status in LocalReminderStatus.values) {
      if (status.name == value) return status;
    }
    return LocalReminderStatus.pending;
  }
}

/// Recurrence pattern for repeating reminders.
enum LocalReminderRecurrence {
  none,
  daily;

  static LocalReminderRecurrence fromString(String? value) {
    for (final rec in LocalReminderRecurrence.values) {
      if (rec.name == value) return rec;
    }
    return LocalReminderRecurrence.none;
  }
}

/// Immutable representation of a persisted local reminder.
///
/// Designed to contain enough information to reconstruct and reconcile OS alarms
/// completely offline, survived across device reboots and app restarts.
@immutable
class LocalReminder {
  const LocalReminder({
    required this.id,
    required this.ownerItemId,
    required this.type,
    required this.title,
    this.body = '',
    required this.scheduledAt,
    this.offsets = const [0],
    this.notificationIds = const [],
    this.recurrence = LocalReminderRecurrence.none,
    this.status = LocalReminderStatus.pending,
    this.isRead = false,
    this.payload = const {},
    required this.createdAt,
    DateTime? updatedAt,
    this.completedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String ownerItemId;
  final LocalReminderType type;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final List<int> offsets;
  final List<int> notificationIds;
  final LocalReminderRecurrence recurrence;
  final LocalReminderStatus status;
  final bool isRead;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isPending => status == LocalReminderStatus.pending;
  bool get isCompleted => status == LocalReminderStatus.completed;
  bool get isSkipped => status == LocalReminderStatus.skipped;
  bool get isCancelled => status == LocalReminderStatus.cancelled;
  bool get isDaily => recurrence == LocalReminderRecurrence.daily;

  LocalReminder copyWith({
    String? id,
    String? ownerItemId,
    LocalReminderType? type,
    String? title,
    String? body,
    DateTime? scheduledAt,
    List<int>? offsets,
    List<int>? notificationIds,
    LocalReminderRecurrence? recurrence,
    LocalReminderStatus? status,
    bool? isRead,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return LocalReminder(
      id: id ?? this.id,
      ownerItemId: ownerItemId ?? this.ownerItemId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      offsets: offsets ?? this.offsets,
      notificationIds: notificationIds ?? this.notificationIds,
      recurrence: recurrence ?? this.recurrence,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerItemId': ownerItemId,
      'type': type.name,
      'title': title,
      'body': body,
      'scheduledAt': scheduledAt.toIso8601String(),
      'offsets': offsets,
      'notificationIds': notificationIds,
      'recurrence': recurrence.name,
      'status': status.name,
      'isRead': isRead,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    };
  }

  factory LocalReminder.fromJson(Map<String, dynamic> json) {
    return LocalReminder(
      id: json['id']?.toString() ?? '',
      ownerItemId: json['ownerItemId']?.toString() ?? '',
      type: LocalReminderType.fromString(json['type']?.toString()),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      scheduledAt:
          DateTime.tryParse(json['scheduledAt']?.toString() ?? '') ??
          DateTime.now(),
      offsets:
          (json['offsets'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [0],
      notificationIds:
          (json['notificationIds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      recurrence: LocalReminderRecurrence.fromString(
        json['recurrence']?.toString(),
      ),
      status: LocalReminderStatus.fromString(json['status']?.toString()),
      isRead: json['isRead'] == true,
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalReminder && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
