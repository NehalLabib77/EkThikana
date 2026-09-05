// Static guards for workspace content: notes delete, empty states, FAB rule.
//
// Verifies that:
//   * Note deletion awaits the result and shows user feedback
//   * Empty states do NOT duplicate the FAB's create action
//   * The FAB remains the single screen-level create action
//   * PDF and Saved Images empty states are context-aware

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Notes delete — awaits result and shows feedback', () {
    late String screenSource;
    late String editorSource;

    setUpAll(() {
      screenSource = _read(
        'lib/features/study/presentation/notes/notes_screen.dart',
      );
      editorSource = _read(
        'lib/features/study/presentation/notes/note_editor_screen.dart',
      );
    });

    test('notes_screen.dart imports showGochanoMessage', () {
      expect(screenSource, contains('showGochanoMessage'));
    });

    test('delete menu callback is async and awaits deleteNote', () {
      expect(
        screenSource,
        contains('onSelected: () async'),
        reason: 'delete callback must be async to await the result',
      );
      expect(
        screenSource,
        contains('await deleteNote(context, doc)'),
        reason: 'must await deleteNote to know if deletion succeeded',
      );
    });

    test('shows success message after deletion', () {
      expect(
        screenSource,
        contains('Note deleted.'),
        reason: 'must show confirmation that the note was deleted',
      );
      expect(
        screenSource,
        contains('নোট মুছে ফেলা হয়েছে।'),
        reason: 'Bengali success message must be present',
      );
    });

    test('deleteNote function has try/catch with error handling', () {
      expect(editorSource, contains('try {'));
      expect(editorSource, contains('} catch (error)'));
      expect(
        editorSource,
        contains('friendlyErrorMessage(error)'),
        reason: 'errors must be converted to friendly messages',
      );
    });

    test('deleteNote shows error via showGochanoMessage on failure', () {
      expect(
        editorSource,
        contains('showGochanoMessage(context, friendlyErrorMessage(error), isError: true)'),
        reason: 'deletion failures must be shown to the user',
      );
    });

    test('deleteNote checks context.mounted before showing error', () {
      expect(
        editorSource,
        contains('if (context.mounted)'),
        reason: 'must check context is still mounted before UI operations',
      );
    });

    test('deleteNote uses showConfirmationSheet for confirmation', () {
      expect(editorSource, contains('showConfirmationSheet'));
      expect(
        editorSource,
        contains('Delete this note?'),
        reason: 'confirmation dialog must ask the user',
      );
    });
  });

  group('Notes empty state — no duplicate CTA', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/study/presentation/notes/notes_screen.dart',
      ),
    );

    test('empty state has no actionLabel', () {
      // The EmptyState in the empty docs branch must not have actionLabel
      final emptyBranch = _extractEmptyBranch(source);
      expect(
        emptyBranch,
        isNot(contains('actionLabel')),
        reason: 'empty state must not have a body CTA button',
      );
    });

    test('empty state has no onAction', () {
      final emptyBranch = _extractEmptyBranch(source);
      expect(
        emptyBranch,
        isNot(contains('onAction')),
        reason: 'empty state must not have an onAction callback',
      );
    });

    test('empty state title says No notes yet', () {
      final emptyBranch = _extractEmptyBranch(source);
      expect(emptyBranch, contains('No notes yet'));
      expect(emptyBranch, contains('এখনো কোনো নোট নেই'));
    });

    test('empty state message references the + button', () {
      final emptyBranch = _extractEmptyBranch(source);
      expect(
        emptyBranch,
        contains('+ button'),
        reason: 'message should direct user to the FAB',
      );
    });

    test('FAB exists with New note label', () {
      expect(source, contains('FloatingActionButton.extended'));
      expect(source, contains('New note'));
      expect(source, contains('নতুন নোট'));
    });

    test('FAB navigates to NoteEditorScreen', () {
      expect(source, contains('NoteEditorScreen()'));
    });
  });

  group('Materials empty state — no duplicate CTA for PDFs and Images', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/study/presentation/materials/materials_screen.dart',
      ),
    );

    test('empty state has no actionLabel', () {
      final emptyBranch = _extractMaterialsEmptyBranch(source);
      expect(
        emptyBranch,
        isNot(contains('actionLabel')),
        reason: 'empty state must not have a body CTA button',
      );
    });

    test('empty state has no onAction', () {
      final emptyBranch = _extractMaterialsEmptyBranch(source);
      expect(
        emptyBranch,
        isNot(contains('onAction')),
        reason: 'empty state must not have an onAction callback',
      );
    });

    test('empty state for images mentions saved images', () {
      expect(source, contains('No saved images yet'));
      expect(source, contains('এখনো কোনো সংরক্ষিত ছবি নেই'));
    });

    test('empty state for PDFs mentions PDFs', () {
      expect(source, contains('No PDFs yet'));
      expect(source, contains('এখনো কোনো পিডিএফ নেই'));
    });

    test('empty state for search says Nothing matched', () {
      expect(source, contains('Nothing matched'));
      expect(source, contains('কিছু মেলেনি'));
    });

    test('empty state messages reference the + button', () {
      expect(
        source,
        contains('+ button'),
        reason: 'all empty states should direct user to the FAB',
      );
    });

    test('FAB exists with Add material label', () {
      expect(source, contains('FloatingActionButton.extended'));
      expect(source, contains('Add material'));
      expect(source, contains('উপকরণ যোগ'));
    });

    test('FAB navigates to MaterialUploadScreen', () {
      expect(source, contains('MaterialUploadScreen'));
    });
  });

  group('Global FAB rule — single create action', () {
    test('NotesScreen has exactly one FAB', () {
      final source = _read(
        'lib/features/study/presentation/notes/notes_screen.dart',
      );
      final fabCount = 'FloatingActionButton'.allMatches(source).length;
      expect(fabCount, 1, reason: 'NotesScreen must have exactly one FAB');
    });

    test('MaterialsScreen has exactly one FAB', () {
      final source = _read(
        'lib/features/study/presentation/materials/materials_screen.dart',
      );
      final fabCount = 'FloatingActionButton'.allMatches(source).length;
      expect(
        fabCount,
        1,
        reason: 'MaterialsScreen must have exactly one FAB',
      );
    });
  });
}

/// Extracts the EmptyState block from notes_screen.dart when docs.isEmpty.
String _extractEmptyBranch(String source) {
  final start = source.indexOf('if (docs.isEmpty) {');
  if (start == -1) return '';
  // Find the matching closing brace by counting depth
  int depth = 0;
  for (int i = start; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start, start + 500);
}

/// Extracts the EmptyState block from materials_screen.dart when docs.isEmpty.
String _extractMaterialsEmptyBranch(String source) {
  final start = source.indexOf('if (docs.isEmpty) {');
  if (start == -1) return '';
  int depth = 0;
  for (int i = start; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start, start + 1000);
}
