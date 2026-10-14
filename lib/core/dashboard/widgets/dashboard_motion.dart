/// The dashboard's opening sequence, and the rules that keep it honest.
///
/// ## One controller, not forty
///
/// Everywhere else in the app an entrance is a widget that owns its own
/// controller and starts it when it is built. That is fine for a form, and
/// wrong for a dashboard, because a dashboard is rebuilt constantly: a
/// Firestore tick, a notice appearing above the grid, an [AppStateSwitcher]
/// swapping a skeleton for the real cards - each of those tears down and
/// rebuilds subtrees. Every rebuilt subtree would start its entrance again,
/// and the screen would blink and re-roll its figures while somebody was
/// reading them.
///
/// So the whole sequence is one [AnimationController], owned by
/// [DashboardMotionHost] and read through [DashboardMotion]. Each part of the
/// screen carves its slot out of it with an [Interval]. A widget rebuilt
/// halfway through simply reads the controller's current value and draws
/// itself at that point; a widget rebuilt after it has finished reads 1.0 and
/// is simply there. Replaying becomes impossible by construction rather than
/// by a flag somebody has to remember to check.
///
/// ## When it replays
///
/// Every time the dashboard is opened, which is what people asked for - not
/// once per session, which is what it used to be. "Opened" means:
///
///   * the screen was mounted (a fresh route, or the web shell swapping the
///     page in), or
///   * the screen's route became current again after something was pushed on
///     top of it and then popped.
///
/// The second case is detected without a [NavigatorObserver]: `_ModalScope`
/// notifies its dependents when `isCurrent` changes, so reading
/// `ModalRoute.of(context)?.isCurrent` in [State.didChangeDependencies] is
/// enough, and it works on both routers.
///
/// A data refresh is none of those things, so it cannot replay the sequence.
library;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

// =============================================================================
// THE SEQUENCE
// =============================================================================

/// Where each part of the screen sits inside the opening sequence.
///
/// All values are fractions of [AppMotion.dashboardEntrance], so the whole
/// sequence is authored here and the order cannot drift between the Android
/// screen and the web page.
abstract final class DashboardStage {
  /// The hero band drops in and fades up. First, and alone, so there is a
  /// moment where it is the only thing that has arrived.
  static const Interval hero = Interval(0.0, 0.28, curve: Curves.easeOutCubic);

  /// Then the greeting, the name, the pills and the description, line by
  /// line. Overlapping, so it reads as one movement rather than four.
  static const Interval greeting = Interval(
    0.10,
    0.34,
    curve: Curves.easeOutCubic,
  );
  static const Interval name = Interval(
    0.16,
    0.40,
    curve: Curves.easeOutCubic,
  );
  static const Interval pills = Interval(
    0.22,
    0.46,
    curve: Curves.easeOutCubic,
  );
  static const Interval description = Interval(
    0.28,
    0.52,
    curve: Curves.easeOutCubic,
  );

  /// Where the KPI cards start arriving, and how much of the window each one
  /// takes. [kpiStep] is the stagger: 0.07 of 1450ms is about 100ms, which is
  /// the middle of the 90-120ms that reads as a sequence rather than as a
  /// ripple.
  static const double kpiStart = 0.26;
  static const double kpiStep = 0.07;
  static const double kpiSpan = 0.22;

  /// Every figure counts up over the same window, however its card is
  /// staggered. 0.78 of 1450ms is about 1.13s - roughly the 1.2s people
  /// asked for, and the same for the first card and the last, so the grid
  /// settles together instead of trailing off.
  static const Interval counting = Interval(
    0.22,
    1.0,
    curve: Curves.easeOutCubic,
  );

  /// The section headings above the charts.
  static const Interval sectionLabel = Interval(
    0.38,
    0.58,
    curve: Curves.easeOutCubic,
  );

  /// The donut sweeps clockwise and the bars grow, slightly after the cards
  /// so the eye is led down the page.
  static const Interval donut = Interval(0.42, 0.88, curve: Curves.easeOutCubic);
  static const Interval bars = Interval(0.45, 0.92, curve: Curves.easeOutCubic);

  /// The timeline's rail draws downward, then the entries appear along it.
  static const Interval rail = Interval(0.55, 0.86, curve: Curves.easeOutCubic);
  static const double timelineStart = 0.60;
  static const double timelineStep = 0.045;
  static const double timelineSpan = 0.24;

  /// The quick actions pop in last, and are the only part that overshoots.
  static const double actionsStart = 0.78;
  static const double actionsStep = 0.042;
  static const double actionsSpan = 0.22;

  /// The slot for the card at [index] in a staggered run.
  static Interval slot(
    int index, {
    required double start,
    required double step,
    required double span,
    Curve curve = Curves.easeOutCubic,
  }) {
    final begin = (start + step * index).clamp(0.0, 0.999);
    final end = (begin + span).clamp(begin + 0.001, 1.0);

    return Interval(begin, end, curve: curve);
  }
}

// =============================================================================
// THE HOST
// =============================================================================

/// Owns the dashboard's one entrance controller and hands it down.
///
/// Wrap the dashboard body in this. Everything below reads [DashboardMotion].
class DashboardMotionHost extends StatefulWidget {
  const DashboardMotionHost({super.key, required this.child});

  final Widget child;

