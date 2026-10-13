/// A soft circle breathing behind an empty state's icon.
///
/// Rich level only: at the subtle level the halo is drawn at a constant size
/// and opacity, so the composition is identical but nothing moves.
///
/// It is a filled circle, not a glow or a bloom - the design rules out glow
/// outright. What it adds is a sense that the screen is alive while it has
/// nothing to show.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class PulsingHalo extends StatefulWidget {
  const PulsingHalo({
    super.key,
    required this.child,
    required this.animate,
    required this.color,
  });

  final Widget child;
  final bool animate;
  final Color color;

  @override
  State<PulsingHalo> createState() => _PulsingHaloState();
}

class _PulsingHaloState extends State<PulsingHalo>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulsingHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final wanted =
        widget.animate && AppMotion.of(context).level == AnimationLevel.rich;

    if (wanted && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        // Shares the float's cycle, so the icon and the circle behind it
        // breathe together instead of beating against each other.
        duration: AppMotion.of(context).float,
      )..repeat();
    } else if (!wanted && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    Widget halo(double scale, double opacity) {
      return Container(
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
        child: Transform.scale(scale: 1 / scale, child: widget.child),
      );
    }

    if (controller == null) {
      return Transform.scale(scale: 1.0, child: halo(1.0, 0.0));
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // A cosine, so it returns exactly to its start and the loop is
        // seamless. The circle grows as it fades, which reads as a breath
        // rather than as a blink.
        final wave = (1 - math.cos(controller.value * 2 * math.pi)) / 2;
        final scale = 1.0 + 0.18 * wave;
        final opacity = 0.10 * (1 - wave);

        return Transform.scale(scale: scale, child: halo(scale, opacity));
      },
    );
  }
}
