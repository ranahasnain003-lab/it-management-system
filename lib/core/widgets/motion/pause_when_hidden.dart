/// Stops every ticker in a subtree when the subtree is not being looked at.
///
/// Flutter already does most of this on its own, and it is worth being exact
/// about which parts, because the two gaps are the only reason this file
/// exists.
///
/// Already handled, with no code of ours:
///
///   * **A route covered by an opaque route.** `Overlay` builds every entry
///     below the topmost opaque one with `tickerEnabled: false`, which is a
///     `TickerMode(enabled: false)` (`_OverlayEntryWidgetState.build` in
///     `widgets/overlay.dart`). `TransitionRoute._handleStatusChanged` only
///     marks the route above as opaque once its push transition *completes*,
///     so the outgoing screen keeps animating exactly as long as it is still
///     visible and then stops. `CustomTransitionPage`, which both of this
///     app's routers use, defaults to `opaque: true, maintainState: true` -
///     the two flags this depends on.
///   * **A backgrounded app.** `SchedulerBinding
///     .handleAppLifecycleStateChanged` sets `framesEnabled = false` for
///     `hidden`, `paused` and `detached`; `scheduleFrame()` then returns
///     early, so no ticker callback ever runs again until the app is back.
///   * **A replaced route.** `context.go(...)` swaps the page rather than
///     stacking on it, so the old screen is disposed outright. There is no
///     ticker left to mute. This is what the web shell does.
///
/// NOT handled, which is what [PauseWhenHidden] adds:
///
///   * **A non-opaque route on top** - a dialog, a bottom sheet, a popup
///     menu. `PopupRoute.opaque` is `false`, so `Overlay` never reaches an
///     opaque entry and mutes nothing below it. A dashboard with a looping
///     gradient keeps repainting it at 60fps behind a modal.
///   * **`inactive`** - a phone call, the app switcher half-open, a desktop
///     window that lost focus. `framesEnabled` stays `true` there.
///
/// Two signals, because one is not enough:
///
///   * `ModalRoute.of(context)!.isCurrent` catches anything pushed onto *the
///     same* navigator, and `_ModalScopeStatus` notifies its dependents when
///     it changes, so this widget rebuilds with no observer to register.
///   * It is **not** enough by itself. `showDialog` defaults to
///     `useRootNavigator: true`, and under a `ShellRoute` the screen lives on
///     the shell's nested navigator - so a dialog lands on a *different*
///     navigator and the screen's own route stays `isCurrent`. That is what
///     [obscured] is for: a [ValueListenable] fed by a [ModalRouteObserver]
///     registered on the root navigator.
///
/// Nesting is safe. `TickerMode` combines with its ancestors by logical AND,
/// so wrapping a subtree in `enabled: true` can never un-mute a route the
/// `Overlay` has already muted.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Reports whether any non-opaque route is open on the navigator it observes.
///
/// Register it on the **root** navigator, which is the one `showDialog` and
/// `showModalBottomSheet` push onto by default:
///
/// ```dart
/// final rootModalObserver = ModalRouteObserver();
///
/// GoRouter(
///   observers: [rootModalObserver],   // root navigator
///   routes: [ ... ],
/// );
/// ```
class ModalRouteObserver extends NavigatorObserver {
  /// True while at least one non-opaque route is open.
  final ValueNotifier<bool> isObscured = ValueNotifier<bool>(false);

  int _open = 0;

  /// An opaque route is left to the `Overlay`, which already mutes everything
  /// under it. Only the see-through ones need reporting.
  static bool _isTransparent(Route<dynamic>? route) =>
      route is ModalRoute && !route.opaque;

  void _add(Route<dynamic>? route) {
    if (!_isTransparent(route)) return;
    _open += 1;
    isObscured.value = _open > 0;
  }

  void _remove(Route<dynamic>? route) {
    if (!_isTransparent(route) || _open == 0) return;
    _open -= 1;
    isObscured.value = _open > 0;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    _add(newRoute);
  }

  void dispose() => isObscured.dispose();
}

class PauseWhenHidden extends StatefulWidget {
  const PauseWhenHidden({
    super.key,
    required this.child,
    this.obscured,
    this.pauseWhenInactive = false,
  });

  final Widget child;

  /// Whether a dialog or sheet is open on the root navigator.
  ///
  /// Without it, a root-navigator dialog leaves this subtree ticking: the
  /// screen's own route is still `isCurrent` on its nested navigator, and the
  /// dialog is not opaque, so nothing mutes it.
  final ValueListenable<bool>? obscured;

  /// Whether losing input focus counts as hidden.
  ///
  /// Off by default: on a desktop browser an unfocused window is still fully
  /// visible, so freezing it would read as a bug rather than a saving. Worth
  /// turning on for a phone, where `inactive` really does mean the screen is
  /// on its way out.
  final bool pauseWhenInactive;

  @override
  State<PauseWhenHidden> createState() => _PauseWhenHiddenState();
}

class _PauseWhenHiddenState extends State<PauseWhenHidden> {
  late final AppLifecycleListener _lifecycle;

  bool _foreground = true;

  @override
  void initState() {
    super.initState();

    // lifecycleState is null until the first platform message arrives, which
    // is also what it stays at for the whole of a widget test. Null means
    // there is no reason to think we are hidden, so it counts as foreground.
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;

    // AppLifecycleListener rather than WidgetsBindingObserver: it is the
    // current API (Flutter 3.13+) and it reports the transitions this widget
    // cares about - onHide / onShow - instead of leaving every caller to
    // derive them from raw states. It does assert that transitions are legal,
    // so a test has to walk resumed -> inactive -> hidden -> paused rather
    // than jumping straight to paused.
    _lifecycle = AppLifecycleListener(
      onResume: () => _setForeground(true),
      onShow: () => _setForeground(true),
      onInactive: () {
        if (widget.pauseWhenInactive) _setForeground(false);
      },
      onHide: () => _setForeground(false),
      onPause: () => _setForeground(false),
      onDetach: () => _setForeground(false),
    );

    widget.obscured?.addListener(_onObscuredChanged);
  }

  @override
  void didUpdateWidget(PauseWhenHidden oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscured != widget.obscured) {
      oldWidget.obscured?.removeListener(_onObscuredChanged);
      widget.obscured?.addListener(_onObscuredChanged);
    }
  }

  void _onObscuredChanged() {
    if (mounted) setState(() {});
  }

  void _setForeground(bool value) {
    if (!mounted || _foreground == value) return;
    setState(() => _foreground = value);
  }

  @override
  void dispose() {
    widget.obscured?.removeListener(_onObscuredChanged);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Outside a route entirely - a bare widget test, or a child of the shell
    // rather than of a page - nothing can cover this, so treat it as on top.
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    final behindAModal = widget.obscured?.value ?? false;

    return TickerMode(
      enabled: _foreground && onTop && !behindAModal,
      child: widget.child,
    );
  }
}
