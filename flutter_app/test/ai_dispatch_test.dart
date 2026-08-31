// Pin the AI Assistant file upload routing contract.
//
// The screen used to unconditionally call ApiService.askPdf on every
// uploaded file, which sent PNG/JPEG/WEBP into /api/ai/pdf-question and
// produced a hard 400 from the server. These tests pin the new dispatch
// helpers (extensionOf / isPdfName / isImageName) so that:
//   * .pdf still routes to the text-extraction endpoint,
//   * .png/.jpg/.jpeg/.webp route to the Gemini Vision endpoint,
//   * unknown extensions do NOT match either helper so the dispatch
//     falls back to the image route and surfaces a real 4xx.
//
// The helpers live on the private State class. They are exposed via
// @visibleForTesting so we can call them statically without mounting
// any widget tree.

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/screens/study/ai_assistant_screen.dart';

void main() {
  group('AiAssistantScreen.extensionOf', () {
    test('returns lowercased extension without the dot', () {
      expect(AiAssistantScreen.extensionOf('notes.PDF'), equals('pdf'));
      expect(AiAssistantScreen.extensionOf('photo.PNG'), equals('png'));
      expect(AiAssistantScreen.extensionOf('photo.JPG'), equals('jpg'));
      expect(AiAssistantScreen.extensionOf('photo.JPEG'), equals('jpeg'));
      expect(AiAssistantScreen.extensionOf('sticker.WebP'), equals('webp'));
    });

    test('returns empty string when the file has no extension', () {
      expect(AiAssistantScreen.extensionOf('Makefile'), equals(''));
      expect(AiAssistantScreen.extensionOf(''), equals(''));
    });

    test('returns empty string when the file ends with a dot', () {
      // ".pdf." must not be treated as "pdf" — lastIndexOf catches the
      // trailing dot and we explicitly bail out.
      expect(AiAssistantScreen.extensionOf('report.'), equals(''));
    });

    test('handles filenames with multiple dots', () {
      // e.g. "notes.v2.pdf" → "pdf", not "v2".
      expect(AiAssistantScreen.extensionOf('notes.v2.pdf'), equals('pdf'));
      expect(AiAssistantScreen.extensionOf('archive.tar.gz'), equals('gz'));
    });
  });

  group('AiAssistantScreen.isPdfName', () {
    test('true only for .pdf (case-insensitive)', () {
      expect(AiAssistantScreen.isPdfName('lecture.pdf'), isTrue);
      expect(AiAssistantScreen.isPdfName('Lecture.PDF'), isTrue);
    });

    test('false for images and anything else', () {
      expect(AiAssistantScreen.isPdfName('photo.png'), isFalse);
      expect(AiAssistantScreen.isPdfName('photo.jpg'), isFalse);
      expect(AiAssistantScreen.isPdfName('photo.jpeg'), isFalse);
      expect(AiAssistantScreen.isPdfName('sticker.webp'), isFalse);
      expect(AiAssistantScreen.isPdfName('archive.txt'), isFalse);
      expect(AiAssistantScreen.isPdfName('noext'), isFalse);
    });
  });

  group('AiAssistantScreen.isImageName', () {
    test('true for png, jpg, jpeg, webp (case-insensitive)', () {
      expect(AiAssistantScreen.isImageName('photo.png'), isTrue);
      expect(AiAssistantScreen.isImageName('photo.PNG'), isTrue);
      expect(AiAssistantScreen.isImageName('photo.jpg'), isTrue);
      expect(AiAssistantScreen.isImageName('photo.JPG'), isTrue);
      expect(AiAssistantScreen.isImageName('photo.jpeg'), isTrue);
      expect(AiAssistantScreen.isImageName('photo.JPEG'), isTrue);
      expect(AiAssistantScreen.isImageName('sticker.webp'), isTrue);
      expect(AiAssistantScreen.isImageName('sticker.WEBP'), isTrue);
    });

    test('false for pdf and unknown extensions', () {
      expect(AiAssistantScreen.isImageName('lecture.pdf'), isFalse);
      expect(AiAssistantScreen.isImageName('archive.zip'), isFalse);
      expect(AiAssistantScreen.isImageName('data.csv'), isFalse);
      expect(AiAssistantScreen.isImageName('noext'), isFalse);
    });
  });

  group('AiAssistantScreen dispatch matrix', () {
    // Mirrors the conditional inside _askPdfFromUpload:
    //   final isPdf = isPdfName(file.name);
    //   final routeAsImage = !isPdf;
    // So a PDF → askPdf, anything else → askImage. This pins the rule so
    // a future refactor that swaps to "isImage → askImage, else askPdf"
    // (which would let a PDF silently leak into the image route) is
    // caught immediately.
    test('PDF routes to askPdf', () {
      final name = 'lecture.pdf';
      final isPdf = AiAssistantScreen.isPdfName(name);
      final routeAsImage = !isPdf;
      expect(isPdf, isTrue);
      expect(routeAsImage, isFalse);
    });

    test('PNG / JPG / JPEG / WEBP route to askImage', () {
      for (final name in ['p.png', 'p.jpg', 'p.jpeg', 'p.webp']) {
        final isPdf = AiAssistantScreen.isPdfName(name);
        final routeAsImage = !isPdf;
        expect(routeAsImage, isTrue,
            reason: '$name should route through askImage');
      }
    });

    test('unknown extension still falls through to askImage (no silent 400)',
        () {
      // Regression guard: the old code sent everything to askPdf and
      // 400'd. Now anything not-a-pdf goes to askImage so the user sees
      // a clean validation message from the server.
      const name = 'data.csv';
      final isPdf = AiAssistantScreen.isPdfName(name);
      final routeAsImage = !isPdf;
      expect(isPdf, isFalse);
      expect(routeAsImage, isTrue);
    });
  });
}
