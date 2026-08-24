import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService._();

  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore db = FirebaseFirestore.instance;

  static Stream<User?> authState() => auth.authStateChanges();

  static Future<void> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String university = '',
    String department = '',
    String semester = '',
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw Exception('Account creation failed.');
    }

    await user.updateDisplayName(name.trim());
    await db.collection('users').doc(user.uid).set({
      'displayName': name.trim(),
      'email': email.trim().toLowerCase(),
      'role': role,
      'university': role == 'student' ? university.trim() : '',
      'department': role == 'student' ? department.trim() : '',
      'semester': role == 'student' ? semester.trim() : '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await user.sendEmailVerification();
  }

  static Future<void> login(String email, String password) async {
    final credential = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  static Future<void> reloadUser() async {
    await auth.currentUser?.reload();
  }

  static Future<void> logout() => auth.signOut();

  static Future<void> sendPasswordReset(String email) {
    return auth.sendPasswordResetEmail(email: email.trim());
  }
}
