import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/services/usage_stats_service.dart';

void main() {
  final day = DateTime(2026, 9, 5);
  final start = day;
  final end = day.add(const Duration(hours: 3));

  UsageEventSample event(String packageName, int hour, int type) {
    return UsageEventSample(
      packageName: packageName,
      timestamp: day.add(Duration(hours: hour)),
      eventType: type,
    );
  }

  test(
    'duplicate resumed events and app switching count one foreground app',
    () {
      final totals = UsageSessionCalculator.calculate(
        [
          event('app.one', 0, 1),
          event('app.one', 0, 19),
          event('app.one', 1, 2),
          event('app.two', 1, 19),
          event('app.two', 2, 20),
        ],
        start: start,
        end: end,
      );

      expect(totals['app.one'], const Duration(hours: 1).inMilliseconds);
      expect(totals['app.two'], const Duration(hours: 1).inMilliseconds);
    },
  );

  test('unmatched foreground closes at the requested local day end', () {
    final totals = UsageSessionCalculator.calculate(
      [event('app.one', 2, 1)],
      start: start,
      end: end,
    );

    expect(totals['app.one'], const Duration(hours: 1).inMilliseconds);
  });

  test('background from another package cannot close the active app', () {
    final totals = UsageSessionCalculator.calculate(
      [event('app.one', 0, 1), event('app.two', 1, 20)],
      start: start,
      end: end,
    );

    expect(totals['app.one'], const Duration(hours: 3).inMilliseconds);
    expect(totals.containsKey('app.two'), isFalse);
  });

  test('system and launcher packages do not contribute usage', () {
    final totals = UsageSessionCalculator.calculate(
      [
        event('com.android.systemui', 0, 1),
        event('com.android.systemui', 1, 2),
        event('com.example.launcher', 1, 1),
        event('com.example.launcher', 2, 2),
      ],
      start: start,
      end: end,
    );

    expect(totals, isEmpty);
  });

  test('historical windows end at the next local midnight', () {
    final historicalEnd = day.add(const Duration(days: 1));
    final totals = UsageSessionCalculator.calculate(
      [
        UsageEventSample(
          packageName: 'app.one',
          timestamp: day.subtract(const Duration(minutes: 5)),
          eventType: 1,
        ),
      ],
      start: start,
      end: historicalEnd,
    );

    expect(totals['app.one'], const Duration(days: 1).inMilliseconds);
  });
}
