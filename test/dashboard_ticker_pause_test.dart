/// Proves that the dashboard's looping animations actually stop ticking when
/// the dashboard is not being looked at.
///
/// "Proves" is the point, so it is worth saying which assertion carries the
/// weight and why the obvious ones do not:
///
///   * `AnimationController.isAnimating` is **useless here**. It is
///     `_ticker != null && _ticker!.isActive`, and `Ticker.isActive` is
///     `_future != null`. Muting a ticker does not clear that future, so a
///     fully muted controller still reports `isAnimating == true`. Verified,
///     not assumed.
///   * `tester.binding.transientCallbackCount` is the real proof for
///     muting. `Ticker.muted = true` calls `unscheduleTick()`, which removes
///     the ticker's entry from `SchedulerBinding._transientCallbacks`, and
///     that map's length is exactly `transientCallbackCount`. Zero means
///     nothing in the whole binding has asked for another frame.
///   * `transientCallbackCount` is **not** proof for the backgrounded case.
///     `scheduleFrameCallback` registers the callback whatever
///     `framesEnabled` says, so the count stays at 1 while the app is
///     paused. What changes there is `hasScheduledFrame`, and the honest
///     assertion is that the animated value stops moving.
///   * `pumpAndSettle` returning at all is a strong, cheap proof: on a
///     `repeat()`ing animation it throws "pumpAndSettle timed out", so a
///     `pumpAndSettle` that completes means every looping ticker in the tree
///     has stopped.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:it_management_system/core/widgets/motion/pause_when_hidden.dart';

// =============================================================================
// A STAND-IN FOR THE DASHBOARD'S LOOPING WIDGETS
// =============================================================================
//
// Shaped like AnimatedGradientBackground / GentleFloat / Shimmer: one
// controller, repeat() forever, no end. Used instead of DashboardScreen
// itself, which needs Firebase and six providers; the behaviour under test is
// the ticker's, not the dashboard's data.

class LoopingBanner extends StatefulWidget {
  const LoopingBanner({super.key});

  @override
  State<LoopingBanner> createState() => LoopingBannerState();
}

class LoopingBannerState extends State<LoopingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  /// Counts painted frames, so a test can tell "not rebuilding" from
  /// "rebuilding with the same value".
  int frames = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        frames++;
        return Opacity(
          opacity: 0.2 + controller.value * 0.6,
          child: const SizedBox(width: 100, height: 100),
        );
      },
    );
  }
}

// =============================================================================
// HELPERS
// =============================================================================

/// A covered route is offstage inside `Overlay`'s `_Theater`, and every
/// default finder has `skipOffstage: true`. Without this the state lookup
/// fails with "Bad state: No element" the moment the route is covered, which
/// looks like a disposal and is not one.
final Finder bannerFinder = find.byType(LoopingBanner, skipOffstage: false);

LoopingBannerState banner(WidgetTester tester) =>
    tester.state<LoopingBannerState>(bannerFinder);

/// Asserts that nothing in the binding has a frame callback registered.
void expectNoTickersScheduled(WidgetTester tester, {required String when}) {
  expect(
    tester.binding.transientCallbackCount,
    0,
    reason:
        'a ticker is still scheduled for the next frame $when - '
        'something in the tree is still animating',
  );
}

/// Advances [total] of animation time in [step]s without ever settling.
///
/// This is the pattern for a screen that holds a `repeat()`ing animation:
/// `pumpAndSettle` would throw, and a single huge `pump` would jump the
/// controller straight past every intermediate value.
Future<void> pumpFrames(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
  }
}

/// Runs [body] over [total] and returns true if the animated value never
/// moved. Frame-identity, without the cost or flake of a golden.
Future<bool> frozenThroughout(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final start = banner(tester).controller.value;
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
    if (banner(tester).controller.value != start) return false;
  }
  return true;
}

// =============================================================================
// THE ROUTER UNDER TEST
// =============================================================================
//
// The same shape as AppRouter._page and WebRouter.page: a ShellRoute whose
// pages are CustomTransitionPage, which defaults to opaque: true and
// maintainState: true - the two flags the Overlay's muting depends on.

CustomTransitionPage<void> _page(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
    child: child,
  );
}

/// Registered on the ROOT navigator, which is the one showDialog pushes onto.
late ModalRouteObserver rootModals;

GoRouter _router() {
  rootModals = ModalRouteObserver();
  return GoRouter(
    initialLocation: '/dashboard',
    observers: [rootModals],
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(body: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _page(
              state,
              PauseWhenHidden(
                obscured: rootModals.isObscured,
                child: const LoopingBanner(),
              ),
            ),
          ),
          GoRoute(
            path: '/assets',
            pageBuilder: (context, state) => _page(state, const Text('assets')),
          ),
        ],
      ),
    ],
  );
}

