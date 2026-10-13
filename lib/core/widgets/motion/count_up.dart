/// A figure counting up to its value, once.
///
/// The single exception to this app's rule against animating numbers people
/// have to read. It runs on the first load of a session and never again: when
/// Firestore later delivers a new total, the new figure simply appears.
///
/// The reason for the exception is that the first sight of a dashboard is the
/// one moment the numbers are not yet information - nobody is reading a value
/// they have not been shown before. Every later change IS information, and
/// animating it would mean a figure that cannot be trusted while it settles,
/// on a screen whose whole job is to be trusted.
library;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class CountUpText extends StatefulWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.animate,
    required this.style,
    this.format,
  });

  /// The number to show.
  final int value;

  /// False, or any later change to [value], shows the figure immediately.
  final bool animate;

  final TextStyle? style;

  /// How to render the number, for thousands separators and the like.
  final String Function(int value)? format;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  /// Where this run started, so a count-up always rises from zero but a later
  /// change does not animate at all.
  int _shown = 0;

  bool _started = false;

  /// Started here rather than in initState because the duration comes from
  /// the inherited animation level.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (!widget.animate) {
      _shown = widget.value;
      return;
    }

    _controller =
        AnimationController(
            vsync: this,
            duration: AppMotion.of(context).countUp,
          )
          ..addListener(_tick)
          ..forward();
  }

  void _tick() {
    final controller = _controller;
    if (controller == null) return;

    final eased = AppMotion.of(context).enter.transform(controller.value);
    final next = (widget.value * eased).round();

    if (next != _shown) setState(() => _shown = next);
  }

  @override
  void didUpdateWidget(CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A new figure from Firestore. Shown as it is: this is information now,
    // and a number that is still settling cannot be read.
    if (widget.value != oldWidget.value) {
      _controller?.stop();
      setState(() => _shown = widget.value);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_tick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.format?.call(_shown) ?? '$_shown';

    return Text(
      text,
      style: widget.style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
