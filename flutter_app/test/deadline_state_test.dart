// Deadline state logic tests.
//
// Verifies the time-left calculation used by the Assignment bento card
// in PlanView. The logic is extracted here as pure functions so it can be
// unit-tested without a Flutter widget binding.

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the deadline state logic from plan_view.dart _deadlineStateBadge.
///
/// Returns a (label, tone) tuple where tone is one of:
///   'error'   — overdue
///   'warning' — due today
///   'info'    — due tomorrow
///   'neutral' — due in N days
(String, String) deadlineState(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;

  if (diff < 0) return ('Overdue', 'error');
  if (diff == 0) return ('Today', 'warning');
  if (diff == 1) return ('Tomorrow', 'info');
  return ('In $diff days', 'neutral');
}

void main() {
  group('Deadline state badge logic', () {
    test('overdue date returns error badge', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final (label, tone) = deadlineState(yesterday);
      expect(label, 'Overdue');
      expect(tone, 'error');
    });

    test('date two days ago returns error badge', () {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final (label, tone) = deadlineState(twoDaysAgo);
      expect(label, 'Overdue');
      expect(tone, 'error');
    });

    test('today returns warning badge', () {
      final now = DateTime.now();
      final (label, tone) = deadlineState(now);
      expect(label, 'Today');
      expect(tone, 'warning');
    });

    test('today at midnight returns warning badge', () {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final (label, tone) = deadlineState(midnight);
      expect(label, 'Today');
      expect(tone, 'warning');
    });

    test('tomorrow returns info badge', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final (label, tone) = deadlineState(tomorrow);
      expect(label, 'Tomorrow');
      expect(tone, 'info');
    });

    test('three days from now returns neutral badge with correct label', () {
      final inThreeDays = DateTime.now().add(const Duration(days: 3));
      final (label, tone) = deadlineState(inThreeDays);
      expect(label, 'In 3 days');
      expect(tone, 'neutral');
    });

    test('seven days from now returns neutral badge', () {
      final inSevenDays = DateTime.now().add(const Duration(days: 7));
      final (label, tone) = deadlineState(inSevenDays);
      expect(label, 'In 7 days');
      expect(tone, 'neutral');
    });

    test('30 days from now returns neutral badge', () {
      final inThirtyDays = DateTime.now().add(const Duration(days: 30));
      final (label, tone) = deadlineState(inThirtyDays);
      expect(label, 'In 30 days');
      expect(tone, 'neutral');
    });
  });
}