void main() {
  // ===========================================================================
  // THE BASELINE: IT REALLY IS LOOPING
  // ===========================================================================
  //
  // Every test below asserts an absence. Without this one, a mistake that
  // stopped the animation from ever starting would make all of them pass.

  group('baseline', () {
    testWidgets('the banner loops forever while it is on top', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      expect(tester.binding.transientCallbackCount, 1);
      expect(banner(tester).frames, greaterThan(3));
      expect(await frozenThroughout(tester), isFalse);
    });

    testWidgets('pumpAndSettle cannot settle it', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      // pumpAndSettle's timeout surfaces as a framework error rather than a
      // rejected future, so it has to be caught here and then cleared with
      // takeException, or the test is failed by the pending exception.
      var timedOut = false;
      try {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 2),
        );
      } catch (_) {
        timedOut = true;
      }
      tester.takeException();

      expect(
        timedOut,
        isTrue,
        reason: 'a repeat()ing animation must never settle',
      );
    });
  });

  // ===========================================================================
  // ANOTHER ROUTE ON TOP
  // ===========================================================================

  group('a route on top', () {
    testWidgets('push: the dashboard is kept alive but stops ticking', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      router.push('/assets');

      // This completing at all is the first proof: a looping ticker would
      // make it throw.
      await tester.pumpAndSettle();

      // Kept in the tree - this is a cover, not a disposal.
      expect(bannerFinder, findsOneWidget);
      expect(find.byType(LoopingBanner), findsNothing); // offstage

      expectNoTickersScheduled(tester, when: 'while covered by /assets');
      expect(TickerMode.valuesOf(tester.element(bannerFinder)).enabled, isFalse);

      // And isAnimating is still true, which is why it is not the assertion.
      expect(banner(tester).controller.isAnimating, isTrue);

      final framesWhenCovered = banner(tester).frames;
      expect(await frozenThroughout(tester), isTrue);
      expect(banner(tester).frames, framesWhenCovered);
    });

    testWidgets('pop: it starts again', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      router.push('/assets');
      await tester.pumpAndSettle();
      expectNoTickersScheduled(tester, when: 'while covered');

      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(await frozenThroughout(tester), isFalse);
    });

    testWidgets('go: the dashboard is disposed outright', (tester) async {
      // What the web shell does. web_shell.dart calls context.go(path), which
      // replaces the page rather than stacking on it, so there is no ticker
      // left to mute.
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      router.go('/assets');
      await tester.pumpAndSettle();

      expect(bannerFinder, findsNothing);
      expectNoTickersScheduled(tester, when: 'after go() replaced the page');
    });
  });

  // ===========================================================================
  // A DIALOG ON TOP - THE CASE FLUTTER DOES *NOT* HANDLE
  // ===========================================================================

  group('a non-opaque route on top', () {
    testWidgets('PauseWhenHidden stops the dashboard behind a dialog', (
      tester,
    ) async {
      // PopupRoute.opaque is false, so Overlay never mutes anything below a
      // dialog. Without PauseWhenHidden this test fails: pumpAndSettle throws
      // and transientCallbackCount stays at 1.
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      final context = tester.element(bannerFinder);
      showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(content: Text('a dialog')),
      );

      await tester.pumpAndSettle();

      expect(find.text('a dialog'), findsOneWidget);
      expectNoTickersScheduled(tester, when: 'while a dialog is open');
      expect(await frozenThroughout(tester), isTrue);
    });
  });

  // ===========================================================================
  // THE APP IN THE BACKGROUND
  // ===========================================================================

  group('the app in the background', () {
    testWidgets('hidden and paused freeze every animation', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      // The chain has to be walked. AppLifecycleListener asserts that
      // transitions are legal, and resumed -> paused directly throws
      // "Invalid state transition from AppLifecycleState.resumed to
      // AppLifecycleState.paused".
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }

      expect(SchedulerBinding.instance.framesEnabled, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(await frozenThroughout(tester), isTrue);

      // Deliberately NOT asserted: transientCallbackCount. The ticker's
      // callback stays registered while the app is paused, because
      // scheduleFrameCallback adds it whatever framesEnabled says. Asserting
      // 0 here would fail even though the animation is genuinely frozen.
    });

    testWidgets('coming back to the foreground resumes it', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      expect(await frozenThroughout(tester), isTrue);

      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }

      // Two pumps: TickerMode is re-enabled during the build phase, which is
      // after the transient-callback phase of that same frame, so the ticker
      // can only schedule itself for the frame after.
      await tester.pump(const Duration(milliseconds: 100));
      expect(await frozenThroughout(tester), isFalse);
    });

    testWidgets('inactive alone does not freeze a visible window', (
      tester,
    ) async {
      // A desktop browser that lost focus is still fully visible. Freezing it
      // would be a visible bug, so pauseWhenInactive defaults to false and
      // framesEnabled stays true for inactive.
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpFrames(tester, total: const Duration(milliseconds: 500));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(SchedulerBinding.instance.framesEnabled, isTrue);
      expect(await frozenThroughout(tester), isFalse);
    });
  });
}
