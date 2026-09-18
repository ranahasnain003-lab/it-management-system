import 'package:flutter/material.dart';

/// Tracks everything that covers the screen above the assistant's button, so
/// the button can step out of the way.
///
/// The assistant lives in the router's signed-in shell: above the screens, but
/// below the root navigator. That places dialogs above it automatically, but
/// leaves two cases it has to be told about:
///
///  * bottom sheets and popup menus, which open on the shell's own navigator
///    and are therefore drawn *below* the shell overlay - hence the
///    [NavigatorObserver] half of this class;
///  * the navigation drawer, which is not a route at all but part of the
///    Scaffold inside the page, so no observer can see it. The screen that
///    hosts a drawer reports it through [setDrawerOpen].
///
/// It lives in its own file so a screen can report its drawer without
/// importing the whole assistant panel.
class AssistantModalObserver extends NavigatorObserver {
  /// Number of modal routes currently open on the observed navigator.
  final ValueNotifier<int> openModals = ValueNotifier<int>(0);

  /// Whether a navigation drawer is currently open.
  final ValueNotifier<bool> drawerOpen = ValueNotifier<bool>(false);

  /// Fires whenever either source changes. [isObscured] reads the result.
  late final Listenable obscured = Listenable.merge([openModals, drawerOpen]);

  /// True while anything is covering the screen, so the button should go.
  bool get isObscured => openModals.value > 0 || drawerOpen.value;

  /// Reported by a screen whose Scaffold has a drawer, from `onDrawerChanged`.
  void setDrawerOpen(bool open) => drawerOpen.value = open;

  static bool _isModal(Route<dynamic>? route) => route is PopupRoute;

  void _add(Route<dynamic>? route) {
    if (_isModal(route)) openModals.value = openModals.value + 1;
  }

  void _remove(Route<dynamic>? route) {
    if (_isModal(route) && openModals.value > 0) {
      openModals.value = openModals.value - 1;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    _add(newRoute);
  }
}

/// The single observer shared by the router's assistant shell, the overlay and
/// the screen that owns the navigation drawer.
final AssistantModalObserver assistantModalObserver = AssistantModalObserver();
