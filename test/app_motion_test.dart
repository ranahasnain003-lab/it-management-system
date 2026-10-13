/// Tests for the motion foundation.
///
/// The two that matter most are the ones proving animations stop completely:
/// when the platform asks for reduced motion, and when the Settings switch is
/// off. "Stop" means render the finished state, not run faster - a widget that
/// merely shortened its animation would still spin a controller forever and
/// would still hang `pumpAndSettle`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/animated_gradient_background.dart';

/// Builds [child] with a chosen `disableAnimations`.
Widget _app(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('AppMotion.enabled', () {
    testWidgets('off when the platform asks for reduced motion', (tester) async {
      late bool enabled;

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              enabled = AppMotion.enabled(context, enabledInSettings: true);
              return const SizedBox();
            },
          ),
          disableAnimations: true,
        ),
      );

      expect(enabled, isFalse);
    });

    testWidgets('off when the Settings switch is off', (tester) async {
      late bool enabled;

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              enabled = AppMotion.enabled(context, enabledInSettings: false);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(enabled, isFalse);
    });

    testWidgets('the platform wins even when Settings says on', (tester) async {
      // Accessibility is not a preference the app may overrule.
      late bool enabled;

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              enabled = AppMotion.enabled(context, enabledInSettings: true);
              return const SizedBox();
            },
          ),
          disableAnimations: true,
        ),
      );

      expect(enabled, isFalse);
    });

    testWidgets('on only when both agree', (tester) async {
      late bool enabled;

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              enabled = AppMotion.enabled(context, enabledInSettings: true);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(enabled, isTrue);
    });
  });

  group('the motion specification', () {
    test('never uses a linear, bouncing or elastic curve', () {
      // The whole tone of the app depends on this. A linear curve reads as
      // cheap; bounce and elastic read as playful, which this is not.
      for (final curve in [AppMotion.enter, AppMotion.exit, AppMotion.move]) {
        expect(curve, isNot(Curves.linear));
        expect(curve, isNot(Curves.bounceIn));
        expect(curve, isNot(Curves.bounceOut));
        expect(curve, isNot(Curves.elasticIn));
        expect(curve, isNot(Curves.elasticOut));
      }
    });

    test('durations sit inside the ranges the design calls for', () {
      expect(AppMotion.micro.inMilliseconds, inInclusiveRange(150, 250));
      expect(AppMotion.short.inMilliseconds, inInclusiveRange(150, 250));
      expect(AppMotion.screen.inMilliseconds, inInclusiveRange(250, 350));
      expect(AppMotion.countUp.inMilliseconds, inInclusiveRange(500, 700));
      expect(AppMotion.success.inMilliseconds, inInclusiveRange(600, 800));
      expect(AppMotion.shake.inMilliseconds, 300);
      // Slow enough that it reads as ambient rather than as something moving.
      expect(AppMotion.backgroundLoop.inSeconds, inInclusiveRange(20, 30));
      expect(AppMotion.staggerCard.inMilliseconds, inInclusiveRange(40, 60));
    });

    test('background blobs stay faint in both themes', () {
      expect(AppMotion.blobOpacityLight, inInclusiveRange(0.08, 0.15));
      expect(AppMotion.blobOpacityDark, inInclusiveRange(0.08, 0.15));
    });

    test('movement distances stay small', () {
      expect(AppMotion.slideLarge, 12);
      expect(AppMotion.slideSmall, 8);
      expect(AppMotion.floatDistance, 3);
    });
  });

  group('AnimatedGradientBackground', () {
    testWidgets('runs no controller when animation is off', (tester) async {
      // The real proof that "off" means off: if a controller were still
      // repeating, pumpAndSettle would never return.
      await tester.pumpWidget(
        _app(
          const AnimatedGradientBackground(
            animate: false,
            child: Text('content'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('still paints its background when animation is off', (tester) async {
      // Off means a still frame, not a blank screen.
      await tester.pumpWidget(
        _app(
          const AnimatedGradientBackground(
            animate: false,
            child: Text('content'),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('animates without rebuilding the content above it', (tester) async {
      // The point of driving the painter through `repaint:`. The children here
      // are Firestore-backed cards in the real app, and rebuilding them at
      // 60fps would be ruinous.
      var contentBuilds = 0;

      await tester.pumpWidget(
        _app(
          AnimatedGradientBackground(
            animate: true,
            child: Builder(
              builder: (context) {
                contentBuilds++;
                return const Text('content');
              },
            ),
          ),
        ),
      );

      final afterFirstFrame = contentBuilds;

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(contentBuilds, afterFirstFrame);
    });

    testWidgets('isolates its repaints behind a boundary', (tester) async {
      await tester.pumpWidget(
        _app(
          const AnimatedGradientBackground(
            animate: true,
            child: Text('content'),
          ),
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

    testWidgets('stops cleanly when switched from animating to still', (tester) async {
      await tester.pumpWidget(
        _app(
          const AnimatedGradientBackground(animate: true, child: Text('c')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pumpWidget(
        _app(
          const AnimatedGradientBackground(animate: false, child: Text('c')),
        ),
      );

      // Would time out if the controller were still repeating.
      await tester.pumpAndSettle();
      expect(find.text('c'), findsOneWidget);
    });
  });
}
