/// Tests for the dashboard guarantees that are easy to lose:
///
///   1. the stat cards do not rebuild on background animation frames,
///   2. a shared entrance widget does not replay when its content changes,
///   3. the dashboard sequence replays when the screen is opened again but
///      NOT when Firestore delivers new figures, and
///   4. each level means what it says.
///
/// They are tested through the widgets that carry the behaviour rather than
/// through DashboardScreen itself, which needs Firebase and six providers.
/// The dashboard rendered end to end, with pixels compared, is
/// test/dashboard_motion_frames_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/dashboard/widgets/dashboard_motion.dart';
import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/animated_gradient_background.dart';
import 'package:it_management_system/core/widgets/motion/count_up.dart';
import 'package:it_management_system/core/widgets/motion/entrance.dart';
import 'package:it_management_system/core/widgets/motion/shimmer.dart';

Widget _app(Widget child, {bool animations = true}) {
  return MotionScope(
    level: animations ? AnimationLevel.rich : AnimationLevel.off,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  // ===========================================================================
  // STAT CARDS DO NOT REBUILD ON ANIMATION FRAMES
  // ===========================================================================

  group('the background does not drive the cards', () {
    testWidgets('stat cards do not rebuild while the background animates', (
      tester,
    ) async {
      // The guarantee that matters most for performance. These cards are
      // Firestore-backed; rebuilding eight of them at 60fps behind a
      // decorative background would cost far more than the background does.
      var cardBuilds = 0;

      await tester.pumpWidget(
        _app(
          AnimatedGradientBackground(
            animate: true,
            child: Column(
              children: [
                for (var i = 0; i < 8; i++)
                  Builder(
                    builder: (context) {
                      cardBuilds++;
                      return SizedBox(height: 10, child: Text('card $i'));
                    },
                  ),
              ],
            ),
          ),
        ),
      );

      final afterFirstFrame = cardBuilds;
      expect(afterFirstFrame, 8);

      // Two seconds of background animation.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(cardBuilds, afterFirstFrame);
    });

    testWidgets('the background repaints behind its own boundary', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const AnimatedGradientBackground(animate: true, child: Text('cards')),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(AnimatedGradientBackground),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });

  // ===========================================================================
  // ENTRANCEFADESLIDE DOES NOT REPLAY ON NEW CONTENT
  //
  // This is the shared widget the rest of the app uses. The dashboard no
  // longer uses it - it has its own sequence, tested below - but every other
  // screen does, and this contract is theirs.
  // ===========================================================================

  group('a shared entrance does not replay', () {
    testWidgets('a data update does not replay it', (tester) async {
      // Standing in for Firestore delivering new totals: the card rebuilds
      // with new content, and must not fade in again.
      Widget card(String value) =>
          _app(EntranceFadeSlide(animate: true, child: Text(value)));

      await tester.pumpWidget(card('12'));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);

      await tester.pumpWidget(card('57'));
      await tester.pump();

      // Still fully visible: no second fade.
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
      expect(find.text('57'), findsOneWidget);
    });

    testWidgets('the stagger grows with the card index', (tester) async {
      // Card 0 arrives first, card 3 last. If they shared a delay the grid
      // would appear as a block instead of being led across.
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              for (var i = 0; i < 4; i++)
                EntranceFadeSlide(
                  animate: true,
                  delay: AppMotion.subtle.staggerCard * i,
                  child: SizedBox(height: 10, child: Text('card $i')),
                ),
            ],
          ),
        ),
      );

      // After the first card's delay but before the last one's.
      await tester.pump(const Duration(milliseconds: 60));

      final opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();

      expect(opacities.first, greaterThan(opacities.last));

      await tester.pumpAndSettle();
      for (final value
          in tester
              .widgetList<Opacity>(find.byType(Opacity))
              .map((o) => o.opacity)) {
        expect(value, 1.0);
      }
    });
  });

  // ===========================================================================
  // THE ONE-TIME COUNT-UP
  // ===========================================================================

  group('stat numbers', () {
    testWidgets('count up once, then land on the real figure', (tester) async {
      await tester.pumpWidget(
        _app(const CountUpText(value: 434, animate: true, style: TextStyle())),
      );

      // Partway through it shows something smaller than the target.
      await tester.pump(const Duration(milliseconds: 200));
      final midway = int.parse((tester.widget<Text>(find.byType(Text)).data)!);
      expect(midway, lessThan(434));

      await tester.pumpAndSettle();
      expect(find.text('434'), findsOneWidget);
    });

    testWidgets('a later value appears at once, without counting', (
      tester,
    ) async {
      // The rule this protects: a figure people are reading must never be
      // mid-animation. Only the very first sight of it counts up.
      await tester.pumpWidget(
        _app(const CountUpText(value: 100, animate: true, style: TextStyle())),
      );
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);

      await tester.pumpWidget(
        _app(const CountUpText(value: 250, animate: true, style: TextStyle())),
      );
      await tester.pump();

      // Immediately 250 - no intermediate figure was ever shown.
      expect(find.text('250'), findsOneWidget);
    });

    testWidgets('shows the figure straight away when motion is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const CountUpText(value: 434, animate: false, style: TextStyle())),
      );

      await tester.pumpAndSettle();
      expect(find.text('434'), findsOneWidget);
    });
  });

  // ===========================================================================
  // LOADING SKELETONS
  // ===========================================================================

  group('loading skeletons', () {
    testWidgets('shimmer settles completely when motion is off', (
      tester,
    ) async {
      // Would hang if the shimmer kept looping, which is exactly what made
      // skeleton screens untestable before.
      await tester.pumpWidget(
        _app(const Shimmer(animate: false, child: Text('skeleton'))),
      );

      await tester.pumpAndSettle();
      expect(find.text('skeleton'), findsOneWidget);
    });

    testWidgets('the placeholder still shows while shimmering', (tester) async {
      await tester.pumpWidget(
        _app(const Shimmer(animate: true, child: Text('skeleton'))),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('skeleton'), findsOneWidget);
    });
  });
  _dashboardSequenceTests();
}

