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

  /// Not initState: the loop duration comes from the inherited level.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.animate && _controller == null) {
      _start();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _start() {
    final motion = AppMotion.of(context);
    // `repeat` with a sine/cosine-driven painter is seamless: phase 1.0 paints
    // exactly what phase 0.0 paints, so the restart cannot be seen.
    _controller = AnimationController(
      vsync: this,
      duration: motion.backgroundLoop,
    )..repeat();
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
    final motion = AppMotion.of(context);

    final opacity =
        (isDark ? motion.blobOpacityDark : motion.blobOpacityLight) *
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
                // Three related colours from the theme and nothing else. At
                // the rich level each blob travels between them over the
                // loop, which is what gives the background its slow change of
                // hue without ever introducing a colour the theme does not
                // already use.
                colors: [scheme.primary, scheme.tertiary, scheme.secondary],
                opacity: opacity,
                drift: motion.blobDrift,
                blur: motion.blobBlur,
                count: motion.blobCount,
                colourShift: motion.blobColourShift,
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
    required this.drift,
    required this.blur,
    required this.count,
    required this.colourShift,
  }) : super(repaint: animation);

  /// Drives repainting. Null means a single still frame.
  final Animation<double>? animation;

  final List<Color> colors;
  final double opacity;

  /// How far a blob wanders, as a fraction of the screen.
  final double drift;

  /// Blur sigma as a fraction of the shortest side. Lower is both sharper and
  /// cheaper, which is why the rich level blurs LESS rather than more.
  final double blur;

  /// How many blobs to draw.
  final int count;

  /// How far a blob's colour travels towards the next one, 0 to 1.
  final double colourShift;

  /// Each blob's resting place, size, and how far it wanders, as fractions of
  /// the shortest side so the composition holds on a phone and on a desktop.
  /// The drift values are unit weights; the level's own [drift] scales them,
  /// so one number moves the whole composition.
  static const List<_Blob> _blobs = [
    _Blob(cx: 0.18, cy: 0.16, radius: 0.62, wx: 1.0, wy: 0.75, phase: 0.0),
    _Blob(cx: 0.86, cy: 0.30, radius: 0.52, wx: 0.75, wy: 1.0, phase: 0.37),
    _Blob(cx: 0.52, cy: 0.88, radius: 0.72, wx: 0.9, wy: 0.6, phase: 0.71),
    // The fourth is drawn only at the rich level, and is the smallest and
    // fastest-travelling of the four so the composition never looks static.
    _Blob(cx: 0.72, cy: 0.62, radius: 0.44, wx: 1.1, wy: 0.9, phase: 0.18),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation?.value ?? 0.0;
    final shortest = math.min(size.width, size.height);

    // One layer for every blob, blurred as a whole. Blurring the layer rather
    // than each circle is what removes every hard edge where two blobs
    // overlap, and it is one filter pass instead of four.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: shortest * blur,
          sigmaY: shortest * blur,
          tileMode: TileMode.decal,
        ),
    );

    final drawn = math.min(count, _blobs.length);

    for (var i = 0; i < drawn; i++) {
      final blob = _blobs[i];

      // Sine and cosine of the phase: continuous, and identical at t=0 and
      // t=1, so the loop never jumps. Different multiples per axis give each
      // blob an unhurried path that does not simply retrace itself.
      final angle = (t + blob.phase) * 2 * math.pi;
      final dx = math.sin(angle) * blob.wx * drift;
      final dy = math.cos(angle * 0.8) * blob.wy * drift;

      final center = Offset(
        (blob.cx + dx) * size.width,
        (blob.cy + dy) * size.height,
      );

      canvas.drawCircle(
        center,
        blob.radius * shortest,
        Paint()..color = _colourFor(i, t).withValues(alpha: opacity),
      );
    }

    canvas.restore();
  }

  /// The colour of blob [i] at phase [t].
  ///
  /// Each blob drifts from its own colour towards the next one in the list and
  /// back again over the loop. The palette is only ever the theme's primary,
  /// tertiary and secondary, so however far it travels the result is always a
  /// colour the app already uses - never a hue invented by interpolation into
  /// something unrelated.
  Color _colourFor(int i, double t) {
    final base = colors[i % colors.length];
    if (colourShift <= 0) return base;

    final next = colors[(i + 1) % colors.length];

    // A cosine, so the colour arrives back exactly where it began and the loop
    // stays seamless in hue as well as in position.
    final wave = (1 - math.cos((t + _blobs[i].phase) * 2 * math.pi)) / 2;

    return Color.lerp(base, next, wave * colourShift) ?? base;
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) {
    // The animation repaints through `repaint:`; this only catches a theme or
    // level change, where the composition is genuinely different.
    return oldDelegate.opacity != opacity ||
        !listEquals(oldDelegate.colors, colors) ||
        oldDelegate.animation != animation ||
        oldDelegate.drift != drift ||
        oldDelegate.blur != blur ||
        oldDelegate.count != count ||
        oldDelegate.colourShift != colourShift;
  }
}

@immutable
class _Blob {
  const _Blob({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.wx,
    required this.wy,
    required this.phase,
  });

  final double cx;
  final double cy;
  final double radius;

  /// Relative drift weights, scaled by the level's own drift value.
  final double wx;
  final double wy;

  /// Offset into the shared loop, so the blobs do not move in unison.
  final double phase;
}
