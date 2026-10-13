/// Tests for the Local AI waiting dots.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/motion/waiting_dots.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

List<double> _opacities(WidgetTester tester) {
  return tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(WaitingDots),
          matching: find.byType(Container),
        ),
      )
      .map((c) => ((c.decoration as BoxDecoration).color!).a)
      .toList();
}

void main() {
  testWidgets('shows three dots', (tester) async {
    await tester.pumpWidget(
      _app(const WaitingDots(animate: true, color: Colors.black)),
    );

    expect(_opacities(tester).length, 3);
  });

  testWidgets('stays visible and still when motion is off', (tester) async {
    // The caller is still waiting, so the dots must remain on screen - they
    // simply stop moving. And with no controller, this settles.
    await tester.pumpWidget(
      _app(const WaitingDots(animate: false, color: Colors.black)),
    );

    await tester.pumpAndSettle();

    final values = _opacities(tester);
    expect(values.length, 3);
    expect(values.every((v) => v > 0.3), isTrue);
    // All identical: no wave.
    expect(values.toSet().length, 1);
  });

  testWidgets('the three dots are out of step with each other', (tester) async {
    await tester.pumpWidget(
      _app(const WaitingDots(animate: true, color: Colors.black)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final values = _opacities(tester);

    // A wave, not a single blink: if all three shared one opacity the row
    // would pulse as a block, which looks like a fault rather than progress.
    expect(values.toSet().length, greaterThan(1));
  });

  testWidgets('every dot stays within the specified opacity range', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const WaitingDots(animate: true, color: Colors.black)),
    );

    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      for (final value in _opacities(tester)) {
        expect(value, greaterThanOrEqualTo(AppMotion.dotMin - 0.01));
        expect(value, lessThanOrEqualTo(AppMotion.dotMax + 0.01));
      }
    }
  });

  testWidgets('the cycle is the 1.2s the design asks for', (tester) async {
    expect(AppMotion.dots.inMilliseconds, 1200);
  });
}
