// Canonical bilingual save and reminder confirmation messages (spec Phase 1).
//
// Ensures consistent, truthful feedback across all creation workflows:
//   * Only promises a reminder when a reminder is actually scheduled.
//   * Truthfully reports when saving succeeded but reminder scheduling failed.
//   * Formats 12-hour times in the active language without script leaks.

import 'gochano_dates.dart';
import 'gochano_language.dart';

class FeedbackMessages {
  FeedbackMessages._();

  static String taskSaved({
    bool isAssignment = false,
    DateTime? remindAt,
    bool reminderFailed = false,
    bool isOffline = false,
  }) {
    if (isOffline) {
      return GochanoLanguage.text(
        isAssignment
            ? 'Assignment saved offline. Will sync when internet returns.'
            : 'Saved offline. Will sync when internet returns.',
        isAssignment
            ? 'অ্যাসাইনমেন্ট অফলাইনে সংরক্ষিত। ইন্টারনেট ফিরলে সিঙ্ক হবে।'
            : 'অফলাইনে সংরক্ষিত। ইন্টারনেট ফিরলে সিঙ্ক হবে।',
      );
    }
    if (reminderFailed) {
      return GochanoLanguage.text(
        isAssignment
            ? 'Assignment saved (reminder could not be scheduled)'
            : 'Task saved (reminder could not be scheduled)',
        isAssignment
            ? 'অ্যাসাইনমেন্ট সংরক্ষিত, কিন্তু রিমাইন্ডার সেট করা যায়নি'
            : 'কাজ সংরক্ষিত, কিন্তু রিমাইন্ডার সেট করা যায়নি',
      );
    }
    if (remindAt != null) {
      final timeStr = formatClock12(remindAt);
      return GochanoLanguage.text(
        isAssignment
            ? 'Assignment saved\nReminder set for $timeStr'
            : 'Task saved\nReminder set for $timeStr',
        isAssignment
            ? 'অ্যাসাইনমেন্ট সংরক্ষিত হয়েছে\nরিমাইন্ডার: $timeStr'
            : 'কাজ সংরক্ষিত হয়েছে\nরিমাইন্ডার: $timeStr',
      );
    }
    return GochanoLanguage.text(
      isAssignment ? 'Assignment saved' : 'Task saved',
      isAssignment ? 'অ্যাসাইনমেন্ট সংরক্ষিত হয়েছে' : 'কাজ সংরক্ষিত হয়েছে',
    );
  }

  static String expenseSaved({bool isEdit = false, bool isOffline = false}) {
    if (isOffline) {
      return GochanoLanguage.text('Saved locally.', 'ডিভাইসে সংরক্ষিত হয়েছে।');
    }
    return GochanoLanguage.text(
      isEdit ? 'Expense updated' : 'Expense added',
      isEdit ? 'খরচ সংরক্ষিত হয়েছে' : 'খরচ যোগ করা হয়েছে',
    );
  }

  static String medicineSaved({
    String? firstTime,
    bool notificationsDenied = false,
    bool isOffline = false,
  }) {
    if (isOffline) {
      return GochanoLanguage.text(
        'Reminder saved. Sync pending.',
        'রিমাইন্ডার সংরক্ষিত। সিঙ্ক অপেক্ষায়।',
      );
    }
    if (notificationsDenied) {
      return GochanoLanguage.text(
        'Saved. Reminders will not appear until notifications are enabled in settings.',
        'সংরক্ষিত হয়েছে। সেটিংসে নোটিফিকেশন চালু না করা পর্যন্ত রিমাইন্ডার দেখা যাবে না।',
      );
    }
    if (firstTime != null && firstTime.isNotEmpty) {
      final timeStr = formatTime12(firstTime);
      return GochanoLanguage.text(
        'Medicine saved\nReminder set for $timeStr',
        'ওষুধ সংরক্ষিত হয়েছে\nরিমাইন্ডার: $timeStr',
      );
    }
    return GochanoLanguage.text('Medicine saved', 'ওষুধ সংরক্ষিত হয়েছে');
  }

  static String tripPlanned({
    int reminderMinutes = 0,
    bool reminderFailed = false,
    bool isEdit = false,
    bool isOffline = false,
  }) {
    if (isOffline) {
      return GochanoLanguage.text(
        'Trip planned offline. Will sync when internet returns.',
        'অফলাইনে যাত্রা পরিকল্পিত। ইন্টারনেট ফিরলে সিঙ্ক হবে।',
      );
    }
    if (reminderFailed) {
      return GochanoLanguage.text(
        isEdit
            ? 'Trip updated (reminder could not be scheduled)'
            : 'Trip planned (reminder could not be scheduled)',
        isEdit
            ? 'যাত্রা হালনাগাদ হয়েছে (রিমাইন্ডার সেট করা যায়নি)'
            : 'যাত্রা পরিকল্পিত হয়েছে (রিমাইন্ডার সেট করা যায়নি)',
      );
    }
    if (reminderMinutes > 0) {
      final bnMinutes = reminderMinutes == 60
          ? '১ ঘণ্টা'
          : '${GochanoLanguage.toBanglaDigits(reminderMinutes)} মিনিট';
      return GochanoLanguage.text(
        isEdit
            ? 'Trip updated\nReminder: $reminderMinutes minutes before'
            : 'Trip planned\nReminder: $reminderMinutes minutes before',
        isEdit
            ? 'যাত্রা হালনাগাদ হয়েছে\nরিমাইন্ডার: $bnMinutes আগে'
            : 'যাত্রা পরিকল্পিত হয়েছে\nরিমাইন্ডার: $bnMinutes আগে',
      );
    }
    return GochanoLanguage.text(
      isEdit ? 'Trip updated' : 'Trip planned',
      isEdit ? 'যাত্রা হালনাগাদ হয়েছে' : 'যাত্রা পরিকল্পিত হয়েছে',
    );
  }

  static String noteSaved({bool isEdit = false}) {
    return GochanoLanguage.text(
      isEdit ? 'Note updated' : 'Note saved',
      isEdit ? 'নোট হালনাগাদ করা হয়েছে' : 'নোট সংরক্ষিত হয়েছে',
    );
  }
}
