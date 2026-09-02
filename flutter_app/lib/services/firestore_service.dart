import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  FirestoreService._();

  static final db = FirebaseFirestore.instance;

  static String get uid {
    final value = FirebaseAuth.instance.currentUser?.uid;
    if (value == null) throw Exception('Not signed in.');
    return value;
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
    return db.collection('users').doc(uid).snapshots();
  }

  /// Updates the signed-in student's own profile fields.
  ///
  /// Deliberately narrow: only the three fields the Profile screen displays.
  /// `role` is never written, which the security rules require anyway --
  /// `allow update` refuses any write that changes it.
  static Future<void> updateProfile({
    required String displayName,
    required String university,
    required String department,
  }) {
    return db.collection('users').doc(uid).update({
      'displayName': displayName,
      'university': university,
      'department': department,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, dynamic>> profile() async {
    final snap = await db.collection('users').doc(uid).get();
    return snap.data() ?? {};
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> ownerStream(
    String collection, {
    int limit = 100,
  }) {
    return db
        .collection(collection)
        .where('ownerId', isEqualTo: uid)
        .limit(limit)
        .snapshots();
  }

  static Future<DocumentReference<Map<String, dynamic>>> addOwnerRecord(
    String collection,
    Map<String, dynamic> data,
  ) {
    return db.collection(collection).add({
      ...data,
      'ownerId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> myGroups() {
    return db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
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

  static Future<void> saveNote({
    String? id,
    required String title,
    required String content,
    required String visibility,
    String? groupId,
    String? semesterId,
    String? subjectId,
  }) async {
    final userProfile = await profile();
    final data = {
      'ownerId': uid,
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
