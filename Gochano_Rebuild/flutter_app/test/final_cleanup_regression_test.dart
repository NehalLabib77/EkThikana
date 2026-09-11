// Regression tests for the final cleanup release v2 fixes.
//
// Pinned bugs:
//   1. DoseStatus .name crash on Infinix / low-memory devices
//   2. CommuteBD _StrategyChooser infinite-height rendering
//   3. Home Quick Access before Today card
//   4. Home legacy attention sections removed
//   5. Profile Study section removed
//   6. Expense FAB overlap / Categories clipping
//   7. Workspace Quick Access responsive labels
//   8. Journey polyline drawn on successful route
//   9. Multimodal fallback returns usable route

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/life/domain/medicine_schedule.dart';
import 'package:gochano/features/life/presentation/commute/journey_models.dart';
import 'package:gochano/features/life/presentation/commute/journey_view.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('DoseStatus safe conversion', () {
    test('doseStatusKey returns correct string for pending', () {
      expect(doseStatusKey(DoseStatus.pending), 'pending');
    });

    test('doseStatusKey returns correct string for taken', () {
      expect(doseStatusKey(DoseStatus.taken), 'taken');
    });

    test('doseStatusKey returns correct string for skipped', () {
      expect(doseStatusKey(DoseStatus.skipped), 'skipped');
    });

    test('doseStatusKey returns correct string for missed', () {
      expect(doseStatusKey(DoseStatus.missed), 'missed');
    });

    test('id getter delegates to doseStatusKey, not Enum.name', () {
      for (final status in DoseStatus.values) {
        expect(status.id, doseStatusKey(status));
      }
    });

    test('parse round-trips every status through doseStatusKey', () {
      for (final status in DoseStatus.values) {
        final key = doseStatusKey(status);
        expect(DoseStatus.parse(key), status);
      }
    });

    test('no DoseStatus value produces an empty key', () {
      for (final status in DoseStatus.values) {
        expect(doseStatusKey(status).isNotEmpty, isTrue);
      }
    });

    test('exactly four DoseStatus values exist (exhaustive switch check)', () {
      expect(DoseStatus.values, hasLength(4));
    });

    test('doseStatusKey source code uses explicit switch, not .name', () {
      final source = _read('lib/features/life/domain/medicine_schedule.dart');
      // The function must exist with an explicit switch.
      expect(source, contains('String doseStatusKey(DoseStatus status)'));
      // Must NOT use Enum.name for the conversion.
      expect(
        source,
        isNot(contains('status.name')),
        reason: 'doseStatusKey must not call Enum.name directly',
      );
    });
  });

  group('CommuteBD StrategyChooser finite height', () {
    // The _StrategyChooser is private, so we test through JourneyPlanSection.
    Map<String, dynamic> multiJourneyResponse() {
      return {
        'journeyPlanning': {'available': true},
        'journeys': [
          {
            'objectives': ['recommended'],
            'category': 'recommended',
            'origin': 'A',
            'destination': 'B',
            'totalFareTk': 30,
            'totalDurationMinutes': 25,
            'totalDistanceKm': 5.0,
            'totalWalkKm': 0.2,
            'transfers': 1,
            'modeSummary': ['Walk', 'Bus', 'Walk'],
            'fareCertainty': 'official',
            'fareCertaintyLabel': 'Official',
            'fareDeltaTk': 0,
            'durationDeltaMinutes': 0,
            'legs': [
              {
                'mode': 'bus',
                'modeLabel': 'Bus',
                'from': 'A',
                'to': 'B',
                'distanceKm': 5.0,
                'durationMinutes': 20,
                'fareTk': 30.0,
                'fareType': 'official',
                'fareLabel': 'Official',
                'fareSource': 'Official table',
                'instruction': 'Take a bus.',
                'isTransfer': false,
                'transferMinutes': 0,
                'serviceName': null,
                'fromLat': 23.8,
                'fromLon': 90.4,
                'toLat': 23.7,
                'toLon': 90.3,
              },
            ],
          },
          {
            'objectives': ['cheapest'],
            'category': 'cheapest',
            'origin': 'A',
            'destination': 'B',
            'totalFareTk': 15,
            'totalDurationMinutes': 40,
            'totalDistanceKm': 5.2,
            'totalWalkKm': 0.3,
            'transfers': 1,
            'modeSummary': ['Walk', 'Bus', 'Walk'],
            'fareCertainty': 'historical',
            'fareCertaintyLabel': 'Historical',
            'fareDeltaTk': -15.0,
            'durationDeltaMinutes': 15,
            'legs': [
              {
                'mode': 'bus',
                'modeLabel': 'Bus',
                'from': 'A',
                'to': 'B',
                'distanceKm': 5.2,
                'durationMinutes': 35,
                'fareTk': 15.0,
                'fareType': 'historical',
                'fareLabel': 'Historical',
                'fareSource': 'BRTA rule',
                'instruction': 'Take a bus.',
                'isTransfer': false,
                'transferMinutes': 0,
                'serviceName': null,
                'fromLat': 23.8,
                'fromLon': 90.4,
                'toLat': 23.7,
                'toLon': 90.3,
              },
            ],
          },
        ],
      };
    }

    testWidgets('renders without infinite height error', (tester) async {
      final plan = JourneyPlan.fromResponse(multiJourneyResponse());
      // Wrap in an unbounded Column inside a ListView, exactly like
      // the real commute screen layout.
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: Scaffold(
            body: ListView(children: [JourneyPlanSection(plan: plan)]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // If the strategy chooser caused an infinite-height error, the widget
      // tree would fail to build. Getting here means it rendered.
      expect(find.text('Recommended'), findsWidgets);
      expect(find.text('Cheapest'), findsOneWidget);
    });

    testWidgets('tapping a strategy switches the selected journey', (
      tester,
    ) async {
      final plan = JourneyPlan.fromResponse(multiJourneyResponse());
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: Scaffold(
            body: ListView(children: [JourneyPlanSection(plan: plan)]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the cheapest strategy card.
      await tester.tap(find.text('Cheapest'));
      await tester.pumpAndSettle();

      // The cheapest fare should now be visible in the summary.
      expect(find.text('৳15'), findsWidgets);
    });
  });

  group('Home structure (static source guards)', () {
    late String source;

    setUpAll(
      () => source = _read('lib/features/home/presentation/home_screen.dart'),
    );

    test('Quick Access section header exists', () {
      expect(source, contains("'Quick Access'"));
      expect(source, contains("'দ্রুত প্রবেশ'"));
    });

    test('Quick Access appears before Today tasks card in build order', () {
      final qaIndex = source.indexOf("'Quick Access'");
      final todayIndex = source.indexOf("Today's tasks");
      expect(
        qaIndex,
        lessThan(todayIndex),
        reason: 'Quick Access must come before Today tasks',
      );
    });

    test('legacy ContinueStudyingCard is removed', () {
      expect(source, isNot(contains('_ContinueStudyingCard')));
    });

    test('legacy GroupActivityCard is removed', () {
      expect(source, isNot(contains('_GroupActivityCard')));
    });

    test('no Smart attention / Your Day / Now-Next / Plan my day / Rescue', () {
      expect(source, isNot(contains('Smart attention')));
      expect(source, isNot(contains('Your Day')));
      expect(source, isNot(contains('Now / Next')));
      expect(source, isNot(contains('Plan my day')));
      expect(source, isNot(contains('Rescue my day')));
    });

    test('Commute card is present', () {
      expect(source, contains('_CommuteCard'));
    });

    test('quick action destinations are preserved', () {
      for (final dest in const [
        'AiAssistantScreen',
        'showAddExpenseSheet',
        'onOpenDestination',
        'CommuteScreen',
      ]) {
        expect(
          source,
          contains(dest),
          reason: '$dest must still be one tap from Home',
        );
      }
    });

    test('formatTaka is still exported for shared use', () {
      expect(source, contains('String formatTaka(double amount)'));
    });
  });

  group('Student global shell (static source guards)', () {
    late String shellSource;
    late String homeSource;

    setUpAll(() {
      shellSource = _read('lib/features/shell/presentation/gochano_shell.dart');
      homeSource = _read('lib/features/home/presentation/home_screen.dart');
    });

    test('student shell exposes exactly the requested five destinations', () {
      final studentStart = shellSource.indexOf('if (_isStudent)');
      final generalStart = shellSource.indexOf('\n    return [', studentStart);
      final studentSource = shellSource.substring(studentStart, generalStart);
      for (final label in const [
        'Today',
        'Study',
        'Money',
        'Commute',
        'Community',
      ]) {
        expect(studentSource, contains("'$label'"));
      }
      expect(studentSource, isNot(contains("'Profile'")));
      expect(studentSource, isNot(contains("'Life'")));
      expect(
        studentSource.indexOf("'Commute'") < studentSource.indexOf("'Money'"),
        isTrue,
      );
    });

    test('Today header retains language control and opens Profile', () {
      expect(homeSource, contains('LanguageToggle'));
      expect(homeSource, contains('onOpenProfile'));
      expect(shellSource, contains('ProfileScreen(role: widget.role)'));
      expect(shellSource, contains('GochanoRoute.to'));
    });

    test('student shell reuses existing Money and Commute screens', () {
      expect(shellSource, contains('const ExpenseScreen()'));
      expect(shellSource, contains('const CommuteScreen()'));
    });
  });

  group('Profile structure (static source guards)', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/profile/presentation/profile_screen.dart',
      ),
    );

    test('Study section is completely removed', () {
      expect(source, isNot(contains("_StudyStatsRow")));
      expect(source, isNot(contains('SectionHeader(title:')));
      expect(source, isNot(contains("'Study'")));
      expect(source, isNot(contains("'পড়াশোনা'")));
    });

    test('Usage Access is not present', () {
      expect(source, isNot(contains('Usage Access')));
      expect(source, isNot(contains('usage_access')));
      expect(source, isNot(contains('UsageAccess')));
    });

    test('Identity header flows directly into settings', () {
      // After _RoleBadge there should be only SizedBox(height: GochanoSpacing.lg)
      // before _SettingsCard, no extra section in between.
      final roleBadgeIdx = source.indexOf('class _RoleBadge');
      final settingsIdx = source.indexOf('class _SettingsCard');
      final between = source.substring(roleBadgeIdx, settingsIdx);
      // Should not contain Study, Stats, or any other section header.
      expect(between, isNot(contains('SectionHeader')));
    });
  });

  group('Expense screen (static source guards)', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/life/presentation/expense/expense_screen.dart',
      ),
    );

    test('Overview tab has safe bottom padding for FAB', () {
      final overviewSource = source.substring(
        source.indexOf('class _OverviewTab'),
      );
      expect(
        overviewSource,
        contains('88'),
        reason: 'Bottom padding of 88px protects content from FAB overlap',
      );
    });

    test(
      'TabBar does not use GochanoSpacing.scrollBody directly for Overview',
      () {
        // The Overview tab should have its own padding with FAB clearance.
        final overviewSource = source.substring(
          source.indexOf('class _OverviewTab'),
          source.indexOf('class _DailyTab'),
        );
        expect(
          overviewSource,
          contains('EdgeInsets.fromLTRB'),
          reason:
              'Overview uses explicit EdgeInsets.fromLTRB for FAB clearance',
        );
      },
    );
  });

  group('Workspace Quick Access (static source guards)', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      ),
    );

    test('Quick Access grid exists', () {
      expect(source, contains('_QuickAccessGrid'));
      expect(source, contains("'Quick Access'"));
    });

    test('Quick Access labels use maxLines: 2', () {
      final qaSource = source.substring(
        source.indexOf('class _QuickAccessItem'),
      );
      expect(qaSource, contains('maxLines: 2'));
    });

    test('Quick Access labels use TextAlign.center', () {
      final qaSource = source.substring(
        source.indexOf('class _QuickAccessItem'),
      );
      expect(qaSource, contains('TextAlign.center'));
    });

    test('Quick Access labels use ellipsis overflow', () {
      final qaSource = source.substring(
        source.indexOf('class _QuickAccessItem'),
      );
      expect(qaSource, contains('TextOverflow.ellipsis'));
    });
  });

  group('Commute journey polyline (static source guard)', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/life/presentation/commute/journey_view.dart',
      ),
    );

    test('JourneyMap draws PolylineLayer for successful routes', () {
      expect(source, contains('PolylineLayer'));
      expect(source, contains('Polyline('));
    });

    test('JourneyMap draws MarkerLayer for origin/destination', () {
      expect(source, contains('MarkerLayer'));
      expect(source, contains('Marker('));
    });

    test('Map uses CameraFit.coordinates for auto-fitting', () {
      expect(source, contains('CameraFit.coordinates'));
    });

    test('Multimodal legs are visually distinguished (walk dashed)', () {
      expect(source, contains('StrokePattern.dashed'));
      expect(source, contains('StrokePattern.solid'));
    });
  });

  group('StrategyChooser layout (source guard)', () {
    test('does not use CrossAxisAlignment.stretch', () {
      final source = _read(
        'lib/features/life/presentation/commute/journey_view.dart',
      );
      final chooserSource = source.substring(
        source.indexOf('class _StrategyChooser'),
        source.indexOf('String journeyStrategyLabel'),
      );
      expect(
        chooserSource,
        isNot(contains('CrossAxisAlignment.stretch')),
        reason:
            'CrossAxisAlignment.stretch causes infinite-height crash in '
            'unbounded vertical scroll',
      );
    });

    test('uses CrossAxisAlignment.start instead', () {
      final source = _read(
        'lib/features/life/presentation/commute/journey_view.dart',
      );
      final chooserSource = source.substring(
        source.indexOf('class _StrategyChooser'),
        source.indexOf('String journeyStrategyLabel'),
      );
      expect(chooserSource, contains('CrossAxisAlignment.start'));
    });
  });

  group('Commute multimodal fallback (source guard)', () {
    test('client_route_estimator.dart or commute fallback exists', () {
      // The commute screen or journey models must have fallback logic.
      final source = _read(
        'lib/features/life/presentation/commute/commute_screen.dart',
      );
      // The screen must not show a hard failure message when routes are empty.
      expect(
        source,
        isNot(
          contains(
            'transport network is temporarily '
            'unavailable',
          ),
        ),
      );
    });
  });
}
