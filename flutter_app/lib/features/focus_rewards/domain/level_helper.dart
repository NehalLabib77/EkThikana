// Centralized level calculation for Focus Rewards.
//
// All XP thresholds live here. Every UI component and service that needs
// level information calls through this helper rather than duplicating
// thresholds in multiple places.

/// Cumulative XP thresholds for each level.
///
/// `levelThresholds[i]` is the XP required to reach level `i + 1`.
/// Level 1 starts at 0 XP (no entry needed).
const List<int> levelThresholds = [
  100, // Level 2
  250, // Level 3
  500, // Level 4
  850, // Level 5
  1300, // Level 6
  1900, // Level 7
  2600, // Level 8
];

/// Maximum level defined by the threshold table.
int get maxLevel => levelThresholds.length + 1;

/// Returns the level for the given cumulative [totalXp].
int levelForXp(int totalXp) {
  if (totalXp < 0) return 1;
  for (var i = 0; i < levelThresholds.length; i++) {
    if (totalXp < levelThresholds[i]) return i + 1;
  }
  return maxLevel;
}

/// Returns the cumulative XP at which the current level started.
int currentLevelStartXp(int totalXp) {
  if (totalXp < 0) return 0;
  final level = levelForXp(totalXp);
  if (level <= 1) return 0;
  return levelThresholds[level - 2];
}

/// Returns the cumulative XP required to reach the next level.
///
/// Returns [totalXp] itself when already at max level.
int nextLevelXp(int totalXp) {
  if (totalXp < 0) return levelThresholds[0];
  final level = levelForXp(totalXp);
  if (level >= maxLevel) return totalXp;
  return levelThresholds[level - 1];
}

/// Returns the fraction (0.0 .. 1.0) of progress toward the next level.
double progressToNextLevel(int totalXp) {
  final level = levelForXp(totalXp);
  if (level >= maxLevel) return 1.0;
  final start = currentLevelStartXp(totalXp);
  final target = nextLevelXp(totalXp);
  final span = target - start;
  if (span <= 0) return 1.0;
  return ((totalXp - start) / span).clamp(0.0, 1.0);
}

/// Returns XP remaining until the next level.
///
/// Returns 0 when at max level.
int xpRemainingToNextLevel(int totalXp) {
  final level = levelForXp(totalXp);
  if (level >= maxLevel) return 0;
  return nextLevelXp(totalXp) - totalXp;
}
