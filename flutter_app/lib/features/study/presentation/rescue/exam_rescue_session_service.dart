// Phase T5/T6 — Exam Rescue Session Service
//
// Streams active Exam Rescue sessions for the current authenticated user.
// Multiplexes snapshot listeners via a shared broadcast stream per UID to
// prevent duplicate Firestore subscriptions across mounted shell tabs
// (Home, Workspace, PlanView in IndexedStack).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../services/firestore_service.dart';

class ExamRescueSessionService {
  final FirebaseFirestore? _firestore;
  final String? Function()? _getUid;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(String uid)?
  _streamFactory;

  ExamRescueSessionService({
    FirebaseFirestore? firestore,
    String? Function()? getUid,
    Stream<QuerySnapshot<Map<String, dynamic>>> Function(String uid)?
    streamFactory,
  }) : _firestore = firestore,
       _getUid = getUid,
       _streamFactory = streamFactory;

  FirebaseFirestore get firestore => _firestore ?? FirestoreService.db;
  String? get uid => _getUid != null ? _getUid() : FirestoreService.uid;

  // Cached broadcast streams per UID to multiplex a single Firestore snapshot listener
  static final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
  _activeStreams = {};

  /// Streams the user's active exam rescue sessions.
  ///
  /// When [shareStream] is true (default), returns a shared broadcast stream
  /// so that multiple mounted tabs (Home, Workspace, PlanView) share a SINGLE
  /// underlying Firestore snapshot listener instead of creating redundant connections.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamActiveSessions({
    bool shareStream = true,
  }) {
    final effectiveUid = uid;
    if (effectiveUid == null || effectiveUid.isEmpty) {
      return const Stream.empty();
    }

    if (shareStream && _activeStreams.containsKey(effectiveUid)) {
      return _activeStreams[effectiveUid]!;
    }

    final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
    if (_streamFactory != null) {
      stream = _streamFactory(effectiveUid).asBroadcastStream();
    } else {
      final query = firestore
          .collection('users')
          .doc(effectiveUid)
          .collection('exam_rescue')
          .where('status', isEqualTo: 'active')
          .limit(10);
      stream = query.snapshots().asBroadcastStream();
    }

    if (shareStream) {
      _activeStreams[effectiveUid] = stream;
    }
    return stream;
  }

  /// Clears cached broadcast streams (e.g. on logout or between tests).
  static void clearStreamCache() {
    _activeStreams.clear();
  }

  /// Returns true if an active broadcast stream is currently cached for [uid].
  static bool hasCachedStream(String uid) {
    return _activeStreams.containsKey(uid);
  }
}
