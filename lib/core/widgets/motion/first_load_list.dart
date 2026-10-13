/// Staggers the first rows of a list into view, once per screen visit.
///
/// The rule this enforces is the hard part, not the animation. Rows animate
/// only on the very first load of the screen:
///
///   - not on scroll, so row 40 never fades in as it is reached;
///   - not on a pull-to-refresh;
///   - not when Firestore pushes an update;
///   - and only the first handful, so a long list does not ripple.
///
/// A list that animates as you scroll is the single most common way this kind
/// of effect turns from polish into irritation, which is why the gate is a
/// one-way latch rather than a flag that anything can reset.
library;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import 'entrance.dart';

/// Tracks whether a given list has already made its entrance.
///
/// Held by the screen's State, so it lives exactly as long as the screen does:
/// leaving and coming back is a new visit and animates again, while anything
/// that merely rebuilds the same screen does not.
class FirstLoadEntrance {
  /// How many rows animate. Past this they appear immediately, so a list of
  /// two thousand assets does not stagger for a minute.
  static const int maxRows = 10;

  bool _spent = false;

  /// True while the first load is still entitled to animate.
  bool get isPending => !_spent;

  /// Marks the entrance as used. Called once the rows have been built.
  void spend() => _spent = true;

  /// Wraps row [index], or returns it untouched when the entrance is over.
  Widget wrap(BuildContext context, int index, Widget child) {
    if (_spent || index >= maxRows || !AppMotion.enabled(context)) return child;

    final motion = AppMotion.of(context);

    return EntranceFadeSlide(
      // Keyed by position so the row keeps its own animation as the list
      // builds; without it a recycled element could restart a neighbour's.
      key: ValueKey('row-enter-$index'),
      animate: true,
      delay: motion.staggerList * index,
      offset: motion.slideList,
      duration: motion.short,
      // No scale and no overshoot on list rows: they are dense, and anything
      // more than a short slide reads as noise.
      scaleFrom: 1.0,
      child: child,
    );
  }
}
