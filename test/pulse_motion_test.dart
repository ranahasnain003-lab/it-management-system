/// Tests for the loading pulse shown while the account and permissions load.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/motion/pulse.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(of: find.byType(PulseFade), matching: find.byType(Opacity)),
    )
    .opacity;

void main() {
  testWidgets('renders solid, with no controller, when motion is off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const PulseFade(animate: false, child: Text('logo'))),
    );

    // Would hang here if a repeating controller existed.
    await tester.pumpAndSettle();
    expect(find.text('logo'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PulseFade),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  testWidgets('breathes between pulseMin and full, never disappearing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const PulseFade(animate: true, child: Text('logo'))),
    );

    var lowest = 1.0;
    var highest = 0.0;

    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 75));
      final value = _opacity(tester);
      lowest = value < lowest ? value : lowest;
      highest = value > highest ? value : highest;
    }

    // It fades, but the logo is always clearly visible: a logo that blinks out
    // reads as a fault rather than as progress.
    expect(lowest, greaterThanOrEqualTo(AppMotion.pulseMin - 0.01));
    expect(highest, greaterThan(0.9));
    expect(lowest, lessThan(0.8));
  });

  testWidgets('only changes opacity - it never turns or scales', (tester) async {
    // The design forbids a spinning or throbbing logo outright.
    await tester.pumpWidget(
      _app(const PulseFade(animate: true, child: Text('logo'))),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(
        of: find.byType(PulseFade),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });
}
