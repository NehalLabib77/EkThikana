// Daily gem earning cap logic.
//
// Prevents trivial farming while still allowing XP to be earned for
// valid completed sessions even after the cap is reached.

/// Maximum Gems a user can earn per calendar day.
const int dailyGemCap = 15;

/// Calculates the actual Gems granted given the raw reward and today's
/// earnings so far.
///
/// Returns the clamped Gems to grant. XP is unaffected by the cap.
int clampGemsForDailyCap({
  required int rawGemReward,
  required int gemsEarnedToday,
}) {
  final remaining = dailyGemCap - gemsEarnedToday;
  if (remaining <= 0) return 0;
  if (rawGemReward <= remaining) return rawGemReward;
  return remaining;
}

/// Returns a Firestore-friendly date key for today (UTC).
String todayKey() {
  final now = DateTime.now().toUtc();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
