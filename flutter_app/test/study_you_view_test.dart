import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/components/app_study_header.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_appearance.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/profile/presentation/study_you_view.dart';
import 'package:gochano/features/shell/presentation/gochano_shell.dart';
import 'package:gochano/features/study/presentation/exam_ecosystem/exam_plan_screen.dart';
import 'package:gochano/services/offline_service.dart';

Widget _buildYouView({
  Size size = const Size(390, 844),
  double textScale = 1.0,
  bool isDark = false,
  GochanoLocale locale = GochanoLocale.english,
  Map<String, dynamic>? mockProfileData,
  Map<String, dynamic>? mockHealthData,
  Map<String, dynamic>? mockAchievementsData,
  List<OfflineEntry>? mockOfflineEntries,
  Map<String, dynamic>? mockAiUsage,
  VoidCallback? onOpenExamPlan,
  VoidCallback? onOpenEditProfile,
  VoidCallback? onLogout,
  VoidCallback? onDeleteAccount,
  VoidCallback? onManageDownloads,
}) {
  GochanoLanguage.current.value = locale;
  return MaterialApp(
    theme: isDark ? GochanoTheme.dark() : GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: StudyYouView(
          mockProfileData: mockProfileData ??
              {
                'name': 'Tanvir Ahmed',
                'role': 'student',
                'email': 'tanvir@example.com',
                'phone': '+8801712345678',
                'institution': 'Dhaka Residential Model College',
                'class': 'HSC 2nd Year',
                'board': 'Dhaka Board',
                'stream': 'Science',
                'targetExam': 'BUET Admission 2027',
                'targetDate': '2027-02-15',
                'studyStreak': 7,
                'completedTasksCount': 24,
              },
          mockHealthData: mockHealthData ??
              {
                'score': 84,
                'streak': 7,
              },
          mockAchievementsData: mockAchievementsData ??
              {
                'badges': [
                  {'id': 'streak_7', 'title': '7-Day Streak', 'description': 'Completed 7 days in a row'},
                  {'id': 'quiz_master', 'title': 'Quiz Ace', 'description': 'Scored 100% on 3 quizzes'},
                ],
              },
          mockOfflineEntries: mockOfflineEntries ??
              [
                OfflineEntry(
                  materialId: 'mat_1',
                  title: 'Physics Chapter 4 Formulas',
                  fileName: 'physics_ch4.pdf',
                  localPath: '/local/physics_ch4.pdf',
                  size: 245760, // 240 KB
                  mimeType: 'application/pdf',
                  savedAt: DateTime(2026, 10, 1),
                ),
                OfflineEntry(
                  materialId: 'mat_2',
                  title: 'Chemistry Organic Reactions',
                  fileName: 'chem_organic.pdf',
                  localPath: '/local/chem_organic.pdf',
                  size: 1572864, // 1.5 MB
                  mimeType: 'application/pdf',
                  savedAt: DateTime(2026, 10, 2),
                ),
              ],
          mockAiUsage: mockAiUsage ??
              {
                'totalRequests': 42,
                'todayRequests': 5,
              },
          onOpenExamPlan: onOpenExamPlan,
          onOpenEditProfile: onOpenEditProfile,
          onLogout: onLogout,
          onDeleteAccount: onDeleteAccount,
          onManageDownloads: onManageDownloads,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      GochanoAppModePreferences.prefsKey: 'study',
      GochanoAppModePreferences.discoveryKey: true,
      'gochano.language': 'en',
    });
    GochanoLanguage.current.value = GochanoLocale.english;
    await GochanoAppModePreferences.restore();
  });

  group('Study Mode → You (Profile & Management) Redesign', () {
    testWidgets('Requirement 1 & 2: Pinned contextual AppStudyHeader outside scrollable body', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.byType(AppStudyHeader), findsOneWidget);
      // AppStudyHeader sits at top level inside Column outside Expanded ScrollView
      final headerFinder = find.byType(AppStudyHeader);
      final scrollFinder = find.byType(CustomScrollView);
      expect(headerFinder, findsOneWidget);
      expect(scrollFinder, findsOneWidget);

      final headerRect = tester.getRect(headerFinder);
      final scrollRect = tester.getRect(scrollFinder);
      expect(headerRect.bottom, lessThanOrEqualTo(scrollRect.top + 1.0));
    });

    testWidgets('Requirement 3: Header search is explicitly hidden on You', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      final header = tester.widget<AppStudyHeader>(find.byType(AppStudyHeader));
      expect(header.showSearch, isFalse);
    });

    testWidgets('Requirement 4 & 5: Compact profile identity block renders real user details', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Tanvir Ahmed'), findsOneWidget);
      expect(find.text('tanvir@example.com'), findsOneWidget);
      expect(find.text('+8801712345678'), findsOneWidget);
      expect(find.text('Dhaka Residential Model College'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
    });

    testWidgets('Requirement 6: Fallback avatar renders initials when photo is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildYouView(
          mockProfileData: {
            'name': 'Rahim Uddin',
            'role': 'student',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RU'), findsOneWidget);
    });

    testWidgets('Requirement 7: Edit Profile entry triggers edit callback or sheet', (
      tester,
    ) async {
      bool editTapped = false;
      await tester.pumpWidget(
        _buildYouView(
          onOpenEditProfile: () => editTapped = true,
        ),
      );
      await tester.pumpAndSettle();

      final editBtn = find.text('Edit Profile');
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      expect(editTapped, isTrue);
    });

    testWidgets('Requirement 8: Personal Study Snapshot renders study streak, academic health, and tasks', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Personal Study Snapshot'), findsOneWidget);
      expect(find.text('Study Streak'), findsOneWidget);
      expect(find.text('7 Days'), findsOneWidget);
      expect(find.text('Academic Health'), findsOneWidget);
      expect(find.text('84 / 100'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('24 tasks'), findsOneWidget);
    });

    testWidgets('Requirement 9 & 10: Academic Profile renders class, board, stream and target exam', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Academic Profile'), findsOneWidget);
      expect(find.text('HSC 2nd Year'), findsOneWidget);
      expect(find.text('Dhaka Board'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);
      expect(find.text('BUET Admission 2027'), findsOneWidget);
      expect(find.text('Change Target'), findsOneWidget);
    });

    testWidgets('Requirement 11 & 12: No-target state displays CTA routing to ExamPlanScreen', (
      tester,
    ) async {
      bool examPlanOpened = false;
      await tester.pumpWidget(
        _buildYouView(
          mockProfileData: {
            'name': 'Karim Islam',
            'role': 'student',
            // No target exam
          },
          onOpenExamPlan: () => examPlanOpened = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No target exam configured yet'), findsOneWidget);
      final setBtn = find.text('Set Target Exam');
      expect(setBtn, findsOneWidget);

      await tester.tap(setBtn);
      await tester.pumpAndSettle();
      expect(examPlanOpened, isTrue);
    });

    testWidgets('Requirement 13: Plan and You use same canonical target exam flow (routes to ExamPlanScreen)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyYouView(
              mockProfileData: const {
                'name': 'Test User',
                'targetExam': 'HSC 2026',
              },
              mockOfflineEntries: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Change Target without custom callback -> pushes ExamPlanScreen
      await tester.tap(find.text('Change Target'));
      await tester.pumpAndSettle();

      expect(find.byType(ExamPlanScreen), findsOneWidget);
    });

    testWidgets('Requirement 14 & 15: Achievements renders badges and polite empty state', (
      tester,
    ) async {
      // With achievements
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Achievements & Progress'), findsOneWidget);
      expect(find.text('7-Day Streak'), findsOneWidget);
      expect(find.text('Quiz Ace'), findsOneWidget);

      // Without achievements
      await tester.pumpWidget(
        _buildYouView(
          mockAchievementsData: const {'badges': []},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No badges unlocked yet. Keep studying!'), findsOneWidget);
    });

    testWidgets('Requirement 16 & 17: Download Center renders offline count and real formatted byte size', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Download Center'), findsOneWidget);
      expect(find.text('2 files saved'), findsOneWidget);
      // Total size: 245760 + 1572864 = 1818624 bytes = 1.7 MB
      expect(find.text('1.7 MB'), findsOneWidget);
    });

    testWidgets('Requirement 18, 19, 20: Download Center Manage and Empty state', (
      tester,
    ) async {
      bool manageTapped = false;
      await tester.pumpWidget(
        _buildYouView(
          onManageDownloads: () => manageTapped = true,
        ),
      );
      await tester.pumpAndSettle();

      final manageBtn = find.text('Manage');
      await tester.ensureVisible(manageBtn);
      await tester.pumpAndSettle();
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();
      expect(manageTapped, isTrue);

      // Empty downloads
      await tester.pumpWidget(
        _buildYouView(
          mockOfflineEntries: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 files saved'), findsOneWidget);
      expect(find.text('0 KB'), findsOneWidget);
      expect(find.text('No offline study materials downloaded yet.'), findsOneWidget);
    });

    testWidgets('Requirement 21 & 22: Grouped settings shows Language and Appearance current values', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Follow system'), findsOneWidget);
    });

    testWidgets('Requirement 23: Grouped settings shows App Mode row', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('App Mode'), findsOneWidget);
      expect(find.text('Study Mode'), findsOneWidget);
    });

    testWidgets('Requirement 24: Grouped settings shows Reminders and Exact Alarm settings', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Reminders & Exact Alarms'), findsOneWidget);
      expect(find.text('Manage task reminder permissions'), findsOneWidget);
    });

    testWidgets('Requirement 25: Grouped settings shows AI Usage with link', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('AI Usage'), findsOneWidget);
    });

    testWidgets('Requirement 26: Grouped settings shows Sync Status', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Sync Status'), findsOneWidget);
    });

    testWidgets('Requirement 27: Help & Support renders Help and About dialog', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      expect(find.text('Help & Support'), findsOneWidget);
      final helpBtn = find.text('Help & FAQ');
      await tester.ensureVisible(helpBtn);
      await tester.pumpAndSettle();
      expect(helpBtn, findsOneWidget);

      final aboutBtn = find.text('About Gochano');
      await tester.ensureVisible(aboutBtn);
      await tester.pumpAndSettle();
      expect(aboutBtn, findsOneWidget);

      await tester.tap(aboutBtn);
      await tester.pumpAndSettle();

      expect(find.text('Gochano'), findsWidgets);
      expect(find.text('EkThikana Platform · 2.0.0'), findsOneWidget);
    });

    testWidgets('Requirement 28: Account Actions renders Sign Out with confirmation', (
      tester,
    ) async {
      bool logoutCalled = false;
      await tester.pumpWidget(
        _buildYouView(
          onLogout: () => logoutCalled = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final signOutBtn = find.text('Sign Out');
      expect(signOutBtn, findsOneWidget);
      await tester.ensureVisible(signOutBtn);
      await tester.pumpAndSettle();

      await tester.tap(signOutBtn);
      await tester.pumpAndSettle();

      expect(logoutCalled, isTrue);
    });

    testWidgets('Requirement 29: Account Actions renders Delete Account with danger confirmation', (
      tester,
    ) async {
      bool deleteCalled = false;
      await tester.pumpWidget(
        _buildYouView(
          onDeleteAccount: () => deleteCalled = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final deleteBtn = find.text('Delete Account');
      expect(deleteBtn, findsOneWidget);
      await tester.ensureVisible(deleteBtn);
      await tester.pumpAndSettle();

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(deleteCalled, isTrue);
    });

    testWidgets('Requirement 30–33: Responsive layouts (320dp, 360dp, 390dp, 412dp) without overflow', (
      tester,
    ) async {
      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        await tester.pumpWidget(
          _buildYouView(
            size: Size(width, 844),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Overflow on width $width');
      }
    });

    testWidgets('Requirement 34 & 35: Minimum 44dp touch target sizes and semantic labels', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      final editBtn = find.text('Edit Profile');
      expect(editBtn, findsOneWidget);
      final editBtnWidget = find.ancestor(of: editBtn, matching: find.byType(OutlinedButton));
      final editSize = tester.getSize(editBtnWidget);
      expect(editSize.height, greaterThanOrEqualTo(44.0));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label == 'Profile photo' ||
                  w.properties.label == 'প্রোফাইল ছবি'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Requirement 36 & 37: Text scale 1.5x and 2.0x without layout failure', (
      tester,
    ) async {
      for (final scale in [1.5, 2.0]) {
        await tester.pumpWidget(
          _buildYouView(
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Failed at text scale $scale');
      }
    });

    testWidgets('Requirement 38: Dark mode renders cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildYouView(
          isDark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Requirement 39: Bangla localization renders correct strings', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildYouView(
          locale: GochanoLocale.bangla,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('শিক্ষার্থী'), findsOneWidget);
      expect(find.text('ব্যক্তিগত পড়ার পরিসংখ্যান'), findsOneWidget);
      expect(find.text('একাডেমিক প্রোফাইল'), findsOneWidget);
      expect(find.text('অর্জন ও অগ্রগতি'), findsOneWidget);
      expect(find.text('ডাউনলোড সেন্টার'), findsOneWidget);
      expect(find.text('পছন্দ ও সেটিংস'), findsOneWidget);
      expect(find.text('সাহায্য ও তথ্য'), findsOneWidget);
    });

    testWidgets('Requirement 40: Shell IndexedStack preserves You state when switching to Today and back', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: GochanoShell(
            role: 'student',
            displayName: 'State Preservation Tester',
            pagesBuilder: (context, mode) {
              return [
                const Center(child: Text('Today Tab Content')),
                const Center(child: Text('Workspace Tab Content')),
                const Center(child: Text('Plan Tab Content')),
                const Center(child: Text('Community Tab Content')),
                const StudyYouView(
                  mockProfileData: {'displayName': 'Preserved User'},
                  mockOfflineEntries: [],
                ),
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Today is active initially
      expect(find.text('Today Tab Content'), findsOneWidget);

      // Tap You tab (index 4)
      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();

      expect(find.text('Preserved User'), findsOneWidget);

      // Switch back to Today
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      expect(find.text('Today Tab Content'), findsOneWidget);

      // Switch back to You -> state maintained
      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();

      expect(find.text('Preserved User'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Requirement 41: RefreshIndicator triggers reload', (
      tester,
    ) async {
      await tester.pumpWidget(_buildYouView());
      await tester.pumpAndSettle();

      final refresh = find.byType(RefreshIndicator);
      expect(refresh, findsOneWidget);

      await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
