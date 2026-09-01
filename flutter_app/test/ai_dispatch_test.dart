// Pin the AI context routing contract.
//
// The AI assistant used to call `askPdf` for every attached file, so a PNG or
// JPEG was posted to `/api/ai/pdf-question` and the server answered 400. These
// tests pin the routing decision so that:
//
//   * PDFs go to the text-extraction endpoint (which has its own OCR fallback
//     for scanned, image-only PDFs);
//   * images go to the multimodal endpoint;
//   * a material with a *missing* MIME type still routes by its file name —
//     the case a MIME-only check would silently get wrong;
//   * anything unrecognised falls to the multimodal endpoint rather than to
//     the PDF extractor, which would be a guaranteed 400.

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/study/presentation/ai/ai_context_routing.dart';

void main() {
  group('AiContextRouting.extensionOf', () {
    test('returns the lowercased extension without the dot', () {
      expect(AiContextRouting.extensionOf('notes.PDF'), 'pdf');
      expect(AiContextRouting.extensionOf('photo.PNG'), 'png');
      expect(AiContextRouting.extensionOf('photo.JPG'), 'jpg');
      expect(AiContextRouting.extensionOf('photo.JPEG'), 'jpeg');
      expect(AiContextRouting.extensionOf('sticker.WebP'), 'webp');
    });

    test('returns empty when there is no extension', () {
      expect(AiContextRouting.extensionOf('Makefile'), '');
      expect(AiContextRouting.extensionOf(''), '');
    });

    test('returns empty when the name ends with a dot', () {
      // "report." must not be read as extension "".
      expect(AiContextRouting.extensionOf('report.'), '');
    });

    test('uses the last dot', () {
      expect(AiContextRouting.extensionOf('notes.v2.pdf'), 'pdf');
      expect(AiContextRouting.extensionOf('archive.tar.gz'), 'gz');
    });
  });

  group('AiContextRouting.isPdfName / isImageName', () {
    test('isPdfName is true only for .pdf, case-insensitively', () {
      expect(AiContextRouting.isPdfName('lecture.pdf'), isTrue);
      expect(AiContextRouting.isPdfName('Lecture.PDF'), isTrue);
      expect(AiContextRouting.isPdfName('photo.png'), isFalse);
      expect(AiContextRouting.isPdfName('archive.txt'), isFalse);
      expect(AiContextRouting.isPdfName('noext'), isFalse);
    });

    test('isImageName covers the image types the backend accepts', () {
      for (final name in ['a.png', 'a.jpg', 'a.jpeg', 'a.webp', 'A.PNG']) {
        expect(AiContextRouting.isImageName(name), isTrue, reason: name);
      }
      for (final name in ['a.pdf', 'a.docx', 'a.txt', 'noext']) {
        expect(AiContextRouting.isImageName(name), isFalse, reason: name);
      }
    });
  });

  group('AiContextRouting.routeFor', () {
    test('an explicit PDF mime type routes to the PDF endpoint', () {
      expect(
        AiContextRouting.routeFor(mimeType: 'application/pdf'),
        AiContextRoute.pdfQuestion,
      );
    });

    test('an explicit image mime type routes to the multimodal endpoint', () {
      for (final mime in ['image/png', 'image/jpeg', 'image/webp']) {
        expect(
          AiContextRouting.routeFor(mimeType: mime),
          AiContextRoute.imageQuestion,
          reason: mime,
        );
      }
    });

    test('a missing mime type falls back to the file name', () {
      // The regression this guards: a material saved without a mimeType.
      // Routing on MIME alone would send scan.png to the PDF extractor.
      expect(
        AiContextRouting.routeFor(fileName: 'scan.png'),
        AiContextRoute.imageQuestion,
      );
      expect(
        AiContextRouting.routeFor(mimeType: '', fileName: 'lecture.pdf'),
        AiContextRoute.pdfQuestion,
      );
    });

    test('mime type wins over a misleading file name', () {
      expect(
        AiContextRouting.routeFor(
          mimeType: 'image/png',
          fileName: 'actually_an_image.pdf',
        ),
        AiContextRoute.imageQuestion,
      );
    });

    test('an unknown type never goes to the PDF extractor', () {
      // The PDF endpoint hard-rejects non-PDFs; the multimodal one at least
      // has a chance of answering.
      for (final name in ['mystery.bin', 'noext', '']) {
        expect(
          AiContextRouting.routeFor(fileName: name),
          AiContextRoute.imageQuestion,
          reason: name,
        );
      }
      expect(AiContextRouting.routeFor(), AiContextRoute.imageQuestion);
    });
  });
}
