/// Three dots brightening and dimming in turn, while an answer is awaited.
///
/// The wave runs left to right on a 1.2s cycle. At the rich level each dot
/// also rides up and down a few pixels, so the row reads as a wave travelling
/// rather than as three lights blinking.
///
/// It says "still working" without the impatience of a spinner, which matters
/// here: the model runs on a laptop and a first answer can take seconds. The
/// caller removes the dots the moment any text arrives, or the request fails,
/// so they never overlap the answer.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class WaitingDots extends StatefulWidget {
  const WaitingDots({
    super.key,
    required this.animate,
    required this.color,
    this.size = 6,
    this.count = 3,
  });

  /// False shows the dots evenly dimmed and still: the caller is still
  /// waiting, so they must stay visible, they simply do not move.
  final bool animate;

  final Color color;
  final double size;
  final int count;

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  /// Started here rather than in initState because its duration comes from the
  /// animation level, which is inherited and cannot be read any earlier.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WaitingDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: AppMotion.of(context).dots,
      )..repeat();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _dot(double opacity, double rise) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      margin: EdgeInsets.symmetric(horizontal: widget.size * 0.28),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );

    if (rise == 0) return dot;

    return Transform.translate(offset: Offset(0, rise), child: dot);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final motion = AppMotion.of(context);

    if (controller == null) {
      // Still, but present. A mid-range opacity so it does not read as a
      // disabled control.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.count; i++)
            _dot((motion.dotMin + motion.dotMax) / 2, 0),
        ],
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.count; i++)
              _dot(
                _waveAt(i, controller.value, motion.dotMin, motion.dotMax),
                // Negative is up. Zero at the subtle level, so nothing moves
                // there and only the brightness travels.
                -_waveAt(i, controller.value, 0, motion.dotWave),
              ),
          ],
        );
      },
    );
  }

  /// Where dot [index] sits in the wave at phase [t], between [low] and
  /// [high].
  ///
  /// Each dot trails the one before it by a third of the cycle, so the wave
  /// travels along the row. Built from a cosine, so the value and its slope
  /// match at both ends and the loop has no seam.
  double _waveAt(int index, double t, double low, double high) {
    final phase = t - (index / widget.count);
    final wave = (1 - math.cos(phase * 2 * math.pi)) / 2;

    return low + (high - low) * wave;
  }
}
