import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/feedback_messages.dart';
import 'package:gochano/core/localization/gochano_language.dart';

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('FeedbackMessages — Truthful Save & Reminder Confirmation', () {
    test('taskSaved produces truthful messages in English and Bengali', () {
      // 1. Simple task without reminder
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(FeedbackMessages.taskSaved(), equals('Task saved'));
      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(FeedbackMessages.taskSaved(), equals('কাজ সংরক্ষিত হয়েছে'));

      // 2. Assignment without reminder
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(
        FeedbackMessages.taskSaved(isAssignment: true),
        equals('Assignment saved'),
      );
      expect(
        FeedbackMessages.taskSaved(isAssignment: true),
        equals('Assignment saved'),
      );
      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(
        FeedbackMessages.taskSaved(isAssignment: true),
        equals('অ্যাসাইনমেন্ট সংরক্ষিত হয়েছে'),
      );
      expect(
        FeedbackMessages.taskSaved(isAssignment: true),
        equals('অ্যাসাইনমেন্ট সংরক্ষিত হয়েছে'),
      );

      // 3. Task with scheduled reminder
      final remindAt = DateTime(2026, 9, 20, 14, 30);
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(
        FeedbackMessages.taskSaved(remindAt: remindAt),
        contains('Reminder set for 2:30 pm'),
      );
      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(
        FeedbackMessages.taskSaved(remindAt: remindAt),
        contains('রিমাইন্ডার:'),
      );

      // 4. Task saved but reminder scheduling failed (truthful reporting)
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(
        FeedbackMessages.taskSaved(reminderFailed: true),
        equals('Task saved (reminder could not be scheduled)'),
      );
      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(
        FeedbackMessages.taskSaved(reminderFailed: true),
        equals('কাজ সংরক্ষিত, কিন্তু রিমাইন্ডার সেট করা যায়নি'),
      );
    });

    test('expenseSaved produces truthful messages in English and Bengali', () {
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(
        FeedbackMessages.expenseSaved(isEdit: false),
        equals('Expense added'),
      );
      expect(
        FeedbackMessages.expenseSaved(isEdit: true),
        equals('Expense updated'),
      );
      expect(
        FeedbackMessages.expenseSaved(isEdit: false),
        equals('Expense added'),
      );
      expect(
        FeedbackMessages.expenseSaved(isEdit: true),
        equals('Expense updated'),
      );

      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(
        FeedbackMessages.expenseSaved(isEdit: false),
        equals('খরচ যোগ করা হয়েছে'),
      );
      expect(
        FeedbackMessages.expenseSaved(isEdit: true),
        equals('খরচ সংরক্ষিত হয়েছে'),
      );
      expect(
        FeedbackMessages.expenseSaved(isEdit: false),
        equals('খরচ যোগ করা হয়েছে'),
      );
      expect(
        FeedbackMessages.expenseSaved(isEdit: true),
        equals('খরচ সংরক্ষিত হয়েছে'),
      );
    });

    test('medicineSaved produces truthful messages in English and Bengali', () {
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(FeedbackMessages.medicineSaved(), equals('Medicine saved'));
      expect(
        FeedbackMessages.medicineSaved(firstTime: '08:00'),
        contains('Reminder set for 8:00 am'),
      );
      expect(
        FeedbackMessages.medicineSaved(notificationsDenied: true),
        contains('Reminders will not appear until notifications are enabled'),
      );

      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(FeedbackMessages.medicineSaved(), equals('ওষুধ সংরক্ষিত হয়েছে'));
      expect(
        FeedbackMessages.medicineSaved(firstTime: '08:00'),
        contains('রিমাইন্ডার:'),
      );
      expect(
        FeedbackMessages.medicineSaved(notificationsDenied: true),
        contains('সেটিংসে নোটিফিকেশন চালু না করা পর্যন্ত'),
      );
    });

    test('tripPlanned produces truthful messages in English and Bengali', () {
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(FeedbackMessages.tripPlanned(), equals('Trip planned'));
      expect(
        FeedbackMessages.tripPlanned(isEdit: true),
        equals('Trip updated'),
      );
      expect(
        FeedbackMessages.tripPlanned(isEdit: true),
        equals('Trip updated'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderMinutes: 30),
        equals('Trip planned\nReminder: 30 minutes before'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderMinutes: 30, isEdit: true),
        equals('Trip updated\nReminder: 30 minutes before'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderFailed: true),
        equals('Trip planned (reminder could not be scheduled)'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderFailed: true, isEdit: true),
        equals('Trip updated (reminder could not be scheduled)'),
      );

      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(FeedbackMessages.tripPlanned(), equals('যাত্রা পরিকল্পিত হয়েছে'));
      expect(
        FeedbackMessages.tripPlanned(isEdit: true),
        equals('যাত্রা হালনাগাদ হয়েছে'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderMinutes: 30),
        equals('যাত্রা পরিকল্পিত হয়েছে\nরিমাইন্ডার: ৩০ মিনিট আগে'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderMinutes: 30, isEdit: true),
        equals('যাত্রা হালনাগাদ হয়েছে\nরিমাইন্ডার: ৩০ মিনিট আগে'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderFailed: true),
        equals('যাত্রা পরিকল্পিত হয়েছে (রিমাইন্ডার সেট করা যায়নি)'),
      );
      expect(
        FeedbackMessages.tripPlanned(reminderFailed: true, isEdit: true),
        equals('যাত্রা হালনাগাদ হয়েছে (রিমাইন্ডার সেট করা যায়নি)'),
      );
    });

    test('noteSaved produces truthful messages in English and Bengali', () {
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(FeedbackMessages.noteSaved(isEdit: false), equals('Note saved'));
      expect(FeedbackMessages.noteSaved(isEdit: true), equals('Note updated'));

      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(
        FeedbackMessages.noteSaved(isEdit: false),
        equals('নোট সংরক্ষিত হয়েছে'),
      );
      expect(
        FeedbackMessages.noteSaved(isEdit: true),
        equals('নোট হালনাগাদ করা হয়েছে'),
      );
      expect(
        FeedbackMessages.noteSaved(isEdit: false),
        equals('নোট সংরক্ষিত হয়েছে'),
      );
      expect(
        FeedbackMessages.noteSaved(isEdit: true),
        equals('নোট হালনাগাদ করা হয়েছে'),
      );
    });
  });
}
