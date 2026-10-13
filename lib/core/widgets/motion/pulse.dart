/// A gentle breath: opacity, and at the rich level a slight scale.
///
/// Used on the logo while the account, profile, roles and permissions load.
/// It replaces a spinner because a spinner implies a measurable wait, and this
/// one is usually over in a moment; a slow breath says "working" without
/// drawing attention to itself.
///
/// It never rotates. A turning logo is exactly the cheap look this app avoids,
/// at every level.
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

  /// Started here rather than in initState because its duration comes from the
  /// animation level, which is inherited and cannot be read any earlier.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: AppMotion.of(context).pulse,
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;

    final motion = AppMotion.of(context);

    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        // A cosine wave. Seamless by construction: the value and its slope
        // match at both ends of the loop, so the breath never stutters at the
        // restart.
        final wave = (1 - math.cos(controller.value * 2 * math.pi)) / 2;
        final eased = 1 - wave;

        final opacity = motion.pulseMin + (1 - motion.pulseMin) * eased;

        Widget result = Opacity(opacity: opacity, child: child);

        // 1.0 at the subtle level, so nothing scales there at all.
        if (motion.pulseScale != 1.0) {
          result = Transform.scale(
            scale: 1 + (motion.pulseScale - 1) * eased,
            child: result,
          );
        }

        return result;
      },
    );
  }
}
