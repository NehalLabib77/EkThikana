// Firestore-backed reward persistence and idempotent grant logic.
//
// Architecture:
// - users/{uid}/reward_profile  — single document with totalXp, gems, level
// - users/{uid}/reward_transactions — append-only ledger of reward events
// - users/{uid}/reward_daily/{dateKey} — daily gem cap tracking
//
// The grant operation is idempotent: calling it twice with the same
// focusSessionId produces at most one reward entry.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/daily_gem_cap.dart';
import '../domain/level_helper.dart';
import '../domain/reaction_catalog.dart';
import '../domain/reward_model.dart';
import '../domain/xp_reward_mapper.dart';

class RewardService {
  RewardService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>> _profileCollection() =>
      FirebaseFirestore.instance.collection('users');

  static DocumentReference<Map<String, dynamic>> _profileDoc() {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    return _profileCollection().doc(uid);
  }

  static CollectionReference<Map<String, dynamic>> _transactionsCollection() {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    return _profileCollection().doc(uid).collection('reward_transactions');
  }

  static DocumentReference<Map<String, dynamic>> _dailyDoc(String dateKey) {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    return _profileCollection()
        .doc(uid)
        .collection('reward_daily')
        .doc(dateKey);
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Streams the user's reward profile. Emits [RewardProfile.empty] when
  /// the document does not exist yet.
  static Stream<RewardProfile> profileStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(RewardProfile.empty());
    return _profileDoc().snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return RewardProfile.empty();
      final xp = (data['totalXp'] as num?)?.toInt() ?? 0;
      return RewardProfile.fromMap(data).copyWith(
        level: levelForXp(xp),
      );
    });
  }

  /// One-shot read of the reward profile.
  static Future<RewardProfile> readProfile() async {
    final uid = _uid;
    if (uid == null) return RewardProfile.empty();
    final snap = await _profileDoc().get();
    final data = snap.data();
    if (data == null) return RewardProfile.empty();
    final xp = (data['totalXp'] as num?)?.toInt() ?? 0;
    return RewardProfile.fromMap(data).copyWith(
      level: levelForXp(xp),
    );
  }

  /// Reads today's total gem earnings from the daily cap document.
  static Future<int> readDailyGemsEarned() async {
    final dateKey = todayKey();
    final snap = await _dailyDoc(dateKey).get();
    final data = snap.data();
    return (data?['gems'] as num?)?.toInt() ?? 0;
  }

  /// Reads recent reward transactions, most recent first.
  static Future<List<RewardTransaction>> readRecentTransactions({
    int limit = 20,
  }) async {
    final snap = await _transactionsCollection()
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => RewardTransaction.fromMap(d.data(), docId: d.id))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Grant
  // ---------------------------------------------------------------------------

  /// Grants reward for a completed focus session.
  ///
  /// Uses the [focusSessionId] as an idempotency key — duplicate calls with
  /// the same ID return the existing grant result without creating a second
  /// ledger entry.
  ///
  /// [plannedMinutes] is the original session duration (15/25/45/60).
  /// [sessionLabel] is the user-provided study label (optional, for ledger).
  static Future<RewardGrantResult> grantFocusReward({
    required String focusSessionId,
    required int plannedMinutes,
    String? sessionLabel,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);
    final txRef = userRef.collection('reward_transactions');
    final dailyRef = userRef.collection('reward_daily').doc(todayKey());

    // Compute base reward from planned minutes.
    final baseReward = rewardForPlannedMinutes(plannedMinutes);

    // Run in a Firestore batch + transaction to ensure atomicity and
    // idempotency. The idempotency check (no existing tx with this sessionId)
    // is part of the read-phase; the write-phase is batched.
    final result = await db.runTransaction<RewardGrantResult>((txn) async {
      // --- Read phase ---

      // 1. Check idempotency: has this session already been rewarded?
      final existingTx = await txRef
          .where('sourceSessionId', isEqualTo: focusSessionId)
          .limit(1)
          .get();

      if (existingTx.docs.isNotEmpty) {
        // Already granted — return the previous result.
        final prevData = existingTx.docs.first.data();
        final profileSnap = await txn.get(userRef);
        final profileData = profileSnap.data() ?? {};
        final totalXp = (profileData['totalXp'] as num?)?.toInt() ?? 0;
        final gems = (profileData['gems'] as num?)?.toInt() ?? 0;
        final level = levelForXp(totalXp);

        // Read daily gems for informational purposes.
        final dailySnap = await txn.get(dailyRef);
        final dailyData = dailySnap.data() ?? {};
        final dailyGems = (dailyData['gems'] as num?)?.toInt() ?? 0;

        return RewardGrantResult(
          xpGranted: prevData['xpDelta'] as int? ?? 0,
          gemsGranted: prevData['gemDelta'] as int? ?? 0,
          oldLevel: level,
          newLevel: level,
          totalXp: totalXp,
          totalGems: gems,
          dailyGemsEarned: dailyGems,
          dailyCap: dailyGemCap,
        );
      }

      // 2. Read current profile.
      final profileSnap = await txn.get(userRef);
      final profileData = profileSnap.data() ?? {};
      final oldXp = (profileData['totalXp'] as num?)?.toInt() ?? 0;
      final oldGems = (profileData['gems'] as num?)?.toInt() ?? 0;
      final oldLevel = levelForXp(oldXp);

      // 3. Read daily gem cap state.
      final dailySnap = await txn.get(dailyRef);
      final dailyData = dailySnap.data() ?? {};
      final gemsEarnedToday = (dailyData['gems'] as num?)?.toInt() ?? 0;

      // --- Compute phase ---
      final actualGems = clampGemsForDailyCap(
        rawGemReward: baseReward.gems,
        gemsEarnedToday: gemsEarnedToday,
      );
      final newXp = oldXp + baseReward.xp;
      final newGems = oldGems + actualGems;
      final newLevel = levelForXp(newXp);

      // --- Write phase ---

      // 4. Create ledger entry.
      txn.set(txRef.doc(), {
        ...RewardTransaction(
          id: '',
          ownerId: uid,
          type: 'focus_reward',
          source: 'focus_session',
          sourceSessionId: focusSessionId,
          xpDelta: baseReward.xp,
          gemDelta: actualGems,
          createdAt: FieldValue.serverTimestamp(),
          label: sessionLabel,
          plannedMinutes: plannedMinutes,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 5. Update reward profile.
      txn.set(
        userRef,
        {
          'totalXp': newXp,
          'gems': newGems,
          'level': newLevel,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 6. Update daily gem cap document.
      txn.set(
        dailyRef,
        {
          'gems': gemsEarnedToday + actualGems,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return RewardGrantResult(
        xpGranted: baseReward.xp,
        gemsGranted: actualGems,
        oldLevel: oldLevel,
        newLevel: newLevel,
        totalXp: newXp,
        totalGems: newGems,
        dailyGemsEarned: gemsEarnedToday + actualGems,
        dailyCap: dailyGemCap,
        unlockedReactions: newLevel > oldLevel
            ? newlyUnlockedReactions(oldLevel, newLevel)
                .map((r) => r.emoji)
                .toList()
            : null,
      );
    });

    return result;
  }
}
