import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final homeSource = _read('lib/features/home/presentation/home_screen.dart');

  group('Today consumes StudentContext foundation', () {
    test('imports student.dart barrel', () {
      expect(homeSource, contains("import '../../../core/student/student.dart'"));
    });

    test('HomeScreen is a StatefulWidget', () {
      expect(homeSource, contains('class HomeScreen extends StatefulWidget'));
    });

    test('builds StudentContext via StudentContextService.build', () {
      expect(homeSource, contains('StudentContextService.build('));
    });

    test('passes all subsystem data to StudentContextService', () {
      expect(homeSource, contains('taskDocs: _taskDocs'));
      expect(homeSource, contains('medicineDocs: _medicineDocs'));
      expect(homeSource, contains('doseDocs: _doseDocs'));
      expect(homeSource, contains('financialSummary: _financialSummary'));
      expect(homeSource, contains('moneyRawFields: _moneyRawFields'));
      expect(homeSource, contains('communityGroupCount: _communityGroupCount'));
    });
  });

  group('No duplicate persistence', () {
    test('does not write to student_events collection', () {
      expect(homeSource, isNot(contains("collection('student_events')")));
    });

    test('single ownerStream tasks call', () {
      final count = "ownerStream('tasks'".allMatches(homeSource).length;
      expect(count, 1);
    });
  });

  group('Now/Next priority', () {
    test('has documented priority function', () {
      expect(homeSource, contains('_pickPriorityEvent'));
      expect(homeSource, contains('overdueEvents'));
      expect(homeSource, contains('StudentEventType.medicine'));
      expect(homeSource, contains('StudentEventStatus.pending'));
      expect(homeSource, contains('upcomingEvents'));
    });

    test('shows NowNextCard for high-priority events', () {
      expect(homeSource, contains('_NowNextCard'));
    });

    test('hides NowNext when no events', () {
      expect(homeSource, contains('SizedBox.shrink()'));
    });
  });

  group('Today schedule', () {
    test('uses ctx.todayEvents', () {
      expect(homeSource, contains('ctx.todayEvents'));
    });

    test('limits visible items to 5', () {
      expect(homeSource, contains('i < 5'));
    });

    test('shows +N more when > 5 events', () {
      expect(homeSource, contains('more'));
    });

    test('empty state shows calm message', () {
      expect(homeSource, contains('All clear today.'));
    });

    test('displays overdue badge', () {
      expect(homeSource, contains('overdueEvents.length'));
    });
  });

  group('Study snapshot', () {
    test('uses StudentContext.studySummary', () {
      expect(homeSource, contains('ctx.studySummary'));
    });

    test('shows total tasks', () {
      expect(homeSource, contains('summary.totalTasks'));
    });

    test('shows overdue count when > 0', () {
      expect(homeSource, contains('summary.overdueCount'));
    });

    test('handles null summary gracefully', () {
      expect(homeSource, contains('summary == null'));
    });
  });

  group('Medicine snapshot', () {
    test('uses StudentContext.pendingMedicine', () {
      expect(homeSource, contains('ctx.pendingMedicine'));
    });

    test('shows pending count', () {
      expect(homeSource, contains('pendingMedicine.length'));
    });

    test('shows all-done state', () {
      expect(homeSource, contains('All done for today'));
    });

    test('taps open MedicineScreen', () {
      expect(homeSource, contains('MedicineScreen()'));
    });
  });

  group('Money snapshot', () {
    test('uses StudentContext.moneySummary', () {
      expect(homeSource, contains('ctx.moneySummary'));
    });

    test('shows adjustedRemaining (authoritative formula)', () {
      expect(homeSource, contains('money.adjustedRemaining'));
    });

    test('shows totalSpent', () {
      expect(homeSource, contains('money.totalSpent'));
    });

    test('handles null money gracefully (not zero)', () {
      expect(homeSource, contains('money == null'));
      expect(homeSource, contains('Unable to load budget'));
    });
  });

  group('Quick actions', () {
    test('contains exactly 4 actions', () {
      expect(homeSource, contains('AiAssistantScreen'));
      expect(homeSource, contains('showAddExpenseSheet'));
      expect(homeSource, contains('MedicineScreen'));
      expect(homeSource, contains('CommuteScreen'));
    });

    test('uses 4-column grid', () {
      expect(homeSource, contains('crossAxisCount: 4'));
    });
  });

  group('Canonical navigation', () {
    test('schedule navigates to Study Plan', () {
      expect(homeSource, contains('StudyTab.plan.tabIndex'));
    });

    test('money snapshot routes to canonical Money area', () {
      expect(homeSource, contains('onOpenDestination(StudentArea.money.tabIndex)'));
    });

    test('Add Expense quick action still calls showAddExpenseSheet', () {
      expect(homeSource, contains('showAddExpenseSheet'));
    });
  });

  group('EN/BN labels', () {
    test('bilingual strings used', () {
      expect(homeSource, contains("GochanoLanguage.text('Today', '\u0986\u099c')"));
      expect(homeSource, contains("GochanoLanguage.text('Money', '\u099f\u09be\u0995\u09be')"));
      expect(homeSource, contains("GochanoLanguage.text('Medicine', '\u0993\u09b7\u09c1\u09a7')"));
      expect(homeSource, contains("GochanoLanguage.text('Study', '\u09aa\u09a1\u09bc\u09be\u09b6\u09cb\u09a8\u09be')"));
    });
  });

  group('Removed features remain absent', () {
    test('no Focus', () {
      expect(homeSource, isNot(contains('Focus')));
    });
    test('no Insights', () {
      expect(homeSource, isNot(contains('Insights')));
    });
    test('no Rewards/XP/Gems', () {
      expect(homeSource, isNot(contains('Rewards')));
      expect(homeSource, isNot(contains('XP')));
      expect(homeSource, isNot(contains('Gems')));
    });
    test('no Study Goal', () {
      expect(homeSource, isNot(contains('Study Goal')));
    });
    test('no OCR', () {
      expect(homeSource, isNot(contains('OCR')));
    });
  });

  group('No automatic AI call', () {
    test('no groq/gemini import', () {
      expect(homeSource, isNot(contains('groq')));
      expect(homeSource, isNot(contains('gemini')));
    });
    test('no AI call in build', () {
      expect(homeSource, isNot(contains('generateContent')));
      expect(homeSource, isNot(contains('chatCompletion')));
    });
  });

  group('No automatic Commute API', () {
    test('no commute route API on load', () {
      expect(homeSource, isNot(contains('commuteRoutes(')));
      expect(homeSource, isNot(contains('commuteSingleFare(')));
    });
  });

  group('Partial subsystem failure', () {
    test('independent error handlers', () {
      final count = 'onError: (_)'.allMatches(homeSource).length;
      expect(count, greaterThanOrEqualTo(4));
    });

    test('handles null study summary', () {
      expect(homeSource, contains('summary == null'));
    });

    test('handles null money', () {
      expect(homeSource, contains('money == null'));
    });
  });

  group('Header', () {
    test('shows Today title', () {
      expect(homeSource, contains("GochanoLanguage.text('Today'"));
    });

    test('shows localized date', () {
      expect(homeSource, contains('formatShortDate'));
    });

    test('profile tappable to ProfileScreen', () {
      expect(homeSource, contains('ProfileScreen(role: role)'));
    });

    test('language toggle present', () {
      expect(homeSource, contains('LanguageToggle()'));
    });
  });

  group('Performance', () {
    test('all ownerStream calls have limits', () {
      expect(homeSource, contains('limit: 100'));
      expect(homeSource, contains('limit: 50'));
    });

    test('no ApiService.getStudyStats (old pattern removed)', () {
      expect(homeSource, isNot(contains('ApiService.getStudyStats')));
    });
  });
}
