// Data models for Focus Rewards.
//
// Persisted as Firestore documents under users/{uid}/reward_profile and
// users/{uid}/reward_transactions.

/// The user's reward profile — one document per user.
class RewardProfile {
  const RewardProfile({
    required this.totalXp,
    required this.gems,
    required this.level,
    required this.updatedAt,
  });

  factory RewardProfile.empty() => const RewardProfile(
        totalXp: 0,
        gems: 0,
        level: 1,
        updatedAt: null,
      );

  factory RewardProfile.fromMap(Map<String, dynamic> data) {
    return RewardProfile(
      totalXp: (data['totalXp'] as num?)?.toInt() ?? 0,
      gems: (data['gems'] as num?)?.toInt() ?? 0,
      level: (data['level'] as num?)?.toInt() ?? 1,
      updatedAt: data['updatedAt'],
    );
  }

  final int totalXp;
  final int gems;
  final int level;
  final dynamic updatedAt;

  Map<String, dynamic> toMap() => {
        'totalXp': totalXp,
        'gems': gems,
        'level': level,
      };

  RewardProfile copyWith({
    int? totalXp,
    int? gems,
    int? level,
  }) {
    return RewardProfile(
      totalXp: totalXp ?? this.totalXp,
      gems: gems ?? this.gems,
      level: level ?? this.level,
      updatedAt: updatedAt,
    );
  }
}

/// A single reward transaction entry — append-only ledger.
class RewardTransaction {
  const RewardTransaction({
    required this.id,
    required this.ownerId,
    required this.type,
    required this.source,
    required this.sourceSessionId,
    required this.xpDelta,
    required this.gemDelta,
    required this.createdAt,
    this.label,
    this.plannedMinutes,
  });

  factory RewardTransaction.fromMap(
    Map<String, dynamic> data, {
    String? docId,
  }) {
    return RewardTransaction(
      id: docId ?? data['id']?.toString() ?? '',
      ownerId: data['ownerId']?.toString() ?? '',
      type: data['type']?.toString() ?? '',
      source: data['source']?.toString() ?? '',
      sourceSessionId: data['sourceSessionId']?.toString() ?? '',
      xpDelta: (data['xpDelta'] as num?)?.toInt() ?? 0,
      gemDelta: (data['gemDelta'] as num?)?.toInt() ?? 0,
      createdAt: data['createdAt'],
      label: data['label']?.toString(),
      plannedMinutes: (data['plannedMinutes'] as num?)?.toInt(),
    );
  }

  final String id;
  final String ownerId;
  final String type;
  final String source;
  final String sourceSessionId;
  final int xpDelta;
  final int gemDelta;
  final dynamic createdAt;
  final String? label;
  final int? plannedMinutes;

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'type': type,
        'source': source,
        'sourceSessionId': sourceSessionId,
        'xpDelta': xpDelta,
        'gemDelta': gemDelta,
        'label': label,
        'plannedMinutes': plannedMinutes,
      };
}

/// Result returned after granting a reward — carries the actual values
/// granted (after daily cap) and whether a level-up occurred.
class RewardGrantResult {
  const RewardGrantResult({
    required this.xpGranted,
    required this.gemsGranted,
    required this.oldLevel,
    required this.newLevel,
    required this.totalXp,
    required this.totalGems,
    required this.dailyGemsEarned,
    required this.dailyCap,
    this.unlockedReactions,
  });

  final int xpGranted;
  final int gemsGranted;
  final int oldLevel;
  final int newLevel;
  final int totalXp;
  final int totalGems;
  final int dailyGemsEarned;
  final int dailyCap;
  final List<String>? unlockedReactions;

  bool get levelUp => newLevel > oldLevel;
}
