/// One short horizontal shake, to say "no" without words.
///
/// Used when a sign-in is refused. It is small and damped on purpose: enough
/// to draw the eye back to the form, not enough to feel like a complaint. The
/// error message still says what went wrong; this only points at it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class ShakeOnSignal extends StatefulWidget {
  const ShakeOnSignal({
    super.key,
    required this.child,
    required this.animate,
    required this.signal,
    this.distance,
  });

  final Widget child;

  /// False renders the child untouched and never creates a controller.
  final bool animate;

  /// Shakes whenever this value changes to something new and non-zero.
  ///
  /// A counter rather than a boolean, so two refusals in a row each shake -
  /// with a flag, the second would set `true` over `true` and do nothing,
  /// leaving the person with no feedback at all on a repeated mistake.
  final int signal;

  /// The furthest the child moves from centre. Defaults to the level.
  final double? distance;

  @override
  State<ShakeOnSignal> createState() => _ShakeOnSignalState();
}

class _ShakeOnSignalState extends State<ShakeOnSignal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: the duration comes from the inherited animation level.
    if (widget.animate && _controller == null) _create();
  }

  void _create() {
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.of(context).shake,
    );
  }

  @override
  void didUpdateWidget(ShakeOnSignal oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.animate && _controller == null) {
      _create();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
      return;
    }

    if (widget.signal != oldWidget.signal && widget.signal > 0) {
      _controller?.forward(from: 0);
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

    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final t = controller.value;

        // One and a half oscillations, damped to nothing by the end: out,
        // back, a smaller out, still. `(1 - t)` is what makes it settle rather
        // than stop dead, which is the difference between a shake and a jolt.
        final distance = widget.distance ?? AppMotion.of(context).shakeDistance;
        final offset = math.sin(t * math.pi * 3) * (1 - t) * distance;

        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
    );
  }
}