  @override
  State<DashboardMotionHost> createState() => _DashboardMotionHostState();
}

class _DashboardMotionHostState extends State<DashboardMotionHost>
    with SingleTickerProviderStateMixin {
  AnimationController? _entrance;

  /// Whether the route was current at the last check. A false -> true change
  /// is the dashboard being returned to, which replays the sequence.
  bool _wasCurrent = true;

  /// Whether motion was enabled at the last check, so turning animation back
  /// on in Settings gives the sequence rather than leaving the screen static
  /// until it is next opened.
  bool? _wasEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final enabled = AppMotion.enabled(context);
    final motion = AppMotion.of(context);

    if (enabled != _wasEnabled) {
      _wasEnabled = enabled;

      if (!enabled) {
        // Off, or the operating system is asking for no motion. No controller
        // at all: every Staged below reads 1.0 and the screen is simply
        // there. This is also what keeps pumpAndSettle usable in tests.
        _entrance?.dispose();
        _entrance = null;
        return;
      }

      _entrance?.dispose();
      _entrance = AnimationController(
        vsync: this,
        duration: motion.dashboardEntrance,
      )..forward();
    }

    if (!enabled) return;

    // Pushed-over-and-popped-back. `isCurrent` is false for the whole time
    // something sits on top, and `_ModalScope` rebuilds its dependents when
    // it flips, so no NavigatorObserver is needed.
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    if (isCurrent && !_wasCurrent) {
      _entrance?.forward(from: 0);
    }

    _wasCurrent = isCurrent;
  }

  @override
  void dispose() {
    _entrance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final enabled = AppMotion.enabled(context);

    return DashboardMotion(
      entrance: _entrance ?? const AlwaysStoppedAnimation<double>(1),
      // Loops are a rich-level thing. Subtle keeps the opening sequence and
      // nothing that starts by itself.
      loops: enabled && motion.dashboardLoops,
      motion: motion,
      child: widget.child,
    );
  }
}

/// The dashboard's motion, read by everything inside it.
class DashboardMotion extends InheritedWidget {
  const DashboardMotion({
    super.key,
    required this.entrance,
    required this.loops,
    required this.motion,
    required super.child,
  });

  /// The opening sequence, 0 to 1. A constant 1 when motion is off, so
  /// everything below renders in its finished state without a special case.
  final Animation<double> entrance;

  /// Whether the always-alive loops run.
  final bool loops;

  final AppMotion motion;

  static DashboardMotion of(BuildContext context) {
    final found = context
        .dependOnInheritedWidgetOfExactType<DashboardMotion>();

    // Outside a host - a widget test rendering one card on its own - the
    // sensible answer is "finished, and still".
    return found ??
        DashboardMotion(
          entrance: const AlwaysStoppedAnimation<double>(1),
          loops: false,
          motion: AppMotion.rich,
          child: const SizedBox.shrink(),
        );
  }

  @override
  bool updateShouldNotify(DashboardMotion oldWidget) {
    return oldWidget.entrance != entrance ||
        oldWidget.loops != loops ||
        oldWidget.motion.level != motion.level;
  }
}

// =============================================================================
// STAGED
// =============================================================================

/// One part of the opening sequence: fades, rises and scales over its [slot].
///
/// The child is passed to [AnimatedBuilder] rather than built inside it, so a
/// frame of the sequence rebuilds this wrapper and nothing underneath. That is
/// what keeps a Firestore-backed card from rebuilding sixty times a second
/// while it arrives.
class Staged extends StatelessWidget {
  const Staged({
    super.key,
    required this.slot,
    required this.child,
    this.slide,
    this.scaleFrom,
    this.slideFromTop = false,
  });

  final Interval slot;
  final Widget child;

  /// How far it travels, in logical pixels. Defaults to the level's card
  /// slide.
  final double? slide;

  /// What it scales from. Null means no scaling.
  final double? scaleFrom;

  /// Whether it comes down from above rather than up from below. The hero
  /// drops in; everything else rises.
  final bool slideFromTop;

  @override
  Widget build(BuildContext context) {
    final dashboard = DashboardMotion.of(context);
    final entrance = dashboard.entrance;
    final distance = slide ?? dashboard.motion.dashboardCardSlide;

    // Already finished - motion off, or this widget rebuilt after its slot
    // passed. No AnimatedBuilder, no listener, nothing to repaint.
    if (entrance.value >= 1.0 && !entrance.isAnimating) {
      return child;
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: entrance,
        child: child,
        builder: (context, child) {
          final t = slot.transform(entrance.value.clamp(0.0, 1.0));
          final offset = (1 - t) * distance * (slideFromTop ? -1 : 1);

          Widget result = Transform.translate(
            offset: Offset(0, offset),
            child: child,
          );

          if (scaleFrom != null) {
            result = Transform.scale(
              scale: scaleFrom! + (1 - scaleFrom!) * t,
              child: result,
            );
          }

          return Opacity(opacity: t.clamp(0.0, 1.0), child: result);
        },
      ),
    );
  }
}

/// The value of [slot] right now, for callers that animate something other
/// than a transform - a chart's sweep, a rail's length, a digit's roll.
double stageValue(BuildContext context, Interval slot) {
  final entrance = DashboardMotion.of(context).entrance;

  return slot.transform(entrance.value.clamp(0.0, 1.0));
}
