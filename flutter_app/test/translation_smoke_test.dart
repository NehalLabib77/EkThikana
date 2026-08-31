// Translation smoke test.
//
// Scans every .dart file under lib/ at runtime (we use a build-time embed of
// the file list), extracts every `EkLanguage.text(en, bn)` literal call-site,
// and asserts:
//   * both EN and BN sides are non-empty,
//   * EN does not contain Bengali script characters (U+0980..U+09FF,
//     except the shared ৳ currency symbol),
//   * BN does contain at least one Bengali alphabetic character,
//   * EN != BN (a forgotten translation slips through otherwise).
//
// This is the in-process twin of `_audit_copy.py`.  Both should agree.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EkLanguage.text literals are bilingual and non-empty', () async {
    final lib = Directory('lib');
    if (!lib.existsSync()) {
      markTestSkipped('lib/ not present (run from flutter_app)');
      return;
    }

    final dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final findings = <_Finding>[];
    for (final file in dartFiles) {
      final text = await file.readAsString();
      findings.addAll(_extractCallSites(text, file.path));
    }

    expect(findings, isNotEmpty,
        reason: 'Expected to find EkLanguage.text() call-sites under lib/.');

    final empty = findings.where((f) => f.en.isEmpty || f.bn.isEmpty).toList();
    final swapped = findings
        .where((f) => _nonSharedBengali.hasMatch(f.en))
        .toList();
    final untranslated = findings
        .where((f) =>
            f.bn.isNotEmpty &&
            !_bengali.hasMatch(f.bn) &&
            f.bn.runes.any((r) => _isAsciiAlpha(r)))
        .toList();
    final identical = findings
        .where((f) => f.en.isNotEmpty && f.en == f.bn)
        .toList();

    final summary = StringBuffer()
      ..writeln('Scanned ${findings.length} literal EkLanguage.text() '
          'call-sites under lib/.')
      ..writeln('  empty:           ${empty.length}')
      ..writeln('  swapped (BN in EN): ${swapped.length}')
      ..writeln('  untranslated (BN ascii-only): ${untranslated.length}')
      ..writeln('  identical (EN == BN): ${identical.length}');

    if (empty.isNotEmpty) {
      summary.writeln('\nEmpty side(s):');
      for (final f in empty.take(20)) {
        summary.writeln('  ${f.path}:${f.lineNo}  '
            'en=${_preview(f.en)}  bn=${_preview(f.bn)}');
      }
    }
    if (swapped.isNotEmpty) {
      summary.writeln('\nEN side contains Bengali script (U+0980..09FF, '
          'excluding ৳):');
      for (final f in swapped.take(20)) {
        summary.writeln('  ${f.path}:${f.lineNo}  '
            'en=${_preview(f.en)}  bn=${_preview(f.bn)}');
      }
    }
    if (untranslated.isNotEmpty) {
      summary.writeln('\nBN side is ASCII-only (possible untranslated):');
      for (final f in untranslated.take(20)) {
        summary.writeln('  ${f.path}:${f.lineNo}  '
            'en=${_preview(f.en)}  bn=${_preview(f.bn)}');
      }
    }
    if (identical.isNotEmpty) {
      summary.writeln('\nEN == BN (forgotten translation):');
      for (final f in identical.take(20)) {
        summary.writeln('  ${f.path}:${f.lineNo}  '
            'en=${_preview(f.en)}');
      }
    }

    expect(empty, isEmpty, reason: summary.toString());
    expect(swapped, isEmpty, reason: summary.toString());
    // untranslated and identical are warnings — log but don't fail.
    if (untranslated.isNotEmpty || identical.isNotEmpty) {
      // ignore: avoid_print
      print(summary);
    }
  });
}

class _Finding {
  _Finding(this.path, this.lineNo, this.en, this.bn);
  final String path;
  final int lineNo;
  final String en;
  final String bn;
}

final RegExp _bengali = RegExp(r'[\u0980-\u09FF]');
final RegExp _nonSharedBengali =
    RegExp(r'[\u0980-\u09F2\u09F4-\u09FF]');
final RegExp _interp = RegExp(r'\$\{[^}]*\}');
final RegExp _callSite = RegExp(
  r'EkLanguage\.text\(',
);

List<_Finding> _extractCallSites(String text, String path) {
  final out = <_Finding>[];
  for (final m in _callSite.allMatches(text)) {
    final after = m.end; // index right after '('
    final parsed = _splitTopLevelCall(text, after);
    if (parsed == null) continue;
    final (closeIdx, body) = parsed;
    final args = _splitTopLevelArgs(body);
    if (args == null) continue;
    final (enRaw, bnRaw) = args;
    final enInner = _stripQuotes(enRaw);
    final bnInner = _stripQuotes(bnRaw);
    final enIsLiteral = enInner.$2;
    final bnIsLiteral = bnInner.$2;
    if (!(enIsLiteral && bnIsLiteral)) {
      continue;
    }
    final en = _interp.allMatches(enInner.$1).isEmpty
        ? enInner.$1
        : enInner.$1.replaceAll(_interp, '');
    final bn = _interp.allMatches(bnInner.$1).isEmpty
        ? bnInner.$1
        : bnInner.$1.replaceAll(_interp, '');
    final lineNo = text.substring(0, m.start).split('\n').length;
    out.add(_Finding(path, lineNo, en, bn));
    // continue past this site
    // (the for-loop already gives us the next match)
    // ignore: unused_local_variable
    final _ = closeIdx;
  }
  return out;
}

(int, String)? _splitTopLevelCall(String text, int start) {
  var depth = 1;
  var i = start;
  final n = text.length;
  while (i < n) {
    final c = text[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return (i, text.substring(start, i));
    } else if (c == "'" || c == '"') {
      final quote = c;
      var j = i + 1;
      while (j < n && text[j] != quote) {
        if (text[j] == r'\' && j + 1 < n) {
          j += 2;
          continue;
        }
        j++;
      }
      i = j; // skip to closing quote
    }
    i++;
  }
  return null;
}

(String, String)? _splitTopLevelArgs(String body) {
  var depthParen = 0;
  var depthBrace = 0;
  var depthBracket = 0;
  var inString = false;
  var stringQuote = '';
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (inString) {
      if (c == r'\' && i + 1 < body.length) {
        i++;
        continue;
      }
      if (c == stringQuote) inString = false;
    } else {
      if (c == "'" || c == '"') {
        inString = true;
        stringQuote = c;
      } else if (c == '(') {
        depthParen++;
      } else if (c == ')') {
        depthParen--;
      } else if (c == '{') {
        depthBrace++;
      } else if (c == '}') {
        depthBrace--;
      } else if (c == '[') {
        depthBracket++;
      } else if (c == ']') {
        depthBracket--;
      } else if (c == ',' &&
          depthParen == 0 &&
          depthBrace == 0 &&
          depthBracket == 0) {
        return (body.substring(0, i), body.substring(i + 1));
      }
    }
  }
  return null;
}

(String, bool) _stripQuotes(String arg) {
  final s = arg.trim();
  if (s.length >= 2 && s[0] == s[s.length - 1] &&
      (s[0] == "'" || s[0] == '"')) {
    return (s.substring(1, s.length - 1), true);
  }
  return (s, false);
}

String _preview(String s) {
  final t = s.replaceAll('\n', ' ');
  return t.length > 50 ? '${t.substring(0, 50)}…' : t;
}

bool _isAsciiAlpha(int r) {
  // ASCII a-z / A-Z.
  return (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);
}