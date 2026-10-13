/// A calm, slowly drifting background of blurred colour.
///
/// Three soft blobs, built from the current theme's own colours, drift along
/// looping paths behind the content. At any moment it should be hard to say
/// whether it is moving at all; only by looking away and back is the change
/// noticeable. That is the intent.
///
/// Two performance rules are built into the structure, not left to the caller:
///
///   1. The animation drives the painter through `CustomPainter(repaint:)`,
///      so each frame repaints the canvas and nothing else. No `setState`, no
///      `AnimatedBuilder` around the children, and therefore no widget in the
///      subtree rebuilds at 60fps - which matters because the things sitting
///      on this background are Firestore-backed cards and charts.
///   2. The painting is wrapped in a `RepaintBoundary`, so its repaints do not
///      dirty the layer the content is drawn into.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

class AnimatedGradientBackground extends StatefulWidget {
  const AnimatedGradientBackground({
    super.key,
    required this.child,
    required this.animate,
    this.intensity = 1.0,
  });

  /// The content drawn over the background.
  final Widget child;

  /// False renders a single still frame: same colours, same composition, no
  /// controller and no repaints at all.
  final bool animate;

  /// Scales the blob opacity, for places that want it fainter still.
  final double intensity;

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(AnimatedGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) {
      _start();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _start() {
    // `repeat` with a sine/cosine-driven painter is seamless: phase 1.0 paints
    // exactly what phase 0.0 paints, so the restart cannot be seen.
    _controller = AnimationController(vsync: this, duration: AppMotion.backgroundLoop)
      ..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final opacity =
        (isDark ? AppMotion.blobOpacityDark : AppMotion.blobOpacityLight) *
        widget.intensity;

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: widget.animate,
              painter: _BlobPainter(
                // Null when still: the painter then draws the phase-zero
                // composition once and is never asked again.
                animation: _controller,
                // Two or three related colours only. Tertiary is the quietest
                // of the three in this theme, so it carries the largest blob.
                colors: [scheme.primary, scheme.tertiary, scheme.secondary],
                opacity: opacity,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Paints the blobs. Pure: everything it needs arrives through the constructor.
class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.animation,
    required this.colors,
    required this.opacity,
  }) : super(repaint: animation);

  /// Drives repainting. Null means a single still frame.
  final Animation<double>? animation;

  final List<Color> colors;
  final double opacity;

  /// Each blob's resting place, size, and how far it wanders, as fractions of
  /// the shortest side so the composition holds on a phone and on a desktop.
  static const List<_Blob> _blobs = [
    _Blob(cx: 0.18, cy: 0.16, radius: 0.62, driftX: 0.07, driftY: 0.05, phase: 0.0),
    _Blob(cx: 0.86, cy: 0.30, radius: 0.52, driftX: 0.05, driftY: 0.07, phase: 0.37),
    _Blob(cx: 0.52, cy: 0.88, radius: 0.72, driftX: 0.06, driftY: 0.04, phase: 0.71),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation?.value ?? 0.0;
    final shortest = math.min(size.width, size.height);

    // One layer for all three blobs, blurred as a whole. Blurring the layer
    // rather than each circle is what removes every hard edge where two blobs
    // overlap, and it is one filter pass instead of three.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: shortest * 0.22,
          sigmaY: shortest * 0.22,
          tileMode: TileMode.decal,
        ),
    );

    for (var i = 0; i < _blobs.length; i++) {
      final blob = _blobs[i];

      // Sine and cosine of the phase: continuous, and identical at t=0 and
      // t=1, so the loop never jumps. Different multiples per axis give each
      // blob an unhurried path that does not simply retrace itself.
      final angle = (t + blob.phase) * 2 * math.pi;
      final dx = math.sin(angle) * blob.driftX;
      final dy = math.cos(angle * 0.8) * blob.driftY;

      final center = Offset(
        (blob.cx + dx) * size.width,
        (blob.cy + dy) * size.height,
      );

      canvas.drawCircle(
        center,
        blob.radius * shortest,
        Paint()..color = colors[i % colors.length].withValues(alpha: opacity),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) {
    // The animation repaints through `repaint:`; this only catches a theme
    // change, where the colours or the opacity are genuinely different.
    return oldDelegate.opacity != opacity ||
        !listEquals(oldDelegate.colors, colors) ||
        oldDelegate.animation != animation;
  }
}

@immutable
class _Blob {
  const _Blob({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.driftX,
    required this.driftY,
    required this.phase,
  });

  final double cx;
  final double cy;
  final double radius;
  final double driftX;
  final double driftY;

  /// Offset into the shared loop, so the blobs do not move in unison.
  final double phase;
}
