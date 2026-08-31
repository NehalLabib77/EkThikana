// Gochano branded loading widget.
// Stationary Gochano logo surrounded by a thin amber ring that rotates while
// the app is busy. Bilingual message via EkLanguage.text('loading').
//
// Disposes its AnimationController safely. Caches the decoded logo through
// the inherited ImageProvider.
//
// Use as a full-screen splash replacement:
//   const GochanoLoading()
// Use inline in cards / list tiles:
//   const GochanoLoading.compact()
// Use when a network call exceeded a retry threshold:
//   GochanoLoading(onRetry: () => refetch(), showRetryAfter: ...)

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/language.dart';

const String _kLogoAsset = 'assets/branding/Gochano.png';

class GochanoLoading extends StatefulWidget {
  const GochanoLoading({
    super.key,
    this.message,
    this.compact = false,
    this.onRetry,
    this.showRetryAfter = const Duration(milliseconds: 200),
  });

  /// Convenience for a tighter (e.g. card-sized) spinner.
  const GochanoLoading.compact({
    super.key,
    this.message,
    this.onRetry,
    this.showRetryAfter = const Duration(milliseconds: 200),
  }) : compact = true;

  /// Optional override message. Defaults to the localized "Loading...".
  final String? message;

  /// True renders a smaller spinner suitable for cards.
  final bool compact;

  /// Optional retry callback. Once [showRetryAfter] elapses, a "Retry" button
  /// appears. The retry button is NEVER auto-pressed.
  final VoidCallback? onRetry;

  /// Delay before the optional retry button is exposed.
  final Duration showRetryAfter;

  @override
  State<GochanoLoading> createState() => _GochanoLoadingState();
}

class _GochanoLoadingState extends State<GochanoLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController;
  Timer? _retryTimer;
  bool _retryVisible = false;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    if (widget.onRetry != null) {
      _retryTimer = Timer(widget.showRetryAfter, () {
        if (!mounted) return;
        setState(() => _retryVisible = true);
      });
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _ringController
      ..stop()
      ..dispose();
    super.dispose();
  }

  String get _resolvedMessage =>
      widget.message ?? EkLanguage.text('Loading...', 'লোড হচ্ছে...');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    // Fixed intrinsic size for the inner Stack (logo + ring) so the layout
    // is deterministic. The parent decides how this should be sized on
    // screen; FittedBox(BoxFit.contain) upstream guarantees the artwork
    // never crops or stretches, regardless of Android screen size or
    // orientation.
    final intrinsic = widget.compact ? 80.0 : 160.0;
    final ringStroke = widget.compact ? 1.6 : 2.4;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: intrinsic,
            height: intrinsic,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Stationary logo. Uses BoxFit.contain inside a tight box so
                // it never stretches; the parent FittedBox guarantees the
                // whole artwork fits the screen.
                Image.asset(
                  _kLogoAsset,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  semanticLabel: 'Gochano logo',
                ),
                // Rotating ring.
                RotationTransition(
                  turns: _ringController,
                  child: CustomPaint(
                    size: Size.square(intrinsic),
                    painter: _GochanoRingPainter(
                      color: brand,
                      strokeWidth: ringStroke,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_resolvedMessage.isNotEmpty) ...[
            SizedBox(height: widget.compact ? 8 : 16),
            Text(
              _resolvedMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (_retryVisible && widget.onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(EkLanguage.text('Retry', 'আবার চেষ্টা করুন')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Draws a thin arc (3/4 of a circle) that, when rotated by the parent
/// AnimationController, gives the appearance of a sweeping brand mark.
class _GochanoRingPainter extends CustomPainter {
  _GochanoRingPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = strokeWidth;
    final arcRect = Rect.fromLTWH(
      rect.left + inset,
      rect.top + inset,
      rect.width - inset * 2,
      rect.height - inset * 2,
    );

    final base = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, 6.283185307179586, false, base);

    final head = Paint()
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0), color],
        startAngle: 0,
        endAngle: 3.141592653589793,
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, -1.6, 1.8, false, head);
  }

  @override
  bool shouldRepaint(covariant _GochanoRingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
