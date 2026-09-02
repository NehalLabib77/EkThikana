// Static guards for the Profile "Privacy and data" compact-surface redesign
// (spec §74).
//
// The brief: remove "Export my data" from the Privacy card, isolate the
// destructive "Delete my account" action in its own tinted card, and keep
// the Sign-out button as the only other account-leaving affordance on the
// screen.
//
// Every check below is a string-level guard so it runs without a Firestore
// emulator or a running backend.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final profile =
      _read('lib/features/profile/presentation/profile_screen.dart');

  group('Compact Profile privacy redesign', () {
    test('removes "Export my data" from the Privacy card', () {
      expect(
        profile.contains("'Export my data'"),
        isFalse,
        reason: 'Export my data tile must be removed from the privacy card',
      );
    });

    test('keeps "Delete my account" on the privacy surface', () {
      expect(
        profile.contains("'Delete my account'"),
        isTrue,
        reason: 'Delete my account must remain reachable from the screen',
      );
    });

    test('isolates destructive action in a tinted AppCard', () {
      // The destructive card uses AppCard + accent: colors.error. The AppCard
      // body can contain nested parens (e.g. the child: Row(...) ), so a
      // naive [^)]* scan stops too early — we walk parens manually instead.
      String? privacyBody;
      int i = 0;
      while (i < profile.length) {
        final at = profile.indexOf('AppCard(', i);
        if (at < 0) break;
        int depth = 0;
        int end = -1;
        for (int j = at; j < profile.length; j++) {
          final ch = profile[j];
          if (ch == '(') {
            depth++;
          } else if (ch == ')') {
            depth--;
            if (depth == 0) {
              end = j;
              break;
            }
          }
        }
        if (end < 0) break;
        final body = profile.substring(at, end + 1);
        if (body.contains('accent:') &&
            body.contains('colors.error') &&
            body.contains('_deleteAccount')) {
          privacyBody = body;
          break;
        }
        i = end + 1;
      }
      expect(
        privacyBody,
        isNotNull,
        reason:
            'Privacy card must use AppCard with an error accent that routes to _deleteAccount',
      );
    });

    test('removes the now-unused _export function', () {
      expect(
        RegExp(r'Future<void>\s+_export\(').hasMatch(profile),
        isFalse,
        reason:
            '_export() must be removed once the Export tile is gone -- it is dead code otherwise',
      );
    });

    test('keeps the sign-out button wired and full-width', () {
      final hasButton = profile.contains('SecondaryButton(') &&
          profile.contains("GochanoLanguage.text('Sign out'");
      expect(
        hasButton,
        isTrue,
        reason: 'Sign out SecondaryButton must remain on the screen',
      );
      expect(
        profile.contains("onPressed: () => _signOut(context)"),
        isTrue,
        reason: 'Sign out SecondaryButton must still call _signOut(context)',
      );
    });
  });
}
