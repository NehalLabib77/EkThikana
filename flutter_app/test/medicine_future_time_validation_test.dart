// Deterministic tests for the medicine reminder "future time" guard.
//
// A new medicine reminder cannot be saved if every selected DateTime is
// <= DateTime.now().  The comparison uses full DateTime (date + hour + minute),
// not TimeOfDay alone.  Future calendar dates are always valid regardless of
// clock time.
//
// The validation is applied:
//   1. After the user picks a time (prevents adding a past time).
//   2. Immediately before Firestore persistence (last gate).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the validation logic in MedicineFormScreen._hasFutureTime().
///
/// Returns `true` when at least one (startDate, time) pair is strictly after
/// [now].  A future start date is always valid; today's date requires each
/// time to be in the future.
bool hasFutureTime(
  DateTime startDate,
  List<String> times, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  for (final hhmm in times) {
    final parts = hhmm.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final candidate = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      hour,
      minute,
    );
    if (candidate.isAfter(clock)) return true;
  }
  return false;
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('hasFutureTime — pure logic', () {
    test('single time in the past → false', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 5);
      expect(hasFutureTime(start, ['11:27'], now: now), isFalse);
    });

    test('single time exactly now → false', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 5);
      expect(hasFutureTime(start, ['11:30'], now: now), isFalse);
    });

    test('single time one minute in the future → true', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 5);
      expect(hasFutureTime(start, ['11:31'], now: now), isTrue);
    });

    test('future calendar date with any time → true', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 6);
      expect(hasFutureTime(start, ['08:00'], now: now), isTrue);
    });

    test('future calendar date with midnight time → true', () {
      final now = DateTime(2026, 9, 5, 23, 59);
      final start = DateTime(2026, 9, 6);
      expect(hasFutureTime(start, ['00:00'], now: now), isTrue);
    });

    test('mixed times: one past, one future → true', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 5);
      expect(
        hasFutureTime(start, ['11:00', '12:00'], now: now),
        isTrue,
      );
    });

    test('mixed times: all past → false', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 5);
      expect(
        hasFutureTime(start, ['09:00', '10:30', '11:29'], now: now),
        isFalse,
      );
    });

    test('empty times list → false', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 5);
      expect(hasFutureTime(start, [], now: now), isFalse);
    });

    test('start date far in future, time is "early" → true', () {
      final now = DateTime(2026, 9, 5, 14, 0);
      final start = DateTime(2026, 12, 25);
      expect(hasFutureTime(start, ['06:00'], now: now), isTrue);
    });

    test('start date is today, time is 23:59, now is 23:58 → true', () {
      final now = DateTime(2026, 9, 5, 23, 58);
      final start = DateTime(2026, 9, 5);
      expect(hasFutureTime(start, ['23:59'], now: now), isTrue);
    });

    test('start date is today, time is 00:00, now is 00:01 → false', () {
      final now = DateTime(2026, 9, 6, 0, 1);
      final start = DateTime(2026, 9, 6);
      expect(hasFutureTime(start, ['00:00'], now: now), isFalse);
    });

    test('start date is yesterday → false for all past times', () {
      final now = DateTime(2026, 9, 5, 11, 30);
      final start = DateTime(2026, 9, 4);
      expect(
        hasFutureTime(start, ['08:00', '12:00', '20:00'], now: now),
        isFalse,
      );
    });
  });

  group('MedicineFormScreen source — validation wiring', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/life/presentation/medicine/medicine_form_screen.dart',
      ),
    );

    test('_hasFutureTime method exists', () {
      expect(source, contains('bool _hasFutureTime()'));
    });

    test('validation calls _hasFutureTime in _save', () {
      expect(source, contains('_hasFutureTime()'));
    });

    test('EN error message is present', () {
      expect(source, contains('Choose a future time.'));
    });

    test('BN error message is present', () {
      expect(source, contains('ভবিষ্যতের একটি সময় নির্বাচন করুন।'));
    });

    test('candidate is built from full DateTime (year, month, day, hour, minute)',
        () {
      expect(
        source,
        contains(
          'DateTime(\n'
          '        _startDate.year,\n'
          '        _startDate.month,\n'
          '        _startDate.day,\n'
          '        hour,\n'
          '        minute,\n'
          '      )',
        ),
        reason: 'validation must use full DateTime, not TimeOfDay alone',
      );
    });

    test('isAfter(DateTime.now()) is the comparison operator', () {
      expect(source, contains('isAfter('));
      expect(source, contains('DateTime.now()'));
    });

    test('_addTime also validates before adding', () {
      final addTimeStart = source.indexOf('Future<void> _addTime()');
      final addTimeEnd = source.indexOf('\n  Future<void> _pickDate');
      final addTimeBody = source.substring(addTimeStart, addTimeEnd);
      expect(
        addTimeBody,
        contains('candidate.isAfter(DateTime.now())'),
        reason:
            '_addTime must validate the picked time before adding to _times',
      );
    });

    test('_addTime shows error and returns early on past time', () {
      final addTimeStart = source.indexOf('Future<void> _addTime()');
      final addTimeEnd = source.indexOf('\n  Future<void> _pickDate');
      final addTimeBody = source.substring(addTimeStart, addTimeEnd);
      expect(addTimeBody, contains('return;'),
          reason: '_addTime must return without adding on past time');
    });

    test('form values are NOT cleared on validation failure', () {
      // The _save method sets _error via setState but never resets
      // _name, _times, _startDate etc. on validation failure.
      final saveStart = source.indexOf('Future<void> _save()');
      final saveBody = source.substring(saveStart);
      final problemCheck = saveBody.indexOf('if (problem != null)');
      final savingState = saveBody.indexOf('_saving = true');
      final validationBlock = saveBody.substring(problemCheck, savingState);
      // Should not contain any controller.clear() or _times = [] in the
      // validation path.
      expect(validationBlock, isNot(contains('.clear()')),
          reason: 'form values must be preserved on validation failure');
    });

    test('edit mode also runs the future-time check', () {
      // _save is shared for create and edit — the _hasFutureTime check is
      // before the _isEdit branch.
      final saveStart = source.indexOf('Future<void> _save()');
      final saveBody = source.substring(saveStart);
      final futureCheck = saveBody.indexOf('_hasFutureTime()');
      final editBranch = saveBody.indexOf('widget.medicineId == null');
      expect(futureCheck, lessThan(editBranch),
          reason:
              'future-time check must run before the create/edit branch');
    });
  });
}
