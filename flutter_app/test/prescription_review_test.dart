// Guards for the prescription review screen's honesty rules.
//
// The screen's whole purpose is to hand a decision to the reader rather than
// make one. These tests pin the parts of that which a well-meaning edit is
// most likely to erode:
//
//   1. **A medicine name is never silently corrected.** The name rendered is
//      always the text that was recognised. A suggestion appears as a
//      question with two explicit answers; nothing changes until one is
//      tapped.
//   2. **A confidence is a phrase, not a fabricated percentage.** Tesseract's
//      raw score is an ordering, not a calibrated probability, and a precise
//      figure on a misread drug name would imply precision it does not have.
//   3. **Poor reads say so.** A page read badly is not a page with fewer
//      medicines on it, and the screen must not let it look like one.
//   4. **A missing Bengali pack is stated.** Without it, Bengali instructions
//      are not misread — they are not read at all.
//
// These are static source guards rather than pumped widgets: the screen owns
// a file picker and an HTTP call, and the properties worth pinning are about
// what it is allowed to say, which the source states directly.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File get _screen => File(
      'lib/features/life/presentation/medicine/prescription_scan_screen.dart',
    );

void main() {
  late String source;

  /// The screen with comments stripped, for checks about what it *renders*.
  /// A doc comment explaining why a bare percentage is wrong must not itself
  /// read as one being rendered.
  late String code;

  setUpAll(() {
    expect(_screen.existsSync(), isTrue,
        reason: 'the prescription review screen must exist');
    // Normalised: this repo checks out with CRLF on Windows.
    source = _screen.readAsStringSync().replaceAll('\r\n', '\n');
    code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  });

  group('A medicine name is never corrected behind the reader', () {
    test('the recognised name is what gets rendered', () {
      // The row builds its title from `candidate['name']` — the text OCR
      // actually produced — and never from the suggestion.
      expect(source, contains("candidate['name']?.toString()"));
    });

    test('the suggestion is offered as a question with explicit answers', () {
      expect(source, contains('Did you mean'));
      expect(source, contains('Use this spelling'));
      expect(source, contains('Keep as read'));
    });

    test('using a suggestion goes through a deliberate callback', () {
      // `onUseSuggestion` is the only route by which a name other than the
      // recognised one reaches the form, and it fires from a tap.
      expect(source, contains('onUseSuggestion'));
      expect(source, contains("'name': useName ?? candidate['name']"));
    });

    test('the reader is told the decision is theirs', () {
      expect(source, contains('Only you can decide'));
    });
  });

  group('Confidence is reported, not invented', () {
    test('bands are rendered as phrases', () {
      for (final phrase in ['Read clearly', 'Check this one', 'Hard to read']) {
        expect(source, contains(phrase),
            reason: 'the $phrase band needs a plain-language label');
      }
    });

    test('an unmeasured confidence says so instead of defaulting', () {
      // "Not measured" and "read badly" are different facts. Collapsing the
      // first into the second, or into a confident-looking default, is the
      // failure this pins.
      expect(source, contains('Not measured'));
      expect(source, contains('could not be measured'));
    });

    test('no percentage sign is rendered', () {
      // A percent sign in this screen's actual code would almost certainly be
      // a confidence dressed up as a probability. Comments are excluded --
      // one of them explains precisely why not to do that.
      expect(code.contains('%'), isFalse,
          reason: 'confidence must not be presented as a percentage');
    });
  });

  group('The page tells the reader how far to trust it', () {
    test('a poor read warns that medicines may be wrong or missing', () {
      expect(source, contains('may be wrong or'));
      expect(source, contains('missing'));
    });

    test('exact PDF text is distinguished from a recognised photo', () {
      // An embedded text layer is exact. Attaching an OCR confidence band to
      // it would invent uncertainty as surely as inventing certainty.
      expect(source, contains('pdf_text'));
      expect(source, contains('Exact text'));
    });

    test('a missing Bengali pack is surfaced', () {
      expect(source, contains('bengaliSupported'));
      expect(source, contains('Bengali instructions were not read'));
    });
  });

  group('The screen still never prescribes', () {
    test('reminder times are not pre-filled from the prescription', () {
      // The long-standing rule: a frequency shorthand like "1+0+1" is a
      // medical instruction, not a set of clock times.
      expect(source, contains('are deliberately **not** pre-filled'));
      expect(source, isNot(contains("'reminderTimes':")));
      expect(source, isNot(contains("'times':")));
    });

    test('explicit clock values are shown but not turned into reminders', () {
      expect(source, contains('explicitTimes'));
      expect(source, contains('still not'));
      expect(source, contains('pre-filled as reminders'));
    });
  });
}
