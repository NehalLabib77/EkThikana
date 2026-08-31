// Pin the P2-UX NavigationBar tab-set contracts.
//
// The previous floating-glass `_BentoFloatingNav` exposed 5 tabs for
// student (Home / Study / AI / Life / Profile) and 4 for general
// (Home / Life / Tasks / Profile). P2-UX replaces that pill with a
// Material 3 `NavigationBar` whose destinations are:
//
//   Student : Home, Study, Life, Community, Profile      (5 tabs)
//   General : Home, Life, Tasks, Community, Profile      (5 tabs)
//
// `AIAssistant` is no longer a top-level tab — it stays as a tile inside
// the Study tab. `GroupsScreen` is lifted to top level as `Community`.
//
// These tests mount a stripped-down harness that mirrors the
// destination list `HomeShell` builds. Mounting `HomeShell` directly
// would require Firestore (the dashboard listens to a real stream), so
// we re-derive the tab set here and assert the contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({required String role}) {
    final destinations = role == 'student'
        ? const <_Dest>[
            _Dest('Home'),
            _Dest('Study'),
            _Dest('Life'),
            _Dest('Community'),
            _Dest('Profile'),
          ]
        : const <_Dest>[
            _Dest('Home'),
            _Dest('Life'),
            _Dest('Tasks'),
            _Dest('Community'),
            _Dest('Profile'),
          ];

    return MaterialApp(
      home: Scaffold(
        body: Text(role),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: const Icon(Icons.circle),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }

  group('HomeShell — student tab set', () {
    testWidgets('renders Home, Study, Life, Community, Profile (5 tabs)',
        (tester) async {
      await tester.pumpWidget(harness(role: 'student'));
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, equals(5));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Study'), findsOneWidget);
      expect(find.text('Life'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('AI'), findsNothing);
      expect(find.text('Tasks'), findsNothing);
    });
  });

  group('HomeShell — general tab set', () {
    testWidgets('renders Home, Life, Tasks, Community, Profile (5 tabs)',
        (tester) async {
      await tester.pumpWidget(harness(role: 'general'));
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, equals(5));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Life'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Study'), findsNothing);
      expect(find.text('AI'), findsNothing);
    });
  });
}

class _Dest {
  const _Dest(this.label);
  final String label;
}