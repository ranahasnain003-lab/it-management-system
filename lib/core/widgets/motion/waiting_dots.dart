/// Three dots brightening and dimming in turn, while an answer is awaited.
///
/// The wave runs left to right on a 1.2s cycle. It says "still working"
/// without the impatience of a spinner, which matters here: the model runs on
/// a laptop and a first answer can take a few seconds.
///
/// The dots are removed by the caller the moment any text arrives, or the
/// request fails - they never overlap the answer.
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

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(WaitingDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) {
      _start();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _start() {
    _controller = AnimationController(vsync: this, duration: AppMotion.dots)
      ..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _dot(double opacity) {
    return Container(
      width: widget.size,
      height: widget.size,
      margin: EdgeInsets.symmetric(horizontal: widget.size * 0.28),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      // Still, but present. A mid-range opacity so it does not read as a
      // disabled control.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.count; i++)
            _dot((AppMotion.dotMin + AppMotion.dotMax) / 2),
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
              _dot(_opacityFor(i, controller.value)),
          ],
        );
      },
    );
  }

  /// Where dot [index] is in the wave at phase [t].
  ///
  /// Each dot trails the one before it by a third of the cycle, so the
  /// brightness travels along the row. Built from a cosine, so the value and
  /// its slope match at both ends and the loop has no seam.
  double _opacityFor(int index, double t) {
    final phase = t - (index / widget.count);
    final wave = (1 - math.cos(phase * 2 * math.pi)) / 2;

    return AppMotion.dotMin + (AppMotion.dotMax - AppMotion.dotMin) * wave;
  }
}