// =============================================================================
// THE DASHBOARD SEQUENCE
// =============================================================================
//
// The policy that changed in this round: the opening sequence now plays every
// time the dashboard is opened rather than once per app run, and it still must
// not replay when Firestore delivers new figures. Both come from the same
// design - one controller for the whole screen, read through an
// InheritedWidget - so both are tested here against that controller.

/// The entrance value [Staged] would be reading, as the tree sees it.
double _entranceValue(WidgetTester tester) {
  final context = tester.element(find.byKey(const ValueKey('probe')));

  return DashboardMotion.of(context).entrance.value;
}

bool _loops(WidgetTester tester) {
  final context = tester.element(find.byKey(const ValueKey('probe')));

  return DashboardMotion.of(context).loops;
}

Widget _host(String content, {required AnimationLevel level}) {
  return MotionScope(
    level: level,
    child: MaterialApp(
      home: Scaffold(
        body: DashboardMotionHost(
          child: Column(
            children: [
              const SizedBox(key: ValueKey('probe'), height: 1),
              // Stands in for a Firestore-backed card: new content, same
              // position in the tree.
              Staged(slot: DashboardStage.hero, child: Text(content)),
            ],
          ),
        ),
      ),
    ),
  );
}

void _dashboardSequenceTests() {
  group('the dashboard sequence', () {
    testWidgets('runs from zero when the screen is mounted', (tester) async {
      await tester.pumpWidget(_host('12', level: AnimationLevel.rich));

      expect(_entranceValue(tester), 0.0);

      await tester.pump(const Duration(milliseconds: 700));
      final midway = _entranceValue(tester);

      expect(midway, greaterThan(0.0));
      expect(midway, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 900));
      expect(_entranceValue(tester), 1.0);
    });

    testWidgets('a Firestore update does not restart it', (tester) async {
      // The hazard this whole design exists to remove. The old screen latched
      // the entrance with a flag, and any rebuild that recreated the card's
      // subtree - a notice appearing above the grid, a loading state swapping
      // out - started it again, so the figures blinked and re-rolled while
      // somebody was reading them.
      await tester.pumpWidget(_host('12', level: AnimationLevel.rich));
      await tester.pump(const Duration(milliseconds: 1600));

      expect(_entranceValue(tester), 1.0);
      expect(find.text('12'), findsOneWidget);

      // New totals arrive.
      await tester.pumpWidget(_host('57', level: AnimationLevel.rich));
      await tester.pump();

      expect(find.text('57'), findsOneWidget);
      expect(
        _entranceValue(tester),
        1.0,
        reason: 'New data replayed the opening sequence.',
      );
    });

    testWidgets('it is finished and still when motion is off', (tester) async {
      await tester.pumpWidget(_host('12', level: AnimationLevel.off));

      // No controller at all, so everything below renders in its settled
      // state and pumpAndSettle stays usable.
      expect(_entranceValue(tester), 1.0);
      await tester.pumpAndSettle();
      expect(_entranceValue(tester), 1.0);
    });

    testWidgets('loops run at rich and not at subtle', (tester) async {
      await tester.pumpWidget(_host('12', level: AnimationLevel.rich));
      expect(_loops(tester), isTrue);

      await tester.pumpWidget(_host('12', level: AnimationLevel.subtle));
      await tester.pump();
      expect(
        _loops(tester),
        isFalse,
        reason: 'Subtle keeps the opening sequence and drops the loops.',
      );

      await tester.pumpWidget(_host('12', level: AnimationLevel.off));
      await tester.pump();
      expect(_loops(tester), isFalse);
    });

    testWidgets('subtle still opens', (tester) async {
      await tester.pumpWidget(_host('12', level: AnimationLevel.subtle));

      expect(_entranceValue(tester), 0.0);

      await tester.pump(const Duration(milliseconds: 500));
      expect(_entranceValue(tester), greaterThan(0.0));

      await tester.pumpAndSettle();
      expect(_entranceValue(tester), 1.0);
    });

    testWidgets('a card rebuilt after the sequence adds no animation work', (
      tester,
    ) async {
      // The case that matters for a screen fed by live streams. Once the
      // sequence is over, a card rebuilt by a Firestore tick must come back as
      // its plain self - no AnimatedBuilder, no listener on a controller that
      // will never fire again - or the cost of the entrance would be paid
      // forever by every card on the screen.
      await tester.pumpWidget(_host('12', level: AnimationLevel.rich));
      await tester.pump(const Duration(milliseconds: 1600));

      expect(_entranceValue(tester), 1.0);

      // New totals arrive, which rebuilds the Staged subtree.
      await tester.pumpWidget(_host('57', level: AnimationLevel.rich));
      await tester.pump();

      expect(find.text('57'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Staged),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
    });
  });
}
