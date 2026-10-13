/// Content arriving: a fade with a small upward slide, played once.
///
/// Once is the important part. These run when a screen is first built and
/// never again - not on a rebuild, not when Firestore delivers new data, not
/// on a pull-to-refresh. Content that re-animates every time a stream ticks is
/// the single fastest way to make an app feel unstable.
library;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class EntranceFadeSlide extends StatefulWidget {
  const EntranceFadeSlide({
    super.key,
    required this.child,
    required this.animate,
    this.delay = Duration.zero,
    this.offset = AppMotion.slideLarge,
    this.duration = AppMotion.screen,
  });

  final Widget child;

  /// False renders the finished state immediately: full opacity, no offset,
  /// and no controller is ever created.
  final bool animate;

  /// How long to wait before starting, which is how the stagger is built.
  final Duration delay;

  /// How far below its resting place the child starts, in logical pixels.
  final double offset;

  final Duration duration;

  @override
  State<EntranceFadeSlide> createState() => _EntranceFadeSlideState();
}

class _EntranceFadeSlideState extends State<EntranceFadeSlide>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;

    _controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.delay == Duration.zero) {
      _controller!.forward();
      return;
    }

    // The widget can be disposed while the delay is still pending - a screen
    // closed quickly, a test that pumps once - so the controller is checked
    // rather than assumed.
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      _controller?.forward();
    });
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

    final curved = CurvedAnimation(parent: controller, curve: AppMotion.enter);

    return AnimatedBuilder(
      animation: curved,
      // Built once and reused: the child does not depend on the animation, so
      // rebuilding it on every frame would be waste.
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, (1 - curved.value) * widget.offset),
            child: child,
          ),
        );
      },
    );
  }
}
