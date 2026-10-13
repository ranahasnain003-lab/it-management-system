/// A card or button that responds to being touched.
///
/// Presses scale it down a little; on the web, a hover lifts it with a
/// stronger shadow. Both are off at the subtle level, where the values are
/// 1.0 and 0, so this widget becomes a plain pass-through.
///
/// The response is what makes a tile feel like a control rather than a
/// picture. It is small on purpose: this is a government asset register, and a
/// card that squashes dramatically reads as a toy.
library;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.animate,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final bool animate;
  final VoidCallback? onTap;

  /// Used by the hover shadow, so it follows the card's own corners.
  final BorderRadius? borderRadius;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final colors = Theme.of(context).colorScheme;

    // 1.0 and 0 at the subtle level: nothing to do, so nothing is wrapped.
    final canPress = widget.animate && motion.pressScale != 1.0;
    final canHover = widget.animate && motion.hoverLift > 0;

    if (!canPress && !canHover) {
      return widget.onTap == null
          ? widget.child
          : GestureDetector(
              // Opaque, not the default deferToChild: a child with no
              // decoration does not absorb hits, which would leave the tile
              // dead whenever animations are off or set to subtle.
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: widget.child,
            );
    }

    final scale = _pressed ? motion.pressScale : 1.0;
    final lift = _hovered && !_pressed ? -motion.hoverLift : 0.0;

    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: canHover ? (_) => setState(() => _hovered = true) : null,
      onExit: canHover ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: canPress ? (_) => setState(() => _pressed = true) : null,
        onTapUp: canPress ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: canPress ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: motion.micro,
          curve: motion.move,
          child: AnimatedContainer(
            duration: motion.micro,
            curve: motion.move,
            transform: Matrix4.translationValues(0, lift, 0),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: _hovered && !_pressed
                  ? [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.13),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
