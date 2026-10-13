/// A small rise and fall, for an empty state's icon.
///
/// Three pixels at the subtle level, six at the rich one, over three seconds.
/// It stops an empty screen looking frozen without becoming something to
/// watch: "there is nothing here yet" should not turn into a decoration.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class GentleFloat extends StatefulWidget {
  const GentleFloat({
    super.key,
    required this.child,
    required this.animate,
    this.distance,
  });

  final Widget child;

  /// False renders the child at rest, with no controller.
  final bool animate;

  /// Defaults to the level's [AppMotion.floatDistance].
  final double? distance;

  @override
  State<GentleFloat> createState() => _GentleFloatState();
}

class _GentleFloatState extends State<GentleFloat>
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
  void didUpdateWidget(GentleFloat oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: AppMotion.of(context).float,
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

    final distance = widget.distance ?? AppMotion.of(context).floatDistance;

    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        // A full sine over the loop: up, back through centre, down, and
        // exactly back to the start, so the repeat has no seam.
        final offset = math.sin(controller.value * 2 * math.pi) * distance;

        return Transform.translate(offset: Offset(0, offset), child: child);
      },
    );
  }
}
