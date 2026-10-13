/// Content arriving: a fade with an upward slide, and at the rich level a
/// slight scale up, played once.
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
    this.offset,
    this.duration,
    this.scaleFrom,
    this.curve,
  });

  final Widget child;

  /// False renders the finished state immediately: full opacity, no offset,
  /// no scale, and no controller is ever created.
  final bool animate;

  /// How long to wait before starting, which is how the stagger is built.
  final Duration delay;

  /// How far below its resting place the child starts. Defaults to the
  /// level's [AppMotion.slideLarge].
  final double? offset;

  /// Defaults to the level's [AppMotion.screen].
  final Duration? duration;

  /// What to scale from. Defaults to the level's [AppMotion.entranceScale],
  /// which is 1.0 at the subtle level - no scaling at all.
  final double? scaleFrom;

  /// Defaults to the level's [AppMotion.enter].
  final Curve? curve;

  @override
  State<EntranceFadeSlide> createState() => _EntranceFadeSlideState();
}

class _EntranceFadeSlideState extends State<EntranceFadeSlide>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _started = false;

  /// Created here rather than in initState because the duration comes from the
  /// animation level, which is an inherited value and cannot be read before
  /// dependencies are available.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.animate) return;

    _started = true;
    final motion = AppMotion.of(context);

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration ?? motion.screen,
    );

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

    final motion = AppMotion.of(context);
    final offset = widget.offset ?? motion.slideLarge;
    final scaleFrom = widget.scaleFrom ?? motion.entranceScale;

    final curved = CurvedAnimation(
      parent: controller,
      curve: widget.curve ?? motion.enter,
    );

    return AnimatedBuilder(
      animation: curved,
      // Built once and reused: the child does not depend on the animation, so
      // rebuilding it on every frame would be waste.
      child: widget.child,
      builder: (context, child) {
        final t = curved.value;

        // Opacity is driven by the eased value clamped to 0-1: an overshooting
        // curve (the stat cards' easeOutBack) would otherwise push opacity
        // past 1 and assert.
        final opacity = t.clamp(0.0, 1.0);

        Widget result = Transform.translate(
          offset: Offset(0, (1 - t) * offset),
          child: child,
        );

        if (scaleFrom != 1.0) {
          result = Transform.scale(
            scale: scaleFrom + (1 - scaleFrom) * t,
            child: result,
          );
        }

        return Opacity(opacity: opacity, child: result);
      },
    );
  }
}
