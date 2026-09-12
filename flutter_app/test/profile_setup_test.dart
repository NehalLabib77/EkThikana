// Profile Setup UI simplification — Name + Student Only.
//
// After a new telecom user authenticates, the Profile Setup screen should
// contain only:
//   1. Full Name (editable, required)
//   2. Account type (fixed: Student, display-only)
//
// The verified phone number must NOT be displayed as an input field or
// visible form row, but must still be written to users/{uid}.phone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('ProfileSetupScreen UI shape', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/auth/presentation/profile_setup_screen.dart',
      ),
    );

    test('Full Name is the only editable input field', () {
      // Must have exactly one TextFormField for name entry
      final textFormFields = RegExp(r'TextFormField\(').allMatches(source);
      // After simplification: only TextFormField should be the name field
      expect(
        textFormFields.length,
        equals(1),
        reason: 'Only one TextFormField (Full Name) should exist',
      );
    });

    test('Full Name label is present with EN/BN copy', () {
      expect(source, contains("'Full name'"));
      expect(source, contains("'পূর্ণ নাম'"));
    });

    test('Full Name field has textCapitalization.words', () {
      expect(source, contains('textCapitalization: TextCapitalization.words'));
    });

    test('Full Name has a validator that rejects empty input', () {
      expect(source, contains("'Please enter your name'"));
      expect(source, contains("'আপনার নাম লিখুন'"));
    });

    test('Account type is shown as fixed Student display', () {
      expect(source, contains("'Account type'"));
      expect(source, contains("'অ্যাকাউন্টের ধরন'"));
      expect(source, contains("'Student'"));
      expect(source, contains("'শিক্ষার্থী'"));
    });

    test('Account type is display-only (Row with Text, no TextFormField)', () {
      // After Account type label, the value must be a plain Row with Text,
      // not a TextFormField
      final accountTypeIdx = source.indexOf("'Account type'");
      final continueIdx = source.indexOf('Continue', accountTypeIdx);
      final accountSection = source.substring(accountTypeIdx, continueIdx);
      expect(accountSection, contains('Row('));
      expect(accountSection, isNot(contains('TextFormField')));
    });

    test('no visible editable phone field exists', () {
      expect(source, isNot(contains("'Phone number'")));
      expect(source, isNot(contains("'ফোন নম্বর'")));
      expect(
        source,
        isNot(contains("initialValue: widget.phone")),
        reason: 'Phone must not be displayed in any TextFormField',
      );
    });

    test('phone constructor parameter is retained internally', () {
      expect(source, contains('required this.phone'));
      expect(source, contains('final String phone'));
    });

    test('Continue button is present with EN/BN copy', () {
      expect(source, contains("'Continue'"));
      expect(source, contains("'চালিয়ে যান'"));
    });

    test('LanguageToggle is present', () {
      expect(source, contains('LanguageToggle()'));
    });

    test('screen is a StatefulWidget', () {
      expect(source, contains('extends StatefulWidget'));
    });
  });

  group('ProfileSetupScreen Firestore write semantics', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/auth/presentation/profile_setup_screen.dart',
      ),
    );

    test('phone is written to Firestore from widget.phone', () {
      expect(
        source,
        contains("'phone': widget.phone"),
        reason: 'Phone must come from the constructor, not a text field',
      );
    });

    test('displayName is written from the name controller', () {
      expect(source, contains("'displayName': name"));
      expect(source, contains('_nameController.text.trim()'));
    });

    test('role is written as "student"', () {
      expect(source, contains("'role': 'student'"));
    });

    test('write uses SetOptions(merge: true)', () {
      expect(source, contains('SetOptions(merge: true)'));
    });

    test('uses users collection with user.uid', () {
      expect(source, contains("collection('users').doc(user.uid)"));
    });

    test('calls FirestoreService.profile() after save', () {
      expect(source, contains('FirestoreService.profile()'));
    });

    test('navigates to GochanoShell after successful save', () {
      expect(source, contains('GochanoShell('));
      expect(source, contains("role: 'student'"));
    });

    test('pushAndRemoveUntil clears the navigation stack', () {
      expect(source, contains('pushAndRemoveUntil'));
    });
  });

  group('ProfileSetupScreen bilingual support', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/auth/presentation/profile_setup_screen.dart',
      ),
    );

    test('GochanoLanguage.text() is used for all user-visible strings', () {
      // Count GochanoLanguage.text occurrences — must have several
      final matches = RegExp(r'GochanoLanguage\.text\(').allMatches(source);
      expect(
        matches.length,
        greaterThanOrEqualTo(5),
        reason: 'At least 5 bilingual text calls expected (heading, '
            'subtitle, name label, name hint, name error, account type, '
            'account type value, continue button)',
      );
    });

    test('BN strings match spec', () {
      expect(source, contains("'পূর্ণ নাম'"));
      expect(source, contains("'অ্যাকাউন্টের ধরন'"));
      expect(source, contains("'শিক্ষার্থী'"));
      expect(source, contains("'চালিয়ে যান'"));
    });

    test('EN strings match spec', () {
      expect(source, contains("'Full name'"));
      expect(source, contains("'Account type'"));
      expect(source, contains("'Student'"));
      expect(source, contains("'Continue'"));
    });
  });

  group('ProfileSetupScreen error and loading behavior', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/auth/presentation/profile_setup_screen.dart',
      ),
    );

    test('saving state is tracked', () {
      expect(source, contains('bool _saving = false'));
    });

    test('error text is displayed in an error card', () {
      expect(source, contains('Icons.error_outline'));
      expect(source, contains('_errorText'));
    });

    test('session-expired error is shown when no Firebase user', () {
      expect(source, contains("'Session expired. Please sign in again.'"));
      expect(
        source,
        contains("'সেশন শেষ হয়ে গেছে। আবার সাইন ইন করুন।'"),
      );
    });

    test('catch block shows save-failure error', () {
      expect(
        source,
        contains("'Could not save your profile. Please try again.'"),
      );
      expect(
        source,
        contains("'আপনার প্রোফাইল সেভ করা যায়নি। আবার চেষ্টা করুন।'"),
      );
    });

    test('PrimaryButton shows busy indicator while saving', () {
      expect(source, contains('busy: _saving'));
    });

    test('form validation is checked before save', () {
      expect(source, contains('_formKey.currentState!.validate()'));
    });
  });
}
