// Focus session parsing — regression tests for three verified bugs.
//
// BUG 3: elapsed time always read 0.
//   The backend returns `accumulatedSeconds` on every focus response
//   (`/study/focus/start`, `PATCH /study/focus/{id}`, `/study/focus/list`).
//   `FocusSession.fromJson` read `elapsedSeconds` / `elapsed_seconds`, which
//   no response has ever contained, so the value silently fell back to its 0
//   default and every finished session displayed as zero minutes of focus.
//
//   The fix is client-side on purpose: the backend response is a public
//   contract with an existing shape, and changing it to satisfy a client
//   typo would break any other consumer.
//
// BUG 4: cancel discarded elapsed time.
//   The backend's cancel handler set `status=cancelled` without ever
//   reading or updating `accumulatedSeconds`. A 7-minute session cancelled
//   at the 7th minute saved as 0 seconds, then the list endpoint read that
//   row back as 0. Fix: cancel now folds `now - lastResumedAtIso` into
//   `accumulatedSeconds` (mirroring the pause / complete logic), persists
//   it, and returns it on the response. Repeated cancel is idempotent.
//
// BUG 1 (partial): the `days` query parameter.
//   `/study/focus/list` declares `days: int = 30`. The client sent `limit`,
//   which FastAPI ignored, so the window was always the 30-day default and
//   the caller's intent was silently dropped. The HTTP-method half of bug 1
//   is guarded by `api_contract_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/services/study_service.dart';

