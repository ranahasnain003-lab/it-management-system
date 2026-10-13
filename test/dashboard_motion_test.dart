/// Tests for the two dashboard guarantees that are easy to lose:
///
///   1. the stat cards do not rebuild on background animation frames, and
///   2. the entrance plays once per session, not on every refresh.
///
/// Both are tested through the widgets that carry the behaviour rather than
/// through DashboardScreen itself, which needs Firebase and six providers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  // THE ENTRANCE PLAYS ONCE
  // ===========================================================================

  group('the entrance plays once', () {
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
}
