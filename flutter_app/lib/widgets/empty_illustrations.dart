// Gochano empty-state illustrations.
//
// Hand-rolled `CustomPainter` illustrations for each module. They live
// inline (no asset bundle, no font dependency, no SVG parser) so they:
//   * cost zero kilobytes in the app bundle,
//   * render crisply on any density,
//   * respect the active theme through the accent / muted colors passed
//     in by the caller,
//   * are fast enough to draw on every empty-state rebuild.
//
// The visual language is intentionally flat and friendly:
//   - one rounded background "plate",
//   - one bold accent shape,
//   - one muted detail shape.
//
// Consumers should mount the painter inside a fixed-size `SizedBox`.
// The painter takes the full size and scales proportionally.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws the empty-state illustration for the given [module].
///
/// Module ids match the keys in [EkGradients] / [EkSoft]:
/// `study`, `medicine`, `expense`, `commute`, `bazar`, `tasks`, `ai`,
/// or anything else (falls back to a generic shape).
class EmptyIllustrationPainter extends CustomPainter {
  const EmptyIllustrationPainter({
    required this.module,
    required this.accent,
    required this.muted,
  });

  final String module;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final shorter = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Background plate — soft circle in muted.
    final platePaint = Paint()..color = muted.withValues(alpha: .35);
    canvas.drawCircle(Offset(cx, cy), shorter * 0.42, platePaint);

