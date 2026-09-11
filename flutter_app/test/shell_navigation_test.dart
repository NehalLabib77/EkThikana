import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String shell;
  late String home;

  setUpAll(() {
    shell = _read('lib/features/shell/presentation/gochano_shell.dart');
    home = _read('lib/features/home/presentation/home_screen.dart');
  });

  test(
    'student navigation order is Today, Study, Commute, Money, Community',
    () {
      final studentStart = shell.indexOf(
        'List<_Destination> _buildDestinations',
      );
      final firstReturn = shell.indexOf('\n      return [', studentStart);
      final generalStart = shell.indexOf('\n    return [', firstReturn + 1);
      final student = shell.substring(studentStart, generalStart);

      final labels = ['Today', 'Study', 'Commute', 'Money', 'Community'];
      var previous = -1;
      for (final label in labels) {
        final index = student.indexOf("'$label'");
        expect(index, greaterThan(previous), reason: '$label order is wrong');
        previous = index;
      }
      expect(student, isNot(contains("'Profile'")));
    },
  );

  test('student pages reuse Commute and Expense screens', () {
    expect(shell, contains('const CommuteScreen()'));
    expect(shell, contains('const ExpenseScreen()'));
  });

  test('Today exposes a normal profile push entry', () {
    expect(home, contains('onOpenProfile'));
    expect(home, contains('Icons.account_circle_outlined'));
    expect(shell, contains('GochanoRoute.to'));
    expect(shell, contains('ProfileScreen(role: widget.role)'));
  });

  test('general-account destinations remain present', () {
    final generalStart = shell.indexOf(
      '\n    return [',
      shell.indexOf('if (_isStudent)'),
    );
    final general = shell.substring(generalStart);
    expect(general, contains("'Life'"));
    expect(general, contains("'Tasks'"));
    expect(general, contains("'Profile'"));
  });
}
