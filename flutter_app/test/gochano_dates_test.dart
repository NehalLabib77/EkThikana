// Regression tests for the localized date helpers.
//
// These exist because the previous version of `_dayLabel` (focus view) and
// `_dueLabel` (tasks) hard-coded English month abbreviations and `am`/`pm`,
// producing exactly the "mixed-language accidental strings" `GochanoLanguage`
// is meant to prevent — a student with the app in বাংলা still saw English
// months on their Recent focus sessions and English am/pm on their tasks.

import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/localization/gochano_dates.dart';
import 'package:gochano/core/localization/gochano_language.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The shared `GochanoLanguage.current` is a global; resetting to English
    // between tests means the test order cannot influence the result.
    await GochanoLanguage.select(GochanoLocale.english);
  });

  group('shortMonthLabel', () {
    test('English short months are returned when the app is English', () {
      const expected = <String>[
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(shortMonthLabel(month), expected[month - 1],
            reason: 'month $month should be ${expected[month - 1]}');
      }
    });

    test('Bangla short months are returned when the app is Bangla', () async {
      await GochanoLanguage.select(GochanoLocale.bangla);
      const expected = <String>[
        'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
        'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(shortMonthLabel(month), expected[month - 1],
            reason: 'month $month should be ${expected[month - 1]}');
      }
    });

    test('out-of-range months do not throw and fall back to English', () {
      // The helper clamps the index into the 12-month array, so values that
      // would otherwise throw are coerced to the first or last real label
      // rather than crashing the row caption.
      expect(shortMonthLabel(0), 'Jan');   // clamped up to 1 → Jan
      expect(shortMonthLabel(13), 'Dec');  // clamped down to 12 → Dec
      expect(shortMonthLabel(-1), 'Jan');  // clamped up to 1 → Jan
    });
  });

  group('formatShortDate', () {
    test('uses English month in English mode', () {
      expect(formatShortDate(DateTime(2025, 3, 23)), '23 Mar');
    });

    test('uses Bangla month in Bangla mode — no English leak', () async {
      await GochanoLanguage.select(GochanoLocale.bangla);
      // The rest of Gochano writes the *day* in Arabic numerals (the only
      // Bangla digit in the codebase is a single literary "৫ম"); only the
      // month is localised.
      final label = formatShortDate(DateTime(2025, 3, 23));
      expect(label, '23 মার্চ');
      // Defensive: the Bangla label must not contain any English month name.
      for (final en in const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ]) {
        expect(label.contains(en), isFalse,
            reason: 'Bangla date "$label" leaked English month "$en"');
      }
    });
  });

  group('formatClock12', () {
    test('uses am/pm in English mode', () {
      expect(formatClock12(DateTime(2025, 1, 1, 3, 20)), '3:20 am');
      expect(formatClock12(DateTime(2025, 1, 1, 15, 20)), '3:20 pm');
      expect(formatClock12(DateTime(2025, 1, 1, 0, 5)), '12:05 am');
      expect(formatClock12(DateTime(2025, 1, 1, 12, 5)), '12:05 pm');
    });

    test('uses বাংলা period markers in Bangla mode — no am/pm leak', () async {
      await GochanoLanguage.select(GochanoLocale.bangla);
      final morning = formatClock12(DateTime(2025, 1, 1, 9, 0));
      final evening = formatClock12(DateTime(2025, 1, 1, 21, 30));
      expect(morning.endsWith('পূর্বাহ্ন'), isTrue,
          reason: 'Bangla morning should end with পূর্বাহ্ন, got "$morning"');
      expect(evening.endsWith('অপরাহ্ন'), isTrue,
          reason: 'Bangla evening should end with অপরাহ্ন, got "$evening"');
      // Defensive: no English period markers in a Bangla clock.
      expect(morning.contains('am') || morning.contains('pm'), isFalse);
      expect(evening.contains('am') || evening.contains('pm'), isFalse);
    });
  });
}
