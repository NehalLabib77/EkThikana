// Localized short-month labels used by Gochano's date helpers (spec §73).
//
// The previous versions of these helpers hard-coded English month abbreviations
// (`Jan`, `Feb`, …) and so produced exactly the "mixed-language accidental
// strings" `GochanoLanguage` is meant to prevent: a student who had switched
// the whole app to বাংলা still saw English month abbreviations on their
// focus-session history, their task due dates, and their group's shared
// uploads.
//
// The Bangla abbreviations are the forms actually used by Bangla-first
// publications in Bangladesh; they are shorter than the full Bengali
// month names ('জানুয়ারি', 'ফেব্রুয়ারি', …) and so read naturally next to
// a numeric day in a small row caption.

import 'gochano_language.dart';

/// Short month labels for the active language, keyed by 1-based month.
///
/// `months[date.month - 1]` is the conventional call shape; the array is
/// 1-based so callers cannot accidentally drift if the month is changed in
/// place.
const List<String> _englishShortMonths = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _banglaShortMonths = <String>[
  'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
  'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
];

/// Returns the localized short month label for an existing month number
/// (1 = January). Out-of-range values fall back to the English label rather
/// than throwing, since these helpers are usually called on dates that
/// already came from a server-validated ISO string.
String shortMonthLabel(int month) {
  final list =
      GochanoLanguage.isBangla ? _banglaShortMonths : _englishShortMonths;
  if (month < 1 || month > list.length) {
    return _englishShortMonths[(month.clamp(1, 12)) - 1];
  }
  return list[month - 1];
}

/// Formats the day portion of a date in the active language.
///
/// Returns just the day label (e.g. `23 Mar` or `২৩ মার্চ`), so callers stay
/// free to add a time, a year, or a separator to suit their layout.
String formatShortDate(DateTime date) =>
    '${date.day} ${shortMonthLabel(date.month)}';

/// 12-hour clock labels for the active language.
///
/// Bangla rendering follows the same convention as the English labels: a
/// period marker is written *after* the number (`3:20 অপরাহ্ন`), not as a
/// Latin `pm`. This keeps the row caption purely in Bangla when the rest of
/// the screen is Bangla — no mixed-script leak.
String formatClock12(DateTime date) {
  final hour24 = date.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  if (GochanoLanguage.isBangla) {
    final period = hour24 < 12 ? 'পূর্বাহ্ন' : 'অপরাহ্ন';
    return '$hour12:$minute $period';
  }
  final period = hour24 < 12 ? 'am' : 'pm';
  return '$hour12:$minute $period';
}

/// Converts a 24-hour `HH:mm` string to 12-hour format with AM/PM.
///
/// Examples: `'00:30'` → `'12:30 am'`, `'15:23'` → `'3:23 pm'`,
/// `'12:00'` → `'12:00 pm'`.
///
/// Falls back to the original string if parsing fails.
String formatTime12(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return hhmm;
  final hour24 = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour24 == null || minute == null) return hhmm;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final mm = minute.toString().padLeft(2, '0');
  if (GochanoLanguage.isBangla) {
    final period = hour24 < 12 ? 'পূর্বাহ্ন' : 'অপরাহ্ন';
    return '$hour12:$mm $period';
  }
  final period = hour24 < 12 ? 'am' : 'pm';
  return '$hour12:$mm $period';
}
