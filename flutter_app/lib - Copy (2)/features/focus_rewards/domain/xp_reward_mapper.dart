// Maps planned focus duration to XP and Gem rewards.
//
// Only completed sessions earn rewards. Starting or cancelling a session
// grants nothing.

/// Reward amounts for a successfully completed focus session.
class FocusReward {
  const FocusReward({
    required this.xp,
    required this.gems,
  });

  final int xp;
  final int gems;
}

/// Returns the reward for a completed session of [plannedMinutes].
///
/// Supported durations: 15, 25, 45, 60 minutes.
/// Returns a zero reward for unsupported durations (safety fallback).
FocusReward rewardForPlannedMinutes(int plannedMinutes) {
  switch (plannedMinutes) {
    case 15:
      return const FocusReward(xp: 15, gems: 1);
    case 25:
      return const FocusReward(xp: 25, gems: 2);
    case 45:
      return const FocusReward(xp: 45, gems: 4);
    case 60:
      return const FocusReward(xp: 60, gems: 5);
    default:
      return const FocusReward(xp: 0, gems: 0);
  }
}
