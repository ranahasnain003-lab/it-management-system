/// A soft band of light travelling across a loading placeholder.
///
/// Built by hand rather than with a package: it is one gradient and one
/// controller, and a dependency for that would be hard to justify.
///
/// It sits on skeleton blocks while figures load, instead of a spinner. A
/// spinner says "wait"; a skeleton with a shimmer says "this is where the
/// numbers will be", which is the more useful thing to say when the shape of
/// the screen is already known.
library;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, required this.animate});

  final Widget child;

  /// False renders the child plainly. The skeleton still shows - the content
  /// is still loading - it simply does not move.
  final bool animate;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) {
      _start();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _start() {
    _controller = AnimationController(vsync: this, duration: AppMotion.shimmer)
      ..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;

    final highlight = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: AppMotion.shimmerOpacity);

    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          // The band lights the skeleton up rather than cutting it out.
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            // Travels from fully off one side to fully off the other, so the
            // band is never parked at an edge when the loop restarts.
            final slide = -1.0 + (controller.value * 3.0);

            return LinearGradient(
              begin: Alignment(slide - 1, -0.3),
              end: Alignment(slide + 1, 0.3),
              colors: [Colors.transparent, highlight, Colors.transparent],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}
