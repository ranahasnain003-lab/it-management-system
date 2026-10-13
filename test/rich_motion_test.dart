/// Tests for the features that exist only at the Rich level.
///
/// Each one checks both halves of the contract: that Rich adds the thing, and
/// that Subtle is left exactly as it was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/motion/press_scale.dart';
import 'package:it_management_system/core/widgets/motion/pulsing_halo.dart';
import 'package:it_management_system/core/widgets/motion/waiting_dots.dart';

Widget _at(AnimationLevel level, Widget child) {
  return MotionScope(
    level: level,
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  group('press and hover', () {
    testWidgets('Rich scales on press; Subtle does not move', (tester) async {
      for (final level in [AnimationLevel.subtle, AnimationLevel.rich]) {
        await tester.pumpWidget(
          _at(
            level,
            PressScale(
              animate: true,
              onTap: () {},
              child: const SizedBox(width: 100, height: 60),
            ),
          ),
        );

        await tester.press(find.byType(PressScale));
        await tester.pump(const Duration(milliseconds: 300));

        final scales = tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .map((w) => w.scale)
            .toList();

        if (level == AnimationLevel.subtle) {
          // Nothing to animate, so the widget is a pass-through.
          expect(scales, isEmpty, reason: 'subtle must not scale');
        } else {
          expect(scales, isNotEmpty, reason: 'rich must respond to a press');
        }

        await tester.pumpAndSettle();
      }
    });

    testWidgets('still calls onTap at every level', (tester) async {
      // The response must never cost the card its function.
      for (final level in AnimationLevel.values) {
        var taps = 0;

        await tester.pumpWidget(
          _at(
            level,
            PressScale(
              animate: level != AnimationLevel.off,
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 60),
            ),
          ),
        );

        await tester.tap(find.byType(PressScale));
        await tester.pumpAndSettle();

        expect(taps, 1, reason: '$level');
      }
    });
  });

  group('the waiting dots wave', () {
    testWidgets('Rich moves the dots vertically; Subtle only dims them', (
      tester,
    ) async {
      for (final level in [AnimationLevel.subtle, AnimationLevel.rich]) {
        await tester.pumpWidget(
          _at(
            level,
            const WaitingDots(animate: true, color: Colors.black),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final moved = find
            .descendant(
              of: find.byType(WaitingDots),
              matching: find.byType(Transform),
            )
            .evaluate()
            .isNotEmpty;

        expect(
          moved,
          level == AnimationLevel.rich,
          reason: 'vertical wave at $level',
        );
      }
    });
  });

  group('the empty-state halo', () {
    testWidgets('breathes at Rich and holds still at Subtle', (tester) async {
      for (final level in [AnimationLevel.subtle, AnimationLevel.rich]) {
        await tester.pumpWidget(
          _at(
            level,
            PulsingHalo(
              animate: true,
              color: Colors.blue,
              child: const Icon(Icons.inbox),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 500));
        final first = tester
            .widgetList<Transform>(
              find.descendant(
                of: find.byType(PulsingHalo),
                matching: find.byType(Transform),
              ),
            )
            .first
            .transform
            .entry(0, 0);

        await tester.pump(const Duration(milliseconds: 700));
        final second = tester
            .widgetList<Transform>(
              find.descendant(
                of: find.byType(PulsingHalo),
                matching: find.byType(Transform),
              ),
            )
            .first
            .transform
            .entry(0, 0);

        if (level == AnimationLevel.rich) {
          expect(first, isNot(second), reason: 'rich halo must breathe');
        } else {
          expect(first, second, reason: 'subtle halo must hold still');
        }
      }
    });

    testWidgets('settles when motion is off', (tester) async {
      await tester.pumpWidget(
        _at(
          AnimationLevel.off,
          PulsingHalo(
            animate: false,
            color: Colors.blue,
            child: const Icon(Icons.inbox),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.inbox), findsOneWidget);
    });
  });

  group('the background', () {
    test('Rich draws more blobs, further, with shifting colour', () {
      // The four numbers that make the background read as alive rather than
      // as a wash.
      expect(AppMotion.rich.blobCount, 4);
      expect(AppMotion.subtle.blobCount, 3);
      expect(AppMotion.rich.blobDrift, greaterThan(AppMotion.subtle.blobDrift));
      expect(AppMotion.rich.colourShiftEnabled, isTrue);
      expect(AppMotion.subtle.colourShiftEnabled, isFalse);
    });
  });
}
