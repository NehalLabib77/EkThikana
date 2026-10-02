// Phase 5 — Ziku Focus Engine: Flutter coverage.
//
// Two surfaces, one store: the session screen (5.4) and the Home card
// (5.5). Every hook is injected so no test opens a socket, and the copies
// pinned here are the ones the spec asks for: "Today's Focus: 45/60
// minutes", "Continue Session", the countdown, and the completion card.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/study/presentation/focus/focus_session_screen.dart';
import 'package:gochano/features/study/presentation/focus/ziku_session_card.dart';
import 'package:gochano/shared/states/gochano_states.dart';
import 'package:gochano/shared/widgets/gochano_controls.dart';

Map<String, dynamic> _todaySnapshot({
  int minutes = 45,
  int goal = 60,
  List<String> activeSessionIds = const [],
}) => {
  'dayKey': '2026-10-02',
  'minutes': minutes,
  'goalMinutes': goal,
  'streakDays': 3,
  'activeSessionIds': activeSessionIds,
  'score': {
    'value': 78,
    'band': 'developing',
    'label': 'Solid rhythm',
    'activeDays': 4,
    'sessions': 6,
  },
  'weekly': {'consistencyPct': 57.1, 'streakDays': 3},
  'nudge': {
    'kind': 'streak',
    'message':
        '3-day focus streak - keep the chain alive with one short block.',
  },
};

const Map<String, dynamic> _startPayload = {
  'id': 'focus_1',
  'status': 'running',
  'plannedMinutes': 25,
};

