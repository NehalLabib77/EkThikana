// Phase 12.2.3 — Flutter Dashboard Bootstrap Tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/home/presentation/home_screen.dart';
import 'package:gochano/features/profile/presentation/academic_health_card.dart';
import 'package:gochano/features/study/presentation/focus/ziku_session_card.dart';
import 'package:gochano/features/study/presentation/memory/learning_recommendation_card.dart';
import 'package:gochano/features/study/presentation/planner/ziku_coach_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Phase 12.2.3 — Dashboard Bootstrap & Startup Optimization', () {
    testWidgets(
      'Home uses bootstrap for initial dashboard load and eliminates waterfalls',
      (tester) async {
        int bootstrapCalls = 0;
        final bootstrapData = {
          'profile': {
            'uid': 'student_123',
            'displayName': 'Ahmad',
            'role': 'student',
          },
          'academicHealth': {
            'available': true,
            'score': 84,
            'hasData': true,
            'headline': 'Consistent study streak',
          },
          'coach': {
            'available': true,
            'greetingKey': 'morning',
            'headline': 'Revise Organic Chemistry',
            'priority': {'topic': 'Chemistry'},
            'mission': [
              {
                'key': 'm1',
                'title': 'Complete 10 MCQs',
                'action': 'quiz',
                'minutes': 15,
              },
            ],
          },
          'focus': {
            'available': true,
            'minutesDone': 30,
            'goalMinutes': 60,
            'focusScore': 85,
            'nudge': 'Keep up the momentum!',
          },
          'recommendation': {
            'available': true,
            'items': [
              {'title': 'Alkanes Revision', 'reason': 'Weak area'},
            ],
          },
          'generatedAt': '2026-10-03T09:00:00Z',
        };

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              role: 'student',
              displayName: 'Ahmad',
              onOpenDestination: (_) {},
              onOpenProfile: () {},
              bootstrapFn: () async {
                bootstrapCalls++;
                return bootstrapData;
              },
            ),
          ),
        );

        // Initial frame
        await tester.pumpAndSettle();

        // Exactly ONE bootstrap request was dispatched
        expect(bootstrapCalls, equals(1));

        // Cards render content supplied directly by bootstrap without independent HTTP calls
        expect(find.text('84'), findsOneWidget);
        expect(find.text('Consistent study streak'), findsOneWidget);
        expect(find.text('Alkanes Revision'), findsOneWidget);
      },
    );

    testWidgets('Partial section degradation leaves remaining cards intact', (
      tester,
    ) async {
      int bootstrapCalls = 0;
      final partialBootstrapData = {
        'profile': {
          'uid': 'student_456',
          'role': 'student',
          'displayName': 'Tanvir',
        },
        'academicHealth': {
          'available': true,
          'score': 72,
          'hasData': true,
          'headline': 'Need more problem practice',
        },
        'coach': {
          'available': false, // Coach failed in backend
          'mission': [],
        },
        'focus': {
          'available': true,
          'minutesDone': 15,
          'goalMinutes': 45,
          'focusScore': 60,
        },
        'recommendation': {
          'available': false, // Recommendations unavailable
          'items': [],
        },
        'generatedAt': '2026-10-03T09:00:00Z',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            role: 'student',
            displayName: 'Tanvir',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
            bootstrapFn: () async {
              bootstrapCalls++;
              return partialBootstrapData;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(bootstrapCalls, equals(1));
      // Academic health card displays score
      expect(find.text('72'), findsOneWidget);
      // Recommendation card shrinks gracefully when unavailable
      expect(find.text('Ziku Suggests'), findsNothing);
    });

    testWidgets('Non-student mode never triggers bootstrap endpoint', (
      tester,
    ) async {
      int bootstrapCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            role: 'general',
            displayName: 'Parent User',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
            bootstrapFn: () async {
              bootstrapCalls++;
              return {};
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      // Zero bootstrap calls for non-student roles
      expect(bootstrapCalls, equals(0));
    });

    testWidgets(
      'Standalone cards without bootstrap preserve dedicated fallback endpoints',
      (tester) async {
        int legacyHealthCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AcademicHealthCard(
                healthFn: () async {
                  legacyHealthCalls++;
                  return {
                    'score': 90,
                    'hasData': true,
                    'headline': 'Excellent work',
                  };
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        // Standalone card mounts and reads its own dedicated endpoint
        expect(legacyHealthCalls, equals(1));
        expect(find.text('90'), findsOneWidget);
      },
    );
  });
}
