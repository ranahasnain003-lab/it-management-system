/// A faint band of light crossing a button while it waits to be pressed.
///
/// Rich level only. It runs on a long cycle with a long pause between passes,
/// so it reads as the button being ready rather than as something demanding
/// attention - a sweep every second would be a flashing advert, which is
/// exactly what this must not be.
///
/// It is drawn inside the button's own shape and never changes its colour,
/// size or position, so the control underneath behaves identically.
library;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class IdleSweep extends StatefulWidget {
  const IdleSweep({
    super.key,
    required this.child,
    required this.animate,
    this.borderRadius,
  });

  final Widget child;

  /// False renders the child untouched, with no controller.
  final bool animate;

  final BorderRadius? borderRadius;

  @override
  State<IdleSweep> createState() => _IdleSweepState();
}

class _IdleSweepState extends State<IdleSweep>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  /// The whole cycle, most of which is the pause.
  static const Duration _cycle = Duration(milliseconds: 4200);

  /// The share of the cycle the band is actually travelling.
  static const double _travelShare = 0.3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(IdleSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final wanted =
        widget.animate && AppMotion.of(context).level == AnimationLevel.rich;

    if (wanted && _controller == null) {
      _controller = AnimationController(vsync: this, duration: _cycle)
        ..repeat();
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
    if (controller == null) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final t = controller.value;

                  // Off screen for most of the cycle: one pass, then a pause.
                  if (t > _travelShare) return const SizedBox.shrink();

                  final slide = -1.0 + (t / _travelShare) * 3.0;

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(slide - 0.6, -1),
                        end: Alignment(slide + 0.6, 1),
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.16),
                          Colors.transparent,
                        ],
                        stops: const [0.35, 0.5, 0.65],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
