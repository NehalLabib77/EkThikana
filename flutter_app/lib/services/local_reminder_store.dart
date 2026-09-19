import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/local_reminder.dart';

/// Local-first persistent repository for reminders.
///
/// Stores reminders on-device in `reminders_manifest.json` via path_provider.
/// Operates 100% offline with no reliance on Firebase, network availability,
/// or external servers.
class LocalReminderStore {
  LocalReminderStore._();

  static final LocalReminderStore instance = LocalReminderStore._();

  static const String _kManifestFileName = 'reminders_manifest.json';

  final List<LocalReminder> _reminders = [];
  final ValueNotifier<List<LocalReminder>> remindersNotifier =
      ValueNotifier<List<LocalReminder>>(<LocalReminder>[]);
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  bool _initialized = false;
  File? _overrideFile;

  @visibleForTesting
  void setTestFile(File file) {
    _overrideFile = file;
    _initialized = false;
  }

  @visibleForTesting
  void resetForTesting([List<LocalReminder>? initial]) {
    _reminders.clear();
    if (initial != null) {
      _reminders.addAll(initial);
    }
    _initialized = true;
    _notify();
  }

  Future<File> _getFile() async {
    if (_overrideFile != null) return _overrideFile!;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_kManifestFileName');
    } catch (_) {
      // Fallback for unit testing environments without path_provider mock
      return File('./$_kManifestFileName');
    }
  }

  /// Initialize and load reminders from disk.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            _reminders.clear();
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                _reminders.add(LocalReminder.fromJson(item));
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalReminderStore] Failed to load reminders: $e');
      }
    } finally {
      _initialized = true;
      _notify();
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _getFile();
      final jsonList = _reminders.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalReminderStore] Failed to persist reminders: $e');
      }
    }
  }

  void _notify() {
    // Sort primarily by scheduled date (upcoming first)
    _reminders.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    remindersNotifier.value = List.unmodifiable(_reminders);
    unreadCountNotifier.value = _reminders
        .where((r) => !r.isRead && r.isPending)
        .length;
  }

  /// Save or update a reminder locally.
  Future<void> save(LocalReminder reminder) async {
    await init();
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index >= 0) {
      _reminders[index] = reminder.copyWith(updatedAt: DateTime.now());
    } else {
      _reminders.add(reminder);
    }
    _notify();
    await _persist();
  }

  /// Save multiple reminders.
  Future<void> saveAll(List<LocalReminder> items) async {
    await init();
    for (final reminder in items) {
      final index = _reminders.indexWhere((r) => r.id == reminder.id);
      if (index >= 0) {
        _reminders[index] = reminder.copyWith(updatedAt: DateTime.now());
      } else {
        _reminders.add(reminder);
      }
    }
    _notify();
    await _persist();
  }

  /// Find reminder by its unique reminder ID.
  LocalReminder? findById(String id) {
    try {
      return _reminders.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Alias for findById.
  LocalReminder? getById(String id) => findById(id);

  /// Find reminder by the domain object ID it was created for.
  LocalReminder? findByOwnerItemId(String ownerItemId) {
    try {
      return _reminders.firstWhere((r) => r.ownerItemId == ownerItemId);
    } catch (_) {
      return null;
    }
  }

  /// Find all reminders for a given domain item ID.
  List<LocalReminder> findAllByOwnerItemId(String ownerItemId) {
    return _reminders.where((r) => r.ownerItemId == ownerItemId).toList();
  }

  /// Returns all stored reminders.
  List<LocalReminder> getAll() {
    return List.unmodifiable(_reminders);
  }

  /// Returns all pending reminders.
  List<LocalReminder> getPending() {
    return _reminders
        .where((r) => r.status == LocalReminderStatus.pending)
        .toList();
  }

  /// Returns all future pending or repeating reminders needed for OS reconciliation.
  List<LocalReminder> getReconcilableReminders() {
    final now = DateTime.now();
    return _reminders.where((r) {
      if (r.recurrence == LocalReminderRecurrence.daily) {
        return r.status != LocalReminderStatus.cancelled;
      }
      if (r.status != LocalReminderStatus.pending) return false;
      // Allow reminders up to 30 mins past due
      return r.scheduledAt.add(const Duration(minutes: 30)).isAfter(now);
    }).toList();
  }

  /// Returns historical reminders (completed, skipped, or cancelled).
  List<LocalReminder> getHistory() {
    return _reminders
        .where((r) => r.status != LocalReminderStatus.pending)
        .toList();
  }

  /// Update the status of a reminder by its ID.
  Future<void> updateStatus(
    String id,
    LocalReminderStatus status, {
    DateTime? completedAt,
  }) async {
    await init();
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index >= 0) {
      final existing = _reminders[index];
      _reminders[index] = existing.copyWith(
        status: status,
        updatedAt: DateTime.now(),
        completedAt:
            completedAt ??
            (status == LocalReminderStatus.completed ? DateTime.now() : null),
      );
      _notify();
      await _persist();
    }
  }

  /// Update the status of all reminders associated with a domain item ID.
  Future<void> updateStatusByOwnerItemId(
    String ownerItemId,
    LocalReminderStatus status, {
    DateTime? completedAt,
  }) async {
    await init();
    var changed = false;
    for (var i = 0; i < _reminders.length; i++) {
      if (_reminders[i].ownerItemId == ownerItemId) {
        _reminders[i] = _reminders[i].copyWith(
          status: status,
          updatedAt: DateTime.now(),
          completedAt:
              completedAt ??
              (status == LocalReminderStatus.completed ? DateTime.now() : null),
        );
        changed = true;
      }
    }
    if (changed) {
      _notify();
      await _persist();
    }
  }

  /// Mark a single reminder as read.
  Future<void> markAsRead(String id) async {
    await init();
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index >= 0 && !_reminders[index].isRead) {
      _reminders[index] = _reminders[index].copyWith(
        isRead: true,
        updatedAt: DateTime.now(),
      );
      _notify();
      await _persist();
    }
  }

  /// Mark all reminders as read.
  Future<void> markAllAsRead() async {
    await init();
    var changed = false;
    for (var i = 0; i < _reminders.length; i++) {
      if (!_reminders[i].isRead) {
        _reminders[i] = _reminders[i].copyWith(
          isRead: true,
          updatedAt: DateTime.now(),
        );
        changed = true;
      }
    }
    if (changed) {
      _notify();
      await _persist();
    }
  }

  /// Delete a reminder by its ID.
  Future<void> delete(String id) async {
    await init();
    final countBefore = _reminders.length;
    _reminders.removeWhere((r) => r.id == id);
    if (_reminders.length != countBefore) {
      _notify();
      await _persist();
    }
  }

  /// Delete all reminders matching an ownerItemId.
  Future<void> deleteByOwnerItemId(String ownerItemId) async {
    await init();
    final countBefore = _reminders.length;
    _reminders.removeWhere((r) => r.ownerItemId == ownerItemId);
    if (_reminders.length != countBefore) {
      _notify();
      await _persist();
    }
  }

  /// Clear all stored reminders.
  Future<void> clear() async {
    _reminders.clear();
    _notify();
    await _persist();
  }
}
