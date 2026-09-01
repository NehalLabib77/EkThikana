// Decides which AI endpoint a material context should be sent to.
//
// Why this is a separate, pure module
// -----------------------------------
// The AI screen used to call `askPdf` for *every* attached file, so a PNG or
// JPEG was posted to `/api/ai/pdf-question`, which rejects anything that is
// not a PDF and returned a hard 400. The fix is a routing decision, and a
// routing decision that lives inside a `State` class cannot be tested without
// mounting a widget — so it lives here instead.
//
// The decision uses the MIME type *and* the file name. MIME alone is not
// enough: a material document written by an older client, or one whose type
// could not be sniffed, can carry an empty `mimeType` while still obviously
// being `scan.png`. Falling back to the extension keeps those working.

/// Which backend endpoint answers questions about a given material.
enum AiContextRoute {
  /// `POST /api/ai/pdf-question` — text extraction with an OCR fallback for
  /// scanned, image-only PDFs.
  pdfQuestion,

  /// `POST /api/ai/image-question` — Gemini multimodal.
  imageQuestion,
}

abstract final class AiContextRouting {
  static const Set<String> imageExtensions = {'png', 'jpg', 'jpeg', 'webp'};

  /// The lowercased extension without the dot, or `''` when there is none.
  ///
  /// `'notes.v2.pdf'` → `'pdf'`; `'report.'` → `''`; `'Makefile'` → `''`.
  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static bool isPdfName(String fileName) => extensionOf(fileName) == 'pdf';

  static bool isImageName(String fileName) =>
      imageExtensions.contains(extensionOf(fileName));

  /// Chooses the endpoint for a material.
  ///
  /// Order of evidence: an explicit MIME type wins, then the file name.
  /// Anything unrecognised routes to [AiContextRoute.imageQuestion] — the
  /// multimodal endpoint is the more forgiving of the two, and sending an
  /// unknown file to the PDF extractor guarantees a 400 while sending it to
  /// the vision endpoint at least has a chance of answering.
  static AiContextRoute routeFor({String? mimeType, String? fileName}) {
    final mime = (mimeType ?? '').toLowerCase().trim();
    final name = (fileName ?? '').trim();

    if (mime.contains('pdf')) return AiContextRoute.pdfQuestion;
    if (mime.startsWith('image/')) return AiContextRoute.imageQuestion;

    if (isPdfName(name)) return AiContextRoute.pdfQuestion;
    if (isImageName(name)) return AiContextRoute.imageQuestion;

    return AiContextRoute.imageQuestion;
  }
}