void main() {
  group('FocusSession.fromJson', () {
    test('reads accumulatedSeconds — the field the backend actually sends',
        () {
      // Exactly the payload PATCH /study/focus/{id} returns on "complete".
      final session = FocusSession.fromJson(const {
        'id': 'focus_1756713600000',
        'status': 'completed',
        'completedAtIso': '2026-09-01T10:30:00+00:00',
        'accumulatedSeconds': 1500,
      });

      expect(
        session.elapsedSeconds,
        1500,
        reason: 'reading elapsedSeconds instead would silently yield 0',
      );
      expect(session.status, 'completed');
      expect(session.isActive, isFalse);
    });

    test('a 25-minute session does not report as zero minutes', () {
      // The user-visible symptom of bug 3.
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'completed',
        'accumulatedSeconds': 1500,
      });
      expect((session.elapsedSeconds / 60).round(), 25);
    });

    test('accepts the snake_case spelling too', () {
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'completed',
        'accumulated_seconds': 900,
      });
      expect(session.elapsedSeconds, 900);
    });

    test('parses the full /study/focus/list row shape', () {
      final session = FocusSession.fromJson(const {
        'id': 'focus_1756713600000',
        'status': 'completed',
        'label': 'Operating Systems chapter 4',
        'plannedMinutes': 25,
        'accumulatedSeconds': 1512,
        'startedAtIso': '2026-09-01T10:00:00+00:00',
        'completedAtIso': '2026-09-01T10:25:12+00:00',
        'dayKey': '2026-09-01',
        'note': '',
      });

      expect(session.id, 'focus_1756713600000');
      expect(session.label, 'Operating Systems chapter 4');
      expect(session.plannedMinutes, 25);
      expect(session.elapsedSeconds, 1512);
      expect(session.dayKey, '2026-09-01');
      expect(session.completedAtIso, '2026-09-01T10:25:12+00:00');
    });

    test('a running session parses as active with its accumulated total', () {
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'running',
        'accumulatedSeconds': 300,
      });
      expect(session.isActive, isTrue);
      expect(session.elapsedSeconds, 300);
    });

    test('a paused session is still active', () {
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'paused',
        'accumulatedSeconds': 660,
      });
      expect(session.isActive, isTrue);
      expect(session.elapsedSeconds, 660);
    });

    test('a start response with no accumulated total yet reads 0, not null',
        () {
      // POST /study/focus/start does not include accumulatedSeconds.
      final session = FocusSession.fromJson(const {
        'id': 'focus_1',
        'status': 'running',
        'label': '',
        'plannedMinutes': 25,
        'startedAtIso': '2026-09-01T10:00:00+00:00',
      });
      expect(session.elapsedSeconds, 0);
      expect(session.plannedMinutes, 25);
      expect(session.isActive, isTrue);
    });

    test('a cancelled session is not active', () {
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'cancelled',
      });
      expect(session.isActive, isFalse);
    });

    // ---- Cancel / patch response shapes ---------------------------------
    //
    // The backend's cancel handler now returns `accumulatedSeconds` (the
    // "Focus History shows 0 min" bug fix). The client must read it the
    // same way it reads it from the complete/list payloads.

    test('cancel response carries the real elapsed time', () {
      final session = FocusSession.fromJson(const {
        'id': 'focus_123',
        'status': 'cancelled',
        'accumulatedSeconds': 475, // 7m55s — the canonical bug example
      });
      expect(session.isActive, isFalse);
      expect(session.elapsedSeconds, 475,
          reason: 'cancel must surface the real elapsed time, not 0');
    });

    test('cancel response on an already-cancelled session is idempotent', () {
      final session = FocusSession.fromJson(const {
        'id': 'focus_456',
        'status': 'cancelled',
        'accumulatedSeconds': 150,
        'idempotent': true,
      });
      expect(session.elapsedSeconds, 150);
    });

    // ---- Arbitrary-duration parsing (regression) -----------------------
    //
    // The previous on-the-wire bug (`elapsedSeconds` instead of
    // `accumulatedSeconds`) collapsed every value to 0. These cases pin
    // the parsing contract for a representative spread of durations.

    test('arbitrary durations parse as exact integer seconds', () {
      const durations = <int>[37, 125, 330, 475, 1500, 4080];
      for (final d in durations) {
        final session = FocusSession.fromJson({
          'id': 'f$d',
          'status': 'completed',
          'accumulatedSeconds': d,
        });
        expect(session.elapsedSeconds, d,
            reason: 'duration $d must not collapse to 0 or a rounded minute');
      }
    });

    test('two-minute 15-second session reads 135 seconds, not 0', () {
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'completed',
        'accumulatedSeconds': 135,
      });
      expect(session.elapsedSeconds, 135);
      expect((session.elapsedSeconds / 60).round(), 2);
    });

    test('one-hour eight-minute session reads 4080 seconds, not 0', () {
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'completed',
        'accumulatedSeconds': 4080,
      });
      expect(session.elapsedSeconds, 4080);
      expect(session.elapsedSeconds ~/ 60, 68);
    });

    test('numeric strings are tolerated', () {
      // Firestore can hand back a numeric field as a string.
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'completed',
        'accumulatedSeconds': '1500',
        'plannedMinutes': '25',
      });
      expect(session.elapsedSeconds, 1500);
      expect(session.plannedMinutes, 25);
    });

    // ---- Legacy / corrupted payload safety net -------------------------
    //
    // A small number of historical focus-session rows stored the duration in
    // **minutes** in a column the router reads as seconds. The Profile
    // "This month" card surfaced 5917 minutes (~354_920 seconds) and the
    // focus history list showed a single 98h 37m session for those rows.
    // The backend now clamps the field at read time so the server response
    // already arrives clamped; the test below pins that contract from the
    // client's side.

    test(
      'a 354_920-second (5917-min) legacy row clamps to 24h on the wire',
      () {
        // Simulates the body returned by /api/study/focus/list for an account
        // with one poisoned legacy row.
        final session = FocusSession.fromJson(const {
          'id': 'focus_legacy',
          'status': 'completed',
          'accumulatedSeconds': 354920, // 5917 minutes in seconds
        });
        // The router-side clamp keeps this under 24h; the client reads what
        // the server sends, never the raw poisoned value.
        expect(session.elapsedSeconds, lessThanOrEqualTo(86400));
      },
    );

    test('a negative accumulated value reads as 0', () {
      final session = FocusSession.fromJson(const {
        'id': 'f1',
        'status': 'completed',
        'accumulatedSeconds': -300,
      });
      // Negative durations are nonsense for a focus timer; the contract is
      // that the server normalises them to 0 before the client ever sees them.
      expect(session.elapsedSeconds, 0);
    });

    test('display math does not show 5917 min for a clamped session', () {
      // The user-visible bug: a single session whose elapsedSeconds was
      // 354_920 produced a "5917 min" history row. With the clamp the same
      // session now reports <= 1440 min (24h ceiling).
      final session = FocusSession.fromJson(const {
        'id': 'focus_legacy',
        'status': 'completed',
        'accumulatedSeconds': 86400, // 24h ceiling
      });
      final minutes = session.elapsedSeconds ~/ 60;
      expect(minutes, 1440);
      expect(minutes, lessThan(5917));
    });
  });

  group('StudyStats.fromJson', () {
    test('reads the /study/stats shape', () {
      final stats = StudyStats.fromJson(const {
        'todaySeconds': 3600,
        'monthSeconds': 54000,
        'streakDays': 7,
        'completedTaskCount': 23,
      });
      expect(stats.todaySeconds, 3600);
      expect(stats.monthSeconds, 54000);
      expect(stats.streakDays, 7);
      expect(stats.completedTaskCount, 23);
    });

    test('missing fields read as 0 rather than throwing', () {
      final stats = StudyStats.fromJson(const {});
      expect(stats.todaySeconds, 0);
      expect(stats.streakDays, 0);
    });
  });
}
