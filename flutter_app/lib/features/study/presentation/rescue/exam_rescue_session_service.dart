// Phase T5/T6/T7 — Exam Rescue Session Service
//
// Streams active Exam Rescue sessions for the current authenticated user.
//
// Multiplexing contract (Phase T6.6 listener audit, hardened in T7):
//   * One shared broadcast stream per UID, so Home / Workspace / PlanView
//     inside the shell's IndexedStack share a SINGLE Firestore listener.
//   * The shared stream is backed by our own `StreamController.broadcast`
//     (not `source.asBroadcastStream()`), because Dart's `_AsBroadcastStream`
//     permanently becomes un-listenable once its last subscriber cancels —
//     which happened every time Study/Utility mode switched and rebuilt the
//     tab tree, leaving the surfaces permanently stuck on "no session".
//   * The cache is scoped to ONE uid at a time: when the signed-in user
//     changes, every previous account's listener is cancelled and dropped
//     (no cross-account reuse, no unbounded static cache growth).
//   * Both `streamActiveSessions()` and `streamNearestActiveSession()` return
//     the SAME object for a given UID (stable reference identity) and replay
//     the latest value to listeners that attach after a zero-listener gap.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../services/firestore_service.dart';
import 'exam_rescue_models.dart';

typedef _SessionList = List<ExamRescueSession>;

/// One multiplexed source listener feeding broadcast streams that every UI
/// surface can subscribe to independently.
class _SharedSessionStream {
  _SharedSessionStream(Stream<_SessionList> source) : _source = source {
    _sessionsController = StreamController<_SessionList>.broadcast(
      onListen: _onListenSessions,
    );
    _nearestController = StreamController<ExamRescueSession?>.broadcast(
      onListen: _onListenNearest,
    );
    // `StreamController.stream` allocates a fresh wrapper per getter call, so
    // the objects handed to callers are pinned here for identity stability.
    sessionsStream = _sessionsController.stream;
    nearestStream = _nearestController.stream;
  }

  final Stream<_SessionList> _source;

  late final StreamController<_SessionList> _sessionsController;
  late final StreamController<ExamRescueSession?> _nearestController;

  /// The shared session-list stream (same object on every call).
  late final Stream<_SessionList> sessionsStream;

  /// The shared nearest-session stream (same object on every call).
  late final Stream<ExamRescueSession?> nearestStream;

  StreamSubscription<_SessionList>? _sub;
  _SessionList? _latestSessions;
  ExamRescueSession? _latestNearest;
  var _latestKnown = false;

  void _ensureSource() {
    _sub ??= _source.listen(_onData, onError: _onError, onDone: _onDone);
  }

  void _onListenSessions() {
    _ensureSource();
    final latest = _latestSessions;
    if (_latestKnown && latest != null && !_sessionsController.isClosed) {
      _sessionsController.add(latest);
    }
  }

  void _onListenNearest() {
    _ensureSource();
    if (_latestKnown && !_nearestController.isClosed) {
      _nearestController.add(_latestNearest);
    }
  }

  void _onData(_SessionList sessions) {
    _latestSessions = sessions;
    _latestNearest = _nearestOf(sessions);
    _latestKnown = true;
    if (_sessionsController.hasListener && !_sessionsController.isClosed) {
      _sessionsController.add(sessions);
    }
    if (_nearestController.hasListener && !_nearestController.isClosed) {
      _nearestController.add(_latestNearest);
    }
  }

  void _onError(Object error, StackTrace stack) {
    if (_sessionsController.hasListener && !_sessionsController.isClosed) {
      _sessionsController.addError(error, stack);
    }
    if (_nearestController.hasListener && !_nearestController.isClosed) {
      _nearestController.addError(error, stack);
    }
  }

  void _onDone() {
    if (!_sessionsController.isClosed) _sessionsController.close();
    if (!_nearestController.isClosed) _nearestController.close();
  }

  static ExamRescueSession? _nearestOf(_SessionList sessions) {
    if (sessions.isEmpty) return null;
    final sorted = [...sessions]
      ..sort((a, b) => a.examDate.compareTo(b.examDate));
    return sorted.first;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    if (!_sessionsController.isClosed) _sessionsController.close();
    if (!_nearestController.isClosed) _nearestController.close();
  }
}

class ExamRescueSessionService {
  final FirebaseFirestore? _firestore;
  final String? Function()? _getUid;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(String uid)?
  _streamFactory;
  final DateTime Function()? _now;

  ExamRescueSessionService({
    FirebaseFirestore? firestore,
    String? Function()? getUid,
    Stream<QuerySnapshot<Map<String, dynamic>>> Function(String uid)?
    streamFactory,
    DateTime Function()? now,
  }) : _firestore = firestore,
       _getUid = getUid,
       _streamFactory = streamFactory,
       _now = now;

  /// App-wide singleton used by the production surfaces (Home, Workspace, Plan)
  /// so all three share one listener.
  static final ExamRescueSessionService instance = ExamRescueSessionService();

