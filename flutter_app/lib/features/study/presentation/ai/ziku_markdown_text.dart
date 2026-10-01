import 'package:flutter/material.dart';

/// Block-level structure of one Ziku assistant reply.
enum ZikuMarkdownBlockType { paragraph, bulletList, numberedList }

class ZikuMarkdownBlock {
  const ZikuMarkdownBlock(
    this.type,
    this.lines, {
    this.numberStart = 1,
  });

  final ZikuMarkdownBlockType type;
  final List<String> lines;

  /// First marker value for [ZikuMarkdownBlockType.numberedList] blocks.
  final int numberStart;
}

final RegExp _bulletLine = RegExp(r'^[-*•]\s+(.*)$');
final RegExp _numberLine = RegExp(r'^(\d+)[.)]\s+(.*)$');
final RegExp _boldSpan = RegExp(r'\*\*(.+?)\*\*');

/// Splits [raw] into paragraphs, bullet lists and numbered lists.
///
/// This is intentionally tiny: it understands only the constructs Ziku is
/// prompted to emit. HTML and all other markdown syntax stay literal text.
List<ZikuMarkdownBlock> parseZikuMarkdown(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  final blocks = <ZikuMarkdownBlock>[];
  var i = 0;

  while (i < lines.length) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    if (_bulletLine.hasMatch(trimmed)) {
      final items = <String>[];
      while (i < lines.length) {
        final t = lines[i].trim();
        final m = _bulletLine.firstMatch(t);
        if (t.isEmpty || m == null) break;
        items.add(m.group(1)!.trim());
        i++;
      }
      blocks.add(ZikuMarkdownBlock(ZikuMarkdownBlockType.bulletList, items));
      continue;
    }

    final numbered = _numberLine.firstMatch(trimmed);
    if (numbered != null) {
      final items = <String>[];
      final start = int.tryParse(numbered.group(1)!) ?? 1;
      var expected = start;
      while (i < lines.length) {
        final t = lines[i].trim();
        final m = _numberLine.firstMatch(t);
        if (t.isEmpty || m == null || int.tryParse(m.group(1)!) != expected) {
          break;
        }
        items.add(m.group(2)!.trim());
        expected++;
        i++;
      }
      blocks.add(
        ZikuMarkdownBlock(
          ZikuMarkdownBlockType.numberedList,
          items,
          numberStart: start,
        ),
      );
      continue;
    }

    // Paragraph: consecutive non-empty lines that are not list items.
    final paraLines = <String>[];
    while (i < lines.length) {
      final t = lines[i].trim();
      if (t.isEmpty || _bulletLine.hasMatch(t) || _numberLine.hasMatch(t)) {
        break;
      }
      paraLines.add(lines[i]);
      i++;
    }
    blocks.add(ZikuMarkdownBlock(ZikuMarkdownBlockType.paragraph, paraLines));
  }

  return blocks;
}

/// Renders the visible plain text of a reply (markers consumed, list glyphs
/// introduced). Used by tests to prove `**bold**` never reaches the screen.
String zikuMarkdownPlainText(String raw) {
  // Inline markers are consumed by the renderer — mirror that here.
  String visible(String source) => source.replaceAllMapped(
        _boldSpan,
        (m) => m.group(1) ?? '',
      );

  final buffer = StringBuffer();
  for (final block in parseZikuMarkdown(raw)) {
    switch (block.type) {
      case ZikuMarkdownBlockType.paragraph:
        buffer.writeln(visible(block.lines.join('\n')));
      case ZikuMarkdownBlockType.bulletList:
        for (final item in block.lines) {
          buffer.writeln('• ${visible(item)}');
        }
      case ZikuMarkdownBlockType.numberedList:
        for (var n = 0; n < block.lines.length; n++) {
          buffer.writeln(
            '${block.numberStart + n}. ${visible(block.lines[n])}',
          );
        }
    }
    buffer.writeln();
  }
  return buffer.toString().trim();
}

/// Dependency-free renderer for Ziku assistant replies.
///
/// Supports exactly three constructs: paragraphs, `**bold**` spans, and
/// `- ` / `1.` lists. No HTML, no external markdown package. User messages
/// must stay plain [SelectableText] — do not pass user input here.
class ZikuMarkdownText extends StatelessWidget {
  const ZikuMarkdownText(
    this.text, {
    super.key,
    this.style,
    this.boldStyle,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? boldStyle;

  List<InlineSpan> _spans(String source, TextStyle base, TextStyle bold) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _boldSpan.allMatches(source)) {
      if (match.start > last) {
        spans.add(TextSpan(text: source.substring(last, match.start)));
      }
      spans.add(TextSpan(text: match.group(1), style: bold));
      last = match.end;
    }
    if (last < source.length) {
      spans.add(TextSpan(text: source.substring(last)));
    }
    if (spans.isEmpty) {
      spans.add(const TextSpan(text: ''));
    }
    return spans;
  }

  Widget _paragraph(String source, TextStyle base, TextStyle bold) {
    return SelectableText.rich(
      TextSpan(children: _spans(source, base, bold)),
      style: base,
    );
  }

  Widget _listRow(Widget marker, String item, TextStyle base, TextStyle bold) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          marker,
          const SizedBox(width: 4),
          Expanded(child: _paragraph(item, base, bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final bold =
        (boldStyle ?? base).copyWith(fontWeight: FontWeight.bold);
    final blocks = parseZikuMarkdown(text);

    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    if (blocks.length == 1 &&
        blocks.single.type == ZikuMarkdownBlockType.paragraph) {
      return _paragraph(blocks.single.lines.join('\n'), base, bold);
    }

    final children = <Widget>[];
    for (var b = 0; b < blocks.length; b++) {
      if (b > 0) children.add(const SizedBox(height: 6));
      final block = blocks[b];
      switch (block.type) {
        case ZikuMarkdownBlockType.paragraph:
          children.add(_paragraph(block.lines.join('\n'), base, bold));
        case ZikuMarkdownBlockType.bulletList:
          children.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in block.lines)
                  _listRow(
                    SizedBox(
                      width: 14,
                      child: Text('•', style: base),
                    ),
                    item,
                    base,
                    bold,
                  ),
              ],
            ),
          );
        case ZikuMarkdownBlockType.numberedList:
          children.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var n = 0; n < block.lines.length; n++)
                  _listRow(
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${block.numberStart + n}.',
                        style: base,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    block.lines[n],
                    base,
                    bold,
                  ),
              ],
            ),
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