/// Content tests need more than the default 800x600 or the timer card and
/// the control row collide.
Future<void> _tallSurface(WidgetTester tester, double height) async {
  await tester.binding.setSurfaceSize(Size(900, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Pushes [screen] on a host route so `Done` has somewhere to pop back to.
Future<void> _openScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: const SizedBox(height: 1))),
  );
  Navigator.of(tester.element(find.byType(SizedBox))).push(
    MaterialPageRoute<void>(builder: (_) => screen),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('focus engine helpers', () {
    test('focusClock formats the countdown as mm:ss', () {
      expect(focusClock(0), '00:00');
      expect(focusClock(9), '00:09');
      expect(focusClock(1499), '24:59');
      expect(focusClock(1500), '25:00');
      expect(focusClock(-3), '00:00');
    });

    test('score bands map to the copy and tone the UI shows', () {
      expect(focusBandLabel('excellent'), contains('Deep focus streak'));
      expect(focusBandLabel('developing'), contains('Solid rhythm'));
      expect(focusBandLabel('needs_structure'), contains('Needs structure'));
      expect(focusBandLabel(null), contains('Needs structure'));
      expect(focusBandTone('excellent'), GochanoBadgeTone.success);
      expect(focusBandTone('developing'), GochanoBadgeTone.info);
      expect(focusBandTone('needs_structure'), GochanoBadgeTone.warning);
      expect(focusBandTone(null), GochanoBadgeTone.neutral);
    });
  });

  group('FocusSessionScreen', () {
    testWidgets('counts down, pauses, resumes and finishes a block',
        (tester) async {
      final calls = <String>[];
      final today = _todaySnapshot();

      Future<Map<String, dynamic>> start({
        String label = '',
        int plannedMinutes = 25,
        String subject = '',
        String topic = '',
      }) async {
        calls.add('start:$subject:$topic:$plannedMinutes');
        return Map<String, dynamic>.from(_startPayload);
      }

      Future<Map<String, dynamic>> patch(String focusId, String action) async {
        calls.add('patch:$focusId:$action');
        return {'id': focusId, 'status': action};
      }

      Future<Map<String, dynamic>> complete(
        String focusId, {
        String? subject,
        String? topic,
      }) async {
        calls.add('complete:$focusId');
        return {
          'id': focusId,
          'status': 'completed',
          'accumulatedSeconds': 1500,
          'focusScore': 92,
          'interruptions': 0,
          'today': today,
        };
      }

      await _tallSurface(tester, 1600);
      await _openScreen(
        tester,
        FocusSessionScreen(
          initialSubject: 'Physics',
          initialTopic: 'Optics',
          startFn: start,
          patchFn: patch,
          completeFn: complete,
          todayFn: () async => today,
        ),
      );

      // Header, smart nudge and today's minutes vs goal before anything runs.
      expect(find.text('Ziku Focus'), findsOneWidget);
      expect(find.textContaining('3-day focus streak'), findsOneWidget);
      expect(find.text('45/60'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Deep work block'), findsNothing);
      expect(find.widgetWithText(TextField, 'Optics'), findsOneWidget);

      await tester.tap(find.text('Start Session'));
      await tester.pump();

      expect(calls, contains('start:Physics:Optics:25'));
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);

      // The clock ticks once per pumped second.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('24:57'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(calls, contains('patch:focus_1:pause'));
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(calls, contains('patch:focus_1:resume'));
      expect(find.text('Pause'), findsOneWidget);

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      // Completion card: what the server decided, nothing invented here.
      expect(calls, contains('complete:focus_1'));
      expect(find.text('Session finished'), findsOneWidget);
      expect(find.text('25 min focused'), findsOneWidget);
      expect(find.text('Score 92'), findsOneWidget);
      expect(find.text('Focus score 78'), findsOneWidget);
      expect(find.text('Solid rhythm'), findsOneWidget);
      expect(find.textContaining('3-day focus streak'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusSessionScreen), findsNothing);
    });

    testWidgets('a failed start explains itself and keeps the screen alive',
        (tester) async {
      final failure = Exception('start refused');

      await _tallSurface(tester, 1400);
      await _openScreen(
        tester,
        FocusSessionScreen(
          startFn: ({
            String label = '',
            int plannedMinutes = 25,
            String subject = '',
            String topic = '',
          }) async =>
              throw failure,
          patchFn: (String focusId, String action) async =>
              <String, dynamic>{},
          completeFn:
              (String focusId, {String? subject, String? topic}) async =>
                  <String, dynamic>{},
          todayFn: () async => _todaySnapshot(),
        ),
      );

      await tester.tap(find.text('Start Session'));
      await tester.pump();

      expect(find.text(friendlyErrorMessage(failure)), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Start Session'), findsOneWidget);
    });

    testWidgets('a session id from Home resumes the running block',
        (tester) async {
      final calls = <String>[];

      await _tallSurface(tester, 1400);
      await _openScreen(
        tester,
        FocusSessionScreen(
          sessionId: 'focus_7',
          patchFn: (String focusId, String action) async {
            calls.add('patch:$focusId:$action');
            return {'id': focusId, 'status': action};
          },
          todayFn: () async =>
              _todaySnapshot(activeSessionIds: const ['focus_7']),
        ),
      );

      // No Start button: the block was already running on another screen.
      expect(find.text('Start Session'), findsNothing);
      expect(find.text('Pause'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(calls, contains('patch:focus_7:pause'));

      // Stop the ticking clock before the test ends.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('ZikuSessionCard', () {
    testWidgets('shows minutes vs goal and opens the timer', (tester) async {
      await _tallSurface(tester, 1400);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZikuSessionCard(
              todayFn: () async => _todaySnapshot(
                activeSessionIds: const ['focus_abc'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziku Focus'), findsOneWidget);
      expect(find.textContaining('Focus: 45/60 minutes'), findsOneWidget);
      expect(find.text('Score 78'), findsOneWidget);
      expect(find.textContaining('3-day focus streak'), findsOneWidget);

      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, closeTo(0.75, 0.001));

      await tester.tap(find.text('Continue Session'));
      await tester.pumpAndSettle();

      final screen = tester.widget<FocusSessionScreen>(
        find.byType(FocusSessionScreen),
      );
      expect(screen.sessionId, 'focus_abc');
    });

    testWidgets('a failed read degrades to a retry line', (tester) async {
      final failure = Exception('socketexception: refused');

      await _tallSurface(tester, 1400);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZikuSessionCard(todayFn: () async => throw failure),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziku Focus'), findsOneWidget);
      expect(find.text(friendlyErrorMessage(failure)), findsOneWidget);
      expect(find.text('Continue Session'), findsNothing);
    });
  });

  group('Home integration', () {
    test('home_screen.dart mounts the card without the banned word', () {
      final source = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();

      expect(source, contains('ziku_session_card.dart'));
      expect(source, contains('const ZikuSessionCard()'));
      expect(source, isNot(contains('Focus')));
    });
  });
}
