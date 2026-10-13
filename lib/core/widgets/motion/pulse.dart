/// A gentle opacity pulse: something is happening, nothing is wrong.
///
/// Used on the logo while the account, profile, roles and permissions load.
/// It replaces a spinner because a spinner implies a measurable wait, and this
/// one is usually over in a moment; a slow breath says "working" without
/// drawing attention to itself.
///
/// It only ever changes opacity. No rotation, no scaling, no bounce - a
/// turning or throbbing logo is exactly the cheap look this app avoids.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class PulseFade extends StatefulWidget {
  const PulseFade({super.key, required this.child, required this.animate});

  final Widget child;

  /// False renders the child at full opacity, with no controller at all.
  final bool animate;

  @override
  State<PulseFade> createState() => _PulseFadeState();
}

class _PulseFadeState extends State<PulseFade>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(PulseFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) {
      _start();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _start() {
    _controller = AnimationController(vsync: this, duration: AppMotion.pulse)
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

    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        // A cosine wave between pulseMin and 1. Seamless by construction: the
        // value and its slope match at both ends of the loop, so the breath
        // never stutters at the restart.
        final wave = (1 - math.cos(controller.value * 2 * math.pi)) / 2;
        final opacity =
            AppMotion.pulseMin + (1 - AppMotion.pulseMin) * (1 - wave);

        return Opacity(opacity: opacity, child: child);
      },
    );
  }
}
