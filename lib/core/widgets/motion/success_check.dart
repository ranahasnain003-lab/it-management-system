/// The success mark: a circle draws, then the check inside it.
///
/// Shown after a deployment, transfer, return or request approval actually
/// succeeds. Never after a failure - a drawn tick is a statement that the
/// stock moved, and it must not appear unless it did.
///
/// About 700ms to draw, a short hold, then it fades. It is deliberately
/// drawn rather than faded in whole: a stroke that travels reads as the app
/// confirming something, where a tick that simply appears reads as an icon.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_motion.dart';

/// Shows the success mark over the current screen, then removes it.
///
/// Returns as soon as it is on screen; the caller does not wait for it. It is
/// an overlay entry rather than a dialog so it never takes focus, never blocks
/// a back press, and cannot be dismissed into a half state.
///
/// Does nothing when motion is off, so a screen reader or a low-end phone is
/// not left with an undismissable square - the caller's own SnackBar or
/// message is what actually reports the outcome.
void showSuccessCheck(BuildContext context, {bool haptic = true}) {
  if (!AppMotion.enabled(context)) return;

  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  if (haptic && _supportsHaptics) {
    // Light: an acknowledgement, not an alert.
    HapticFeedback.lightImpact();
  }

  late OverlayEntry entry;
  var removed = false;

  entry = OverlayEntry(
    builder: (context) => _SuccessOverlay(
      onFinished: () {
        // Guarded: removing an entry twice throws, and the overlay can also
        // be torn down underneath it when the screen is popped.
        if (removed) return;
        removed = true;
        entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

/// Identifies the mark on screen, for tests and for debugging.
const Key successCheckKey = Key('success-check');

/// Haptics exist on phones; on desktop and web the call is a no-op at best and
/// an error at worst, so it is not made.
bool get _supportsHaptics {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return false;
  }
}

class _SuccessOverlay extends StatefulWidget {
  const _SuccessOverlay({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<_SuccessOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _draw;
  late final AnimationController _fade;

  bool _started = false;

  /// Started here rather than in initState because the durations come from
  /// the inherited animation level.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final motion = AppMotion.of(context);
    _draw = AnimationController(vsync: this, duration: motion.success);
    _fade = AnimationController(vsync: this, duration: motion.short, value: 1);

    _run();
  }

  /// The pause between the mark finishing and it fading.
  ///
  /// A real Timer rather than `Future.delayed`, because a Future cannot be
  /// cancelled: if the screen were popped mid-hold, the pending callback would
  /// outlive the widget and the test framework would rightly complain about a
  /// timer still pending after disposal.
  Timer? _hold;

  Future<void> _run() async {
    await _draw.forward();
    if (!mounted) return;

    _hold = Timer(AppMotion.of(context).successHold, () async {
      if (!mounted) return;
      await _fade.reverse();
      if (!mounted) return;
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return IgnorePointer(
      key: successCheckKey,
      child: FadeTransition(
        opacity: _fade,
        child: Center(
          child: RepaintBoundary(
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _CheckPainter(
                  progress: _draw,
                  color: colors.primary,
                  curve: AppMotion.of(context).enter,
                  onColor: colors.onPrimary,
                  filled: AppMotion.of(context).level == AnimationLevel.rich,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the ring, then the tick.
class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.progress,
    required this.color,
    required this.curve,
    required this.onColor,
    required this.filled,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  /// Passed in rather than looked up: a painter has no BuildContext, and
  /// keeping it pure is what lets it be driven straight from `repaint:`.
  final Curve curve;

  /// The colour the tick is drawn in when the disc is filled.
  final Color onColor;

  /// Rich: a filled disc with a white tick and one expanding ring.
  /// Subtle: the original outlined ring with a coloured tick.
  final bool filled;

  /// The ring owns the first 55% of the time, the tick the rest. The ring is
  /// the slower of the two because it travels much further.
  static const double _ringShare = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final t = curve.transform(progress.value);
    final center = Offset(size.width / 2, size.height / 2);
    // 0.26 rather than 0.30 so the expanding ring, which reaches 1.6x, still
    // fits inside the card instead of being clipped at its edges.
    final radius = math.min(size.width, size.height) * 0.26;

    final ringProgress = (t / _ringShare).clamp(0.0, 1.0);

    // --- the expanding ring -------------------------------------------------
    //
    // Rich only. One ring travels outwards and fades as it goes, which is what
    // makes the mark feel like an event rather than an icon appearing. It is a
    // stroked circle, not a glow: the design rules glow out.
    if (filled && t > 0.1) {
      final ripple = ((t - 0.1) / 0.9).clamp(0.0, 1.0);

      canvas.drawCircle(
        center,
        radius * (1.0 + ripple * 0.6),
        Paint()
          ..color = color.withValues(alpha: 0.28 * (1 - ripple))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }

    // --- the disc, or the drawn ring ----------------------------------------
    if (filled) {
      // The circle fills with the primary colour and the tick is cut out of it
      // in white, which reads far more strongly than an outline.
      canvas.drawCircle(center, radius * ringProgress, Paint()..color = color);
    } else if (ringProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        // From the top, clockwise, so it reads as being drawn rather than
        // appearing.
        -math.pi / 2,
        2 * math.pi * ringProgress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final stroke = Paint()
      ..color = filled ? onColor : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = filled ? 3.6 : 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // --- the tick -----------------------------------------------------------
    final tickProgress = ((t - _ringShare) / (1 - _ringShare)).clamp(0.0, 1.0);
    if (tickProgress <= 0) return;

    final start = center + Offset(-radius * 0.46, radius * 0.02);
    final elbow = center + Offset(-radius * 0.12, radius * 0.38);
    final end = center + Offset(radius * 0.50, -radius * 0.34);

    // The two legs are different lengths, so the stroke is split by distance
    // rather than in half - otherwise the pen visibly slows at the elbow.
    final firstLeg = (elbow - start).distance;
    final secondLeg = (end - elbow).distance;
    final travelled = (firstLeg + secondLeg) * tickProgress;

    final path = Path()..moveTo(start.dx, start.dy);

    if (travelled <= firstLeg) {
      final point = Offset.lerp(start, elbow, travelled / firstLeg)!;
      path.lineTo(point.dx, point.dy);
    } else {
      path.lineTo(elbow.dx, elbow.dy);
      final point = Offset.lerp(
        elbow,
        end,
        (travelled - firstLeg) / secondLeg,
      )!;
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.curve != curve ||
      oldDelegate.onColor != onColor ||
      oldDelegate.filled != filled;
}
