/// Tests for the three animation levels.
///
/// The contract these lock in: Off means nothing moves, Subtle keeps the
/// original tuning exactly, Rich is measurably stronger, and the device's own
/// reduce-motion setting beats all three.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/animated_gradient_background.dart';
import 'package:it_management_system/core/widgets/motion/entrance.dart';

Widget _probe({
  required AnimationLevel level,
  bool disableAnimations = false,
  required void Function(BuildContext) read,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MotionScope(
      level: level,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            read(context);
            return const SizedBox();
          },
        ),
      ),
    ),
  );
}

void main() {
  group('choosing a level', () {
    testWidgets('Off disables motion entirely', (tester) async {
      late bool enabled;
      await tester.pumpWidget(
        _probe(
          level: AnimationLevel.off,
          read: (c) => enabled = AppMotion.enabled(c),
        ),
      );
      expect(enabled, isFalse);
    });

    testWidgets('Subtle and Rich both enable motion', (tester) async {
      for (final level in [AnimationLevel.subtle, AnimationLevel.rich]) {
        late bool enabled;
        await tester.pumpWidget(
          _probe(level: level, read: (c) => enabled = AppMotion.enabled(c)),
        );
        expect(enabled, isTrue, reason: '$level');
      }
    });

    testWidgets('each level hands out its own values', (tester) async {
      late AppMotion subtle;
      late AppMotion rich;

      await tester.pumpWidget(
        _probe(
          level: AnimationLevel.subtle,
          read: (c) => subtle = AppMotion.of(c),
        ),
      );
      await tester.pumpWidget(
        _probe(level: AnimationLevel.rich, read: (c) => rich = AppMotion.of(c)),
      );

      expect(subtle.level, AnimationLevel.subtle);
      expect(rich.level, AnimationLevel.rich);
    });

    testWidgets('no scope at all means Rich, the default', (tester) async {
      // A leaf widget must work with nothing above it, which is how several
      // widgets are built in their own tests.
      late AnimationLevel level;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              level = AppMotion.levelOf(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(level, AnimationLevel.rich);
    });

    testWidgets('the device setting beats every level', (tester) async {
      // Accessibility is not a preference the app may overrule.
      for (final level in AnimationLevel.values) {
        late AnimationLevel resolved;
        await tester.pumpWidget(
          _probe(
            level: level,
            disableAnimations: true,
            read: (c) => resolved = AppMotion.levelOf(c),
          ),
        );
        expect(resolved, AnimationLevel.off, reason: '$level');
      }
    });
  });

  group('Subtle is unchanged', () {
    test('keeps exactly the values it had before levels existed', () {
      // The promise made when the levels were introduced: choosing Subtle
      // gives back the original app, value for value.
      const m = AppMotion.subtle;

      expect(m.screen, const Duration(milliseconds: 280));
      expect(m.countUp, const Duration(milliseconds: 600));
      expect(m.success, const Duration(milliseconds: 700));
      expect(m.backgroundLoop, const Duration(seconds: 24));
      expect(m.staggerLarge, const Duration(milliseconds: 80));
      expect(m.staggerCard, const Duration(milliseconds: 50));
      expect(m.slideLarge, 12);
      expect(m.slideSmall, 8);
      expect(m.floatDistance, 3);
      expect(m.blobOpacityLight, 0.10);
      expect(m.blobOpacityDark, 0.15);
      expect(m.blobCount, 3);
      // No scaling, no wave, no overshoot at this level.
      expect(m.entranceScale, 1.0);
      expect(m.pulseScale, 1.0);
      expect(m.pressScale, 1.0);
      expect(m.dotWave, 0);
      expect(m.blobColourShift, 0);
      expect(m.cardEntrance, Curves.easeOutCubic);
    });
  });

  group('Rich is genuinely stronger', () {
    test('moves further, faster and more visibly', () {
      const s = AppMotion.subtle;
      const r = AppMotion.rich;

      // If any of these were equal, choosing Rich would change nothing.
      expect(r.slideLarge, greaterThan(s.slideLarge));
      expect(r.slideSmall, greaterThan(s.slideSmall));
      expect(r.floatDistance, greaterThan(s.floatDistance));
      expect(r.blobOpacityLight, greaterThan(s.blobOpacityLight));
      expect(r.blobOpacityDark, greaterThan(s.blobOpacityDark));
      expect(r.blobDrift, greaterThan(s.blobDrift));
      expect(r.blobCount, greaterThan(s.blobCount));
      expect(r.backgroundLoop, lessThan(s.backgroundLoop));
      expect(r.entranceScale, lessThan(1.0));
      expect(r.pressScale, lessThan(1.0));
      expect(r.dotWave, greaterThan(0));
      expect(r.blobColourShift, greaterThan(0));
    });

    test('stays inside the ranges the design asks for', () {
      const r = AppMotion.rich;

      expect(r.blobOpacityLight, inInclusiveRange(0.25, 0.35));
      expect(r.blobOpacityDark, inInclusiveRange(0.20, 0.30));
      expect(r.backgroundLoop.inSeconds, inInclusiveRange(10, 14));
      expect(r.blobDrift, inInclusiveRange(0.20, 0.30));
      expect(r.blobCount, inInclusiveRange(3, 4));
      expect(r.screen.inMilliseconds, inInclusiveRange(300, 350));
      expect(r.staggerCard.inMilliseconds, inInclusiveRange(60, 80));
      expect(r.countUp.inMilliseconds, inInclusiveRange(850, 950));
      expect(r.success.inMilliseconds, inInclusiveRange(850, 950));
      expect(r.slideLarge, 24);
      expect(r.floatDistance, 6);
      // Less blur than subtle: more defined blobs, and a cheaper frame.
      expect(r.blobBlur, lessThan(AppMotion.subtle.blobBlur));
    });

    test('overshoot exists only for the stat cards', () {
      // The single exception to the no-bounce rule, and it is named rather
      // than written at a call site so there is exactly one place to look.
      expect(AppMotion.rich.cardEntrance, Curves.easeOutBack);

      for (final m in [AppMotion.subtle, AppMotion.rich]) {
        expect(m.enter, Curves.easeOutCubic);
        expect(m.exit, Curves.easeInCubic);
        expect(m.move, Curves.easeInOutCubic);
      }
    });
  });

  group('every level still settles', () {
    testWidgets('nothing loops when the level is Off', (tester) async {
      // The guarantee that keeps pumpAndSettle usable across the suite.
      for (final widget in [
        const AnimatedGradientBackground(animate: false, child: Text('x')),
        const EntranceFadeSlide(animate: false, child: Text('x')),
      ]) {
        await tester.pumpWidget(
          MotionScope(
            level: AnimationLevel.off,
            child: MaterialApp(home: Scaffold(body: widget)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('x'), findsOneWidget);
      }
    });
  });
}