  FirebaseFirestore get firestore => _firestore ?? FirestoreService.db;
  String? get uid => _getUid != null ? _getUid() : FirestoreService.uid;
  DateTime get now => _now != null ? _now() : DateTime.now();

  static final Map<String, _SharedSessionStream> _activeStreams = {};

  /// UID that owns the currently cached entry. Only ever one owner: switching
  /// accounts tears the previous listener down.
  static String? _cacheOwnerUid;

  /// Builds the underlying Firestore (or injected) snapshot stream.
  Stream<QuerySnapshot<Map<String, dynamic>>> _openSnapshotStream(String uid) {
    if (_streamFactory != null) return _streamFactory(uid);
    return firestore
        .collection('users')
        .doc(uid)
        .collection('exam_rescue')
        .where('status', isEqualTo: 'active')
        .limit(10)
        .snapshots();
  }

  /// Sessions visible to the user, filtered by eligibility (status `active`
  /// and exam today or later) so expired / completed / cancelled sessions are
  /// never surfaced by Home, Workspace or Plan.
  _SessionList _visibleSessions(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final nowRef = now;
    final sessions = <ExamRescueSession>[];
    for (final doc in snapshot.docs) {
      final session = ExamRescueSession.fromFirestore(doc.id, doc.data());
      if (session.isEligibleActive(nowRef)) sessions.add(session);
    }
    sessions.sort((a, b) => a.examDate.compareTo(b.examDate));
    return sessions;
  }

  _SharedSessionStream _entryFor(String uid) {
    if (_cacheOwnerUid != uid) {
      // Auth switch: never reuse (or keep alive) another account's listener.
      clearStreamCache();
      _cacheOwnerUid = uid;
    }
    final existing = _activeStreams[uid];
    if (existing != null) return existing;

    final entry = _SharedSessionStream(
      _openSnapshotStream(uid).map(_visibleSessions),
    );
    _activeStreams[uid] = entry;
    return entry;
  }

  /// Streams the user's eligible active exam rescue sessions.
  ///
  /// All mounted surfaces receive the same broadcast stream, so a single
  /// underlying Firestore listener serves Home, Workspace and PlanView.
  Stream<List<ExamRescueSession>> streamActiveSessions() {
    final effectiveUid = uid;
    if (effectiveUid == null || effectiveUid.isEmpty) {
      return Stream<_SessionList>.value(const []);
    }
    return _entryFor(effectiveUid).sessionsStream;
  }

  /// The single nearest active session (earliest upcoming exam), or null when
  /// no eligible session exists.
  Stream<ExamRescueSession?> streamNearestActiveSession() {
    final effectiveUid = uid;
    if (effectiveUid == null || effectiveUid.isEmpty) {
      return Stream<ExamRescueSession?>.value(null);
    }
    return _entryFor(effectiveUid).nearestStream;
  }

  /// Today's progress for [session] derived from real task documents.
  ///
  /// Only tasks that belong to [session] (same `rescueSessionId` and
  /// `source == 'exam_rescue'`) are counted — progress is never merged across
  /// rescue sessions, and the overall totals cover every day of the plan.
  static ExamRescueTodayProgress calculateTodayProgress({
    required ExamRescueSession session,
    required List<Map<String, dynamic>> tasks,
    required DateTime now,
  }) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    var overallTotal = 0;
    var overallCompleted = 0;
    var todayTotal = 0;
    var todayCompleted = 0;
    var todayMinutes = 0;

    for (final task in tasks) {
      if (task['source'] != 'exam_rescue') continue;
      final taskSessionId = task['rescueSessionId']?.toString() ?? '';
      if (taskSessionId.isEmpty || taskSessionId != session.sessionId) continue;

      final done = task['done'] == true || task['isCompleted'] == true;
      overallTotal++;
      if (done) overallCompleted++;

      final due = _asLocalDateTime(task['dueAt'] ?? task['dueDate']);
      if (due == null) continue;
      if (due.isBefore(todayStart) || due.isAfter(todayEnd)) continue;

      todayTotal++;
      if (done) todayCompleted++;
      final minutes = task['estimatedMinutes'];
      if (minutes is num) todayMinutes += minutes.toInt();
    }

    return ExamRescueTodayProgress(
      overallTotal: overallTotal,
      overallCompleted: overallCompleted,
      todayTotal: todayTotal,
      todayCompleted: todayCompleted,
      todayPlannedMinutes: todayMinutes,
    );
  }

  static DateTime? _asLocalDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return null;
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }
    try {
      final dynamic timestamp = value;
      return (timestamp.toDate() as DateTime).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Clears cached broadcast streams and cancels their Firestore listeners
  /// (on logout, between tests, or when the authenticated UID changes).
  static void clearStreamCache() {
    for (final entry in _activeStreams.values) {
      entry.dispose();
    }
    _activeStreams.clear();
    _cacheOwnerUid = null;
  }

  /// Returns true if a shared stream is currently cached for [uid].
  static bool hasCachedStream(String uid) => _activeStreams.containsKey(uid);
}
