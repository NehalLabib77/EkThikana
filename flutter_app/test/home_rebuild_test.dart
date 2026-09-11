import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String source;
  late String build;

  setUpAll(() {
    source = _read('lib/features/home/presentation/home_screen.dart');
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final buildEnd = source.indexOf('\n  }', buildStart);
    build = source.substring(buildStart, buildEnd);
  });

  test('Home order is Quick Access, Today, Medicine, Commute, Money', () {
    final quick = build.indexOf('Quick Access');
    final today = build.indexOf('_TodaysTasksCard');
    final medicine = build.indexOf('_MedicineScheduleCard');
    final commute = build.indexOf('_CommuteCard');
    final money = build.indexOf('_MoneyCard');
    expect(quick, greaterThanOrEqualTo(0));
    expect(today, greaterThan(quick));
    expect(medicine, greaterThan(today));
    expect(commute, greaterThan(medicine));
    expect(money, greaterThan(commute));
  });

  test('Today uses Plan task stream and supports assignments', () {
    expect(source, contains("ownerStream('tasks'"));
    expect(source, contains("data['type']?.toString() == 'assignment'"));
    expect(source, contains("'Assignment'"));
    expect(source, contains("'Task'"));
    expect(source, contains('FieldValue.serverTimestamp()'));
  });

  test('Home contains safe medicine, commute, and money states', () {
    expect(source, contains('No medicine scheduled today'));
    expect(source, contains('All medicines taken for today'));
    expect(source, contains('Plan a trip'));
    expect(source, contains('Unable to load budget'));
    expect(source, contains('getRemaining'));
  });

  test('legacy visible dashboard sections are not composed by Home', () {
    expect(build, isNot(contains('_SmartSummaryCard')));
    expect(build, isNot(contains('_StudyProgressCard')));
    expect(build, isNot(contains('_RecentMaterialsCard')));
    expect(build, isNot(contains('_BentoRow')));
  });

  test(
    'profile avatar route remains wired through the existing shell callback',
    () {
      expect(source, contains('onOpenProfile'));
      expect(source, contains('Icons.account_circle_outlined'));
      expect(source, contains('tooltip: GochanoLanguage.text(\'Profile\''));
    },
  );
}
