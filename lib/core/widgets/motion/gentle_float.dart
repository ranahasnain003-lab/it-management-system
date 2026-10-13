/// A very small rise and fall, for an empty state's icon.
///
/// Three pixels over three seconds. At that size it is barely a movement at
/// all - it stops an empty screen looking frozen or broken, without becoming
/// something to watch. Anything larger or faster would turn "there is nothing
/// here yet" into a decoration, which is not what an empty inventory screen
/// should be doing.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class GentleFloat extends StatefulWidget {
  const GentleFloat({
    super.key,
    required this.child,
    required this.animate,
    this.distance = AppMotion.floatDistance,
  });

  final Widget child;

  /// False renders the child at rest, with no controller.
  final bool animate;

  final double distance;

  @override
  State<GentleFloat> createState() => _GentleFloatState();
}

class _GentleFloatState extends State<GentleFloat>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(GentleFloat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) {
      _start();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _start() {
    _controller = AnimationController(vsync: this, duration: AppMotion.float)
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
        // A full sine over the loop: up, back through centre, down, and
        // exactly back to the start, so the repeat has no seam.
        final offset =
            math.sin(controller.value * 2 * math.pi) * widget.distance;

        return Transform.translate(offset: Offset(0, offset), child: child);
      },
    );
  }
}
