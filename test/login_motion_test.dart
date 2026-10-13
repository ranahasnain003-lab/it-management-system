/// Tests for the two motion pieces the sign-in screen introduces.
///
/// They are tested here rather than through LoginScreen itself because the
/// screen needs Firebase and a live AuthProvider; the behaviour that can
/// actually go wrong - playing twice, not playing at all, never settling -
/// lives in these two widgets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/motion/entrance.dart';
import 'package:it_management_system/core/widgets/motion/shake.dart';

Widget _app(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// The horizontal offset a ShakeOnSignal is currently applying.
double _shakeOffset(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(ShakeOnSignal),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.getTranslation().x;
}

void main() {
  group('EntranceFadeSlide', () {
    testWidgets('renders the finished state at once when animation is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const EntranceFadeSlide(animate: false, child: Text('card'))),
      );

      // No controller exists, so there is nothing to settle and nothing to
      // fade: the content is simply there, at full opacity.
      await tester.pumpAndSettle();
      expect(find.text('card'), findsOneWidget);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('starts invisible and below, then settles', (tester) async {
      await tester.pumpWidget(
        _app(const EntranceFadeSlide(animate: true, child: Text('card'))),
      );

      final opacityAtStart = tester
          .widget<Opacity>(find.byType(Opacity))
          .opacity;
      expect(opacityAtStart, lessThan(0.2));

      await tester.pumpAndSettle();

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });

    testWidgets('honours its delay, which is how the stagger works', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          EntranceFadeSlide(
            animate: true,
            delay: AppMotion.subtle.staggerLarge,
            child: const Text('card'),
          ),
        ),
      );

      // Still waiting: the delay has not elapsed, so nothing has moved.
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.0);

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });

    testWidgets('does not replay when the parent rebuilds', (tester) async {
      // A rebuild is not an arrival. If this replayed, every Firestore tick
      // behind the screen would fade the card in again.
      await tester.pumpWidget(
        _app(const EntranceFadeSlide(animate: true, child: Text('card'))),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(const EntranceFadeSlide(animate: true, child: Text('card'))),
      );
      await tester.pump();

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });

    testWidgets('survives being disposed during its delay', (tester) async {
      await tester.pumpWidget(
        _app(
          const EntranceFadeSlide(
            animate: true,
            delay: Duration(milliseconds: 200),
            child: Text('card'),
          ),
        ),
      );

      // Gone before the delay fires; the pending callback must not touch a
      // disposed controller.
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });

  group('ShakeOnSignal', () {
    testWidgets('stays still when animation is off', (tester) async {
      await tester.pumpWidget(
        _app(
          const ShakeOnSignal(animate: false, signal: 0, child: Text('card')),
        ),
      );

      await tester.pumpWidget(
        _app(
          const ShakeOnSignal(animate: false, signal: 1, child: Text('card')),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ShakeOnSignal),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });

    testWidgets('does not shake on first build', (tester) async {
      // Opening the screen is not a refusal.
      await tester.pumpWidget(
        _app(const ShakeOnSignal(animate: true, signal: 0, child: Text('c'))),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(_shakeOffset(tester), 0.0);
    });

    testWidgets('shakes when the signal increments, and settles back', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const ShakeOnSignal(animate: true, signal: 0, child: Text('c'))),
      );

      await tester.pumpWidget(
        _app(const ShakeOnSignal(animate: true, signal: 1, child: Text('c'))),
      );

      await tester.pump(const Duration(milliseconds: 60));
      expect(_shakeOffset(tester).abs(), greaterThan(0.5));

      await tester.pumpAndSettle();
      // Damped to nothing: it must end exactly where it started.
      expect(_shakeOffset(tester), moreOrLessEquals(0.0, epsilon: 0.01));
    });

    testWidgets('a second refusal shakes again', (tester) async {
      // The reason the signal is a counter and not a flag: with a flag the
      // second wrong password would give no feedback at all.
      await tester.pumpWidget(
        _app(const ShakeOnSignal(animate: true, signal: 1, child: Text('c'))),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(const ShakeOnSignal(animate: true, signal: 2, child: Text('c'))),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(_shakeOffset(tester).abs(), greaterThan(0.5));
      await tester.pumpAndSettle();
    });

    testWidgets('never moves further than the specified distance', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const ShakeOnSignal(animate: true, signal: 0, child: Text('c'))),
      );
      await tester.pumpWidget(
        _app(const ShakeOnSignal(animate: true, signal: 1, child: Text('c'))),
      );

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(
          _shakeOffset(tester).abs(),
          lessThanOrEqualTo(AppMotion.subtle.shakeDistance + 0.01),
        );
      }

      await tester.pumpAndSettle();
    });
  });
}
