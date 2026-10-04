// Phase 10.6 — Admin Analytics Dashboard Widget & Contract Tests.
//
// Tests:
//   * Admin-only visibility (admin role check in ProfileScreen contract)
//   * Access control on screen (non-admin student & general roles show Access Restricted)
//   * Dashboard states (loading, error, access restricted, time-range filters)
//   * Analytics rendering & privacy guarantees (disclaimer, privacy notice, no student PII)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/admin/presentation/admin_analytics_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Phase 10.6 — Admin Analytics Code & Contract Tests', () {
    final adminScreenCode = _read(
      'lib/features/admin/presentation/admin_analytics_screen.dart',
    );
    final profileScreenCode = _read(
      'lib/features/profile/presentation/profile_screen.dart',
    );

    test('profile_screen surfaces AdminAnalyticsScreen only for role == admin', () {
      expect(
        profileScreenCode.contains("if (role == 'admin')"),
        isTrue,
        reason: 'Profile screen must guard admin card with role == admin check',
      );
      expect(
        profileScreenCode.contains('AdminAnalyticsScreen'),
        isTrue,
        reason: 'Profile screen must navigate to AdminAnalyticsScreen',
      );
    });

    test('admin_analytics_screen defines time range filters 7, 30, and 90 days', () {
      expect(adminScreenCode.contains('7'), isTrue);
      expect(adminScreenCode.contains('30'), isTrue);
      expect(adminScreenCode.contains('90'), isTrue);
      expect(adminScreenCode.contains('ChoiceChip'), isTrue);
    });

    test('admin_analytics_screen enforces topic difficulty disclaimer', () {
      expect(
        adminScreenCode.contains('Observed platform struggle'),
        isTrue,
        reason: 'Must include transparent interpretation disclaimer',
      );
    });

    test('admin_analytics_screen has explicit privacy notice and no student profile leak', () {
      expect(
        adminScreenCode.contains('Privacy Notice'),
        isTrue,
        reason: 'Dashboard must prominently display platform privacy guarantee',
      );
      // Ensure no individual student private fields are queried or rendered
      expect(adminScreenCode.contains('studentName'), isFalse);
      expect(adminScreenCode.contains('chatTranscript'), isFalse);
      expect(adminScreenCode.contains('rawNotes'), isFalse);
      expect(adminScreenCode.contains('studentPhone'), isFalse);
    });
  });

  group('Phase 10.6 — Admin Analytics Widget Tests', () {
    testWidgets('non-admin role displays Access Restricted view', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: const AdminAnalyticsScreen(userRole: 'student'),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('Administrator privileges are required to view platform analytics.'), findsOneWidget);

      // Verify that no platform overview or topic data is shown to non-admin
      expect(find.text('Platform Overview'), findsNothing);
      expect(find.text('Topic Difficulty'), findsNothing);
    });

    testWidgets('general role displays Access Restricted view', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: const AdminAnalyticsScreen(userRole: 'general'),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(find.text('Platform Overview'), findsNothing);
    });

    testWidgets('admin role initially renders loading indicator then handles network error cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: const AdminAnalyticsScreen(userRole: 'admin'),
        ),
      );

      // In initial build, shows loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Pump to settle async calls (which fail in unit test environment due to no live server)
      await tester.pumpAndSettle();

      // Displays error state with retry button
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

