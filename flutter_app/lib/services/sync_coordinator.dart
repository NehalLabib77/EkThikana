import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'firestore_service.dart';

enum SyncStatus { synced, offline, pending, syncing, error }

@immutable
class SyncPendingItem {
  const SyncPendingItem({
    required this.id,
    required this.collection,
    required this.type,
    required this.title,
    this.timestamp,
  });

  final String id;
  final String collection;
  final String type; // 'task' | 'medicine' | 'expense' | 'trip'
  final String title;
  final DateTime? timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncPendingItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          collection == other.collection;

  @override
  int get hashCode => id.hashCode ^ collection.hashCode;
}

@immutable
class SyncState {
  const SyncState({
    required this.status,
    required this.isOnline,
    required this.pendingCount,
    required this.pendingItems,
    this.lastSyncTime,
    this.errorMessage,
  });

  final SyncStatus status;
  final bool isOnline;
  final int pendingCount;
  final List<SyncPendingItem> pendingItems;
  final DateTime? lastSyncTime;
  final String? errorMessage;

  SyncState copyWith({
    SyncStatus? status,
    bool? isOnline,
    int? pendingCount,
    List<SyncPendingItem>? pendingItems,
    DateTime? lastSyncTime,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      pendingCount: pendingCount ?? this.pendingCount,
      pendingItems: pendingItems ?? this.pendingItems,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Coordinates and exposes sync status across Gochano's offline-capable domains.
///
/// Observes Cloud Firestore pending mutation queues via snapshot metadata
/// (`hasPendingWrites`) and network state via [ConnectivityService].
class SyncCoordinator {
  SyncCoordinator._();

  static final SyncCoordinator instance = SyncCoordinator._();

  final ValueNotifier<SyncState> syncState = ValueNotifier<SyncState>(
    const SyncState(
      status: SyncStatus.synced,
      isOnline: true,
      pendingCount: 0,
      pendingItems: <SyncPendingItem>[],
    ),
  );

  final Map<String, List<SyncPendingItem>> _pendingByCollection = {};
  final List<StreamSubscription> _subscriptions = [];
  bool _initialized = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  /// Start observing connectivity and Firestore pending write streams.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Listen to network transitions
    ConnectivityService.instance.online.addListener(_onConnectivityChanged);

    // Initial network state
    _recomputeState();

    // Start watching Firestore collection metadata
    _startWatchingCollections();
  }

  void _onConnectivityChanged() {
    _recomputeState();
  }

  void _startWatchingCollections() {
    try {
      final uid = FirestoreService.uid;
      if (uid == null) return;

      _watchCollection(
        collection: 'tasks',
        type: 'task',
        titleExtractor: (data) => (data['title']?.toString() ?? 'Task').trim(),
      );

      _watchCollection(
        collection: 'medicines',
        type: 'medicine',
        titleExtractor: (data) =>
            (data['name']?.toString() ?? 'Medicine').trim(),
      );

      _watchCollection(
        collection: 'daily_expenses',
        type: 'expense',
        titleExtractor: (data) =>
            (data['title']?.toString() ??
                    data['category']?.toString() ??
                    'Expense')
                .trim(),
      );

      _watchCollection(
        collection: 'planned_commute_trips',
        type: 'trip',
        titleExtractor: (data) =>
            (data['destinationName']?.toString() ?? 'Planned Trip').trim(),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SyncCoordinator] Error setting up collection watchers: $e',
        );
      }
    }
  }

  void _watchCollection({
    required String collection,
    required String type,
    required String Function(Map<String, dynamic> data) titleExtractor,
  }) {
    try {
      final uid = FirestoreService.uid;
      if (uid == null) return;

      final stream = FirestoreService.db
          .collection(collection)
          .where('ownerId', isEqualTo: uid)
          .snapshots(includeMetadataChanges: true);

      final sub = stream.listen(
        (snapshot) {
          final pendingInCol = <SyncPendingItem>[];
          for (final doc in snapshot.docs) {
            if (doc.metadata.hasPendingWrites) {
              final data = doc.data();
              final title = titleExtractor(data);
              final ts =
                  (data['updatedAt'] as Timestamp?)?.toDate() ??
                  (data['createdAt'] as Timestamp?)?.toDate();
              pendingInCol.add(
                SyncPendingItem(
                  id: doc.id,
                  collection: collection,
                  type: type,
                  title: title.isEmpty ? type : title,
                  timestamp: ts,
                ),
              );
            }
          }
          _pendingByCollection[collection] = pendingInCol;
          _recomputeState();
        },
        onError: (err) {
          if (kDebugMode) {
            debugPrint('[SyncCoordinator] Error in $collection stream: $err');
          }
        },
      );

      _subscriptions.add(sub);
    } catch (_) {
      // Ignored for environments without active Firestore
    }
  }

  void _recomputeState() {
    final isOnline = ConnectivityService.instance.online.value;

    final allPending = <SyncPendingItem>[];
    for (final list in _pendingByCollection.values) {
      allPending.addAll(list);
    }

    SyncStatus status;
    if (_isSyncing) {
      status = SyncStatus.syncing;
    } else if (!isOnline) {
      status = allPending.isNotEmpty ? SyncStatus.pending : SyncStatus.offline;
    } else if (allPending.isNotEmpty) {
      status = SyncStatus.pending;
    } else {
      status = SyncStatus.synced;
    }

    syncState.value = SyncState(
      status: status,
      isOnline: isOnline,
      pendingCount: allPending.length,
      pendingItems: List.unmodifiable(allPending),
      lastSyncTime: _lastSyncTime,
      errorMessage: syncState.value.errorMessage,
    );
  }

  /// Manually triggers synchronization with backend.
  ///
  /// Returns `true` if all pending writes were successfully acknowledged.
  /// If offline, fails immediately with a truthful error.
  Future<bool> syncNow({Duration timeout = const Duration(seconds: 8)}) async {
    final isOnline = ConnectivityService.instance.online.value;
    if (!isOnline) {
      syncState.value = syncState.value.copyWith(
        status: SyncStatus.error,
        errorMessage:
            'Cannot sync while offline. Please connect to the internet.',
      );
      return false;
    }

    _isSyncing = true;
    syncState.value = syncState.value.copyWith(
      status: SyncStatus.syncing,
      clearError: true,
    );

    try {
      // Real wait for Cloud Firestore pending mutation queue
      await FirestoreService.db.waitForPendingWrites().timeout(timeout);
      _lastSyncTime = DateTime.now();
      _isSyncing = false;
      _recomputeState();
      return true;
    } catch (e) {
      _isSyncing = false;
      syncState.value = syncState.value.copyWith(
        status: SyncStatus.error,
        errorMessage:
            'Sync in progress or timed out. Will retry automatically.',
      );
      return false;
    }
  }

  /// Disposes subscriptions.
  Future<void> dispose() async {
    ConnectivityService.instance.online.removeListener(_onConnectivityChanged);
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _pendingByCollection.clear();
    _initialized = false;
  }

  @visibleForTesting
  void debugSetState(SyncState state) {
    syncState.value = state;
  }

  @visibleForTesting
  void debugAddPendingItem(SyncPendingItem item) {
    final current = List<SyncPendingItem>.from(syncState.value.pendingItems);
    current.removeWhere(
      (e) => e.id == item.id && e.collection == item.collection,
    );
    current.add(item);
    _pendingByCollection.putIfAbsent(item.collection, () => []).add(item);

    final isOnline = syncState.value.isOnline;
    syncState.value = SyncState(
      status: isOnline ? SyncStatus.pending : SyncStatus.pending,
      isOnline: isOnline,
      pendingCount: current.length,
      pendingItems: List.unmodifiable(current),
      lastSyncTime: syncState.value.lastSyncTime,
      errorMessage: syncState.value.errorMessage,
    );
  }

  @visibleForTesting
  void debugClearPending() {
    _pendingByCollection.clear();
    _recomputeState();
  }

  @visibleForTesting
  void debugReset() {
    _pendingByCollection.clear();
    _isSyncing = false;
    _lastSyncTime = null;
    syncState.value = const SyncState(
      status: SyncStatus.synced,
      isOnline: true,
      pendingCount: 0,
      pendingItems: <SyncPendingItem>[],
    );
  }
}
