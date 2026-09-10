import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tri-state result for [FirestoreService.checkProfileState].
///
/// Distinguishes "profile exists" from "profile missing" from
/// "profile lookup error" — critical for the post-OTP auth
/// completion path (PART 30) where a network error must NOT be
/// misinterpreted as "no profile → ProfileSetupScreen".
enum ProfileCheckResult {
  /// Profile document exists with a non-empty `displayName`.
  /// Route to Home.
  exists,

  /// No `users/{uid}` document, or `displayName` is empty/null.
  /// Route to ProfileSetupScreen.
  missing,

  /// Firestore read failed (network, permission, timeout).
  /// Treat as a recoverable post-auth failure — do NOT route
  /// to ProfileSetupScreen.
  error,
}

class FirestoreService {
  FirestoreService._();

  static final db = FirebaseFirestore.instance;

  static String? get uid {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  static List<String> keywords(String text, {int limit = 100}) {
    final words = RegExp(r'[A-Za-z0-9\u0980-\u09FF]+')
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .where((e) => e.length >= 2);
    final seen = <String>{};
    final result = <String>[];
    for (final word in words) {
      if (seen.add(word)) {
        result.add(word);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream() {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<DocumentSnapshot<Map<String, dynamic>>>.fromFuture(
        db.collection('users').limit(0).get().then((s) => s.docs.first),
      );
    }
    return db.collection('users').doc(currentUid).snapshots();
  }

  /// Writes profile fields to the user's Firestore document.
  ///
  /// Only the keys present in [fields] are written — unknown keys are
  /// ignored and missing keys are never set to null.  This prevents
  /// accidental data loss when a caller only wants to update a subset
  /// of fields (e.g. only `photoURL` after a photo upload).
  static Future<void> updateProfile(Map<String, dynamic> fields) async {
    const allowed = {
      'displayName',
      'university',
      'department',
      'photoURL',
      'nickname',
    };
    final patch = <String, dynamic>{};
    for (final key in allowed) {
      if (fields.containsKey(key)) {
        patch[key] = fields[key];
      }
    }
    if (patch.isEmpty) return;
    final currentUid = uid;
    if (currentUid == null) return;
    await db.collection('users').doc(currentUid).set(
          patch,
          SetOptions(merge: true),
        );
  }

  static Future<Map<String, dynamic>> profile() async {
    final currentUid = uid;
    if (currentUid == null) return {};
    final snap = await db.collection('users').doc(currentUid).get();
    return snap.data() ?? {};
  }

  /// Returns `true` when the current Firebase user has a `users/{uid}`
  /// document with a non-empty `displayName`.  Used after telecom
  /// authentication to decide whether to show the home shell or the
  /// profile-setup screen.
  ///
  /// NOTE: This method conflates "profile genuinely missing" with
  /// "network/permission error" — both return `false`. For the
  /// post-OTP auth completion path (PART 30), use [checkProfileState]
  /// instead, which distinguishes the three cases.
  static Future<bool> hasProfile() async {
    final currentUid = uid;
    if (currentUid == null) return false;
    try {
      final snap = await db.collection('users').doc(currentUid).get();
      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;
      final name = data['displayName']?.toString().trim();
      return name != null && name.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Tri-state profile check for the post-OTP auth completion path.
  ///
  /// Unlike [hasProfile], this method distinguishes:
  /// - [ProfileCheckResult.exists] — profile document has a non-empty
  ///   `displayName`. Route to Home.
  /// - [ProfileCheckResult.missing] — no `users/{uid}` document, or
  ///   `displayName` is empty/null. Route to ProfileSetupScreen.
  /// - [ProfileCheckResult.error] — Firestore read failed (network,
  ///   permission, timeout). Treat as a recoverable post-auth failure;
  ///   do NOT route to ProfileSetupScreen.
  static Future<ProfileCheckResult> checkProfileState() async {
    final currentUid = uid;
    if (currentUid == null) return ProfileCheckResult.error;
    try {
      final snap = await db.collection('users').doc(currentUid).get();
      if (!snap.exists) return ProfileCheckResult.missing;
      final data = snap.data();
      if (data == null) return ProfileCheckResult.missing;
      final name = data['displayName']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        return ProfileCheckResult.exists;
      }
      return ProfileCheckResult.missing;
    } catch (_) {
      return ProfileCheckResult.error;
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> ownerStream(
    String collection, {
    int limit = 100,
  }) {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.fromFuture(
        db.collection(collection).limit(0).get(),
      );
    }
    return db
        .collection(collection)
        .where('ownerId', isEqualTo: currentUid)
        .limit(limit)
        .snapshots();
  }

  static Future<DocumentReference<Map<String, dynamic>>> addOwnerRecord(
    String collection,
    Map<String, dynamic> data,
  ) {
    final currentUid = uid;
    if (currentUid == null) {
      throw Exception('Not signed in. Cannot add record.');
    }
    return db.collection(collection).add({
      ...data,
      'ownerId': currentUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> myGroups() {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.fromFuture(
        db.collection('groups').limit(0).get(),
      );
    }
    return db
        .collection('groups')
        .where('memberIds', arrayContains: currentUid)
        .limit(50)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> groupMaterials(String groupId) {
    return db
        .collection('materials')
        .where('groupId', isEqualTo: groupId)
        .where('visibility', isEqualTo: 'group')
        .limit(100)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> groupNotes(String groupId) {
    return db
        .collection('notes')
        .where('groupId', isEqualTo: groupId)
        .where('visibility', isEqualTo: 'group')
        .limit(100)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> groupMessages(String groupId) {
    return db
        .collection('group_messages')
        .where('groupId', isEqualTo: groupId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  // ---------------------------------------------------------------------------
  // Group Projects
  // ---------------------------------------------------------------------------

  static Stream<QuerySnapshot<Map<String, dynamic>>> groupProjects(String groupId) {
    return db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> projectTasks(
    String groupId,
    String projectId,
  ) {
    return db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .collection('tasks')
        .orderBy('createdAt')
        .snapshots();
  }

  static Future<DocumentReference<Map<String, dynamic>>> createProject({
    required String groupId,
    required String name,
    String? description,
  }) async {
    final userProfile = await profile();
    return db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .add({
      'name': name.trim(),
      'description': description?.trim() ?? '',
      'createdBy': uid,
      'createdByName': userProfile['displayName']?.toString() ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateProject({
    required String groupId,
    required String projectId,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteProject({
    required String groupId,
    required String projectId,
  }) async {
    // Delete all tasks first
    final tasks = await db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .collection('tasks')
        .get();
    for (final doc in tasks.docs) {
      await doc.reference.delete();
    }
    await db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .delete();
  }

  static Future<DocumentReference<Map<String, dynamic>>> createTask({
    required String groupId,
    required String projectId,
    required String title,
    String? description,
    String? assigneeId,
    DateTime? deadline,
  }) async {
    final userProfile = await profile();
    return db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .collection('tasks')
        .add({
      'title': title.trim(),
      'description': description?.trim() ?? '',
      'assigneeId': assigneeId,
      'completed': false,
      'createdBy': uid,
      'createdByName': userProfile['displayName']?.toString() ?? '',
      'deadline': deadline,
      'reminderByUser': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateTask({
    required String groupId,
    required String projectId,
    required String taskId,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .collection('tasks')
        .doc(taskId)
        .update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteTask({
    required String groupId,
    required String projectId,
    required String taskId,
  }) async {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .collection('tasks')
        .doc(taskId)
        .delete();
  }

  /// Sets or clears a per-user reminder on a community task.
  ///
  /// [reminderAt] is a [DateTime] for the reminder, or `null` to clear it.
  /// The entry is stored under `reminderByUser.<userId>` so each member's
  /// reminder is independent and reassignment does not overwrite others.
  static Future<void> setTaskReminder({
    required String groupId,
    required String projectId,
    required String taskId,
    required String userId,
    DateTime? reminderAt,
  }) async {
    final field = 'reminderByUser.$userId';
    await db
        .collection('groups')
        .doc(groupId)
        .collection('projects')
        .doc(projectId)
        .collection('tasks')
        .doc(taskId)
        .update({
      field: reminderAt,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> saveNote({
    String? id,
    required String title,
    required String content,
    required String visibility,
    String? groupId,
    String? semesterId,
    String? subjectId,
    String? relatedTaskId,
    String? relatedMaterialId,
  }) async {
    final currentUid = uid;
    if (currentUid == null) {
      throw Exception('Not signed in. Cannot save note.');
    }
    final userProfile = await profile();
    final data = {
      'ownerId': currentUid,
      'ownerName': userProfile['displayName']?.toString() ?? '',
      'title': title.trim(),
      'content': content.trim(),
      'visibility': visibility,
      'groupId': visibility == 'group' ? groupId : null,
      'semesterId': semesterId,
      'subjectId': subjectId,
      'university': userProfile['university']?.toString() ?? '',
      'department': userProfile['department']?.toString() ?? '',
      'semester': userProfile['semester']?.toString() ?? '',
      'keywords': keywords('$title $content'),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Optional cross-module relationships (Phase 5).
    if (relatedTaskId != null) data['relatedTaskId'] = relatedTaskId;
    if (relatedMaterialId != null) {
      data['relatedMaterialId'] = relatedMaterialId;
    }
    if (id == null) {
      await db.collection('notes').add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await db.collection('notes').doc(id).update(data);
    }
  }

  static Future<void> deleteOwnerDocument(String collection, String id) {
    return db.collection(collection).doc(id).delete();
  }
}