    // Module-specific illustration sits on top.
    switch (module) {
      case 'study':
        _drawBook(canvas, size, cx, cy, shorter);
        break;
      case 'medicine':
        _drawPill(canvas, size, cx, cy, shorter);
        break;
      case 'expense':
        _drawWallet(canvas, size, cx, cy, shorter);
        break;
      case 'commute':
        _drawPin(canvas, size, cx, cy, shorter);
        break;
      case 'bazar':
        _drawBasket(canvas, size, cx, cy, shorter);
        break;
      case 'tasks':
        _drawChecklist(canvas, size, cx, cy, shorter);
        break;
      case 'ai':
        _drawSparkle(canvas, size, cx, cy, shorter);
        break;
      default:
        _drawSparkle(canvas, size, cx, cy, shorter);
    }
  }

  // --- module shapes -------------------------------------------------------

  void _drawBook(Canvas canvas, Size size, double cx, double cy, double s) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + s * 0.04), width: s * 0.55, height: s * 0.42),
      const Radius.circular(10),
    );
    final bodyPaint = Paint()..color = accent;
    canvas.drawRRect(body, bodyPaint);

    final spine = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx, cy - s * 0.17),
      Offset(cx, cy + s * 0.25),
      spine,
    );

    // Pages lines
    final page = Paint()
      ..color = Colors.white.withValues(alpha: .75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 3; i++) {
      final dx = (i - 1) * s * 0.10;
      canvas.drawLine(
        Offset(cx + dx, cy - s * 0.10),
        Offset(cx + dx, cy + s * 0.18),
        page,
      );
    }
  }

  void _drawPill(Canvas canvas, Size size, double cx, double cy, double s) {
    final pillRect = Rect.fromCenter(
      center: Offset(cx, cy + s * 0.04),
      width: s * 0.55,
      height: s * 0.22,
    );
    final pillPaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(99)),
      pillPaint,
    );

    // Right half white.
    final rightHalf = Rect.fromLTRB(
      pillRect.center.dx,
      pillRect.top,
      pillRect.right,
      pillRect.bottom,
    );
    final whitePaint = Paint()..color = Colors.white;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(rightHalf, const Radius.circular(99)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(99)),
      whitePaint,
    );
    canvas.restore();

    // Plus mark on the white side.
    final mark = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final markCx = pillRect.center.dx + s * 0.13;
    canvas.drawLine(
      Offset(markCx - 4, pillRect.center.dy),
      Offset(markCx + 4, pillRect.center.dy),
      mark,
    );
    canvas.drawLine(
      Offset(markCx, pillRect.center.dy - 4),
      Offset(markCx, pillRect.center.dy + 4),
      mark,
    );
  }

  void _drawWallet(Canvas canvas, Size size, double cx, double cy, double s) {
    final walletRect = Rect.fromCenter(
      center: Offset(cx, cy + s * 0.02),
      width: s * 0.55,
      height: s * 0.36,
    );
    final walletPaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(walletRect, const Radius.circular(10)),
      walletPaint,
    );

    // Coin slot.
    final slot = Paint()..color = Colors.white.withValues(alpha: .85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(walletRect.center.dx, walletRect.top + s * 0.05),
          width: s * 0.28,
          height: s * 0.04,
        ),
        const Radius.circular(4),
      ),
      slot,
    );

    // Coin peeking out.
    final coin = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(walletRect.right - s * 0.10, walletRect.center.dy + s * 0.04),
      s * 0.08,
      coin,
    );
    final coinEdge = Paint()
      ..color = accent
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
      Offset(walletRect.right - s * 0.10, walletRect.center.dy + s * 0.04),
      s * 0.08,
      coinEdge,
    );

    final taka = TextPainter(
      text: const TextSpan(
        text: '৳',
        style: TextStyle(
          color: Color(0xFF126C25),
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    taka.paint(
      canvas,
      Offset(
        walletRect.right - s * 0.10 - taka.width / 2,
        walletRect.center.dy + s * 0.04 - taka.height / 2,
      ),
    );
  }

  void _drawPin(Canvas canvas, Size size, double cx, double cy, double s) {
    final path = Path()
      ..moveTo(cx, cy + s * 0.20)
      ..cubicTo(
        cx - s * 0.20,
        cy + s * 0.04,
        cx - s * 0.20,
        cy - s * 0.18,
        cx,
        cy - s * 0.18,
      )
      ..cubicTo(
        cx + s * 0.20,
        cy - s * 0.18,
        cx + s * 0.20,
        cy + s * 0.04,
        cx,
        cy + s * 0.20,
      )
      ..close();
    final pinPaint = Paint()..color = accent;
    canvas.drawShadow(path, accent, 4, true);
    canvas.drawPath(path, pinPaint);

    final hole = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy - s * 0.06), s * 0.06, hole);
  }

  void _drawBasket(Canvas canvas, Size size, double cx, double cy, double s) {
    // Basket body.
    final basketRect = Rect.fromCenter(
      center: Offset(cx, cy + s * 0.04),
      width: s * 0.50,
      height: s * 0.34,
    );
    final basketPaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        basketRect,
        bottomLeft: const Radius.circular(14),
        bottomRight: const Radius.circular(14),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      ),
      basketPaint,
    );

    // Handle.
    final handle = Paint()
      ..color = accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy - s * 0.06),
        width: s * 0.30,
        height: s * 0.26,
      ),
      math.pi,
      math.pi,
      false,
      handle,
    );

    // Veggies peeking out.
    final veggies = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - s * 0.10, cy - s * 0.08), s * 0.05, veggies);
    canvas.drawCircle(Offset(cx, cy - s * 0.12), s * 0.06, veggies);
    canvas.drawCircle(Offset(cx + s * 0.10, cy - s * 0.07), s * 0.05, veggies);
  }

  void _drawChecklist(Canvas canvas, Size size, double cx, double cy, double s) {
    final paper = Rect.fromCenter(
      center: Offset(cx, cy + s * 0.02),
      width: s * 0.50,
      height: s * 0.55,
    );
    final paperPaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(paper, const Radius.circular(10)),
      paperPaint,
    );

    final line = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    // Three checks.
    for (var i = 0; i < 3; i++) {
      final y = paper.top + s * 0.10 + i * s * 0.13;
      // Check.
      final x = paper.left + s * 0.08;
      final path = Path()
        ..moveTo(x - 4, y)
        ..lineTo(x - 1, y + 4)
        ..lineTo(x + 6, y - 4);
      canvas.drawPath(path, line);

      // Bar.
      canvas.drawLine(
        Offset(x + 12, y),
        Offset(paper.right - s * 0.08, y),
        Paint()
          ..color = Colors.white.withValues(alpha: .55)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawSparkle(Canvas canvas, Size size, double cx, double cy, double s) {
    // 4-pointed star sparkle.
    final path = Path()
      ..moveTo(cx, cy - s * 0.22)
      ..lineTo(cx + s * 0.05, cy - s * 0.05)
      ..lineTo(cx + s * 0.22, cy)
      ..lineTo(cx + s * 0.05, cy + s * 0.05)
      ..lineTo(cx, cy + s * 0.22)
      ..lineTo(cx - s * 0.05, cy + s * 0.05)
      ..lineTo(cx - s * 0.22, cy)
      ..lineTo(cx - s * 0.05, cy - s * 0.05)
      ..close();
    final sparkle = Paint()..color = accent;
    canvas.drawPath(path, sparkle);

    // Side sparkles.
    final small = Paint()..color = accent.withValues(alpha: .8);
    canvas.drawCircle(Offset(cx + s * 0.20, cy - s * 0.16), s * 0.025, small);
    canvas.drawCircle(Offset(cx - s * 0.18, cy + s * 0.18), s * 0.02, small);
    canvas.drawCircle(Offset(cx - s * 0.22, cy - s * 0.08), s * 0.015, small);
  }

  @override
  bool shouldRepaint(covariant EmptyIllustrationPainter old) =>
      old.module != module || old.accent != accent || old.muted != muted;
}
