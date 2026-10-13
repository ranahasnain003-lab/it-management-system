/// Tests for the success mark drawn after a deployment, transfer, return or
/// approval.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/motion/success_check.dart';

Widget _app({
  required bool animations,
  required void Function(BuildContext) onTap,
}) {
  return MotionScope(
    enabled: animations,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onTap(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

/// Advances past the draw and the hold, then lets the fade finish.
///
/// The hold is a plain Timer, which schedules no frames, so pumpAndSettle on
/// its own returns while the mark is still up - the clock has to be moved by
/// hand.
Future<void> _runItOut(WidgetTester tester) async {
  // Pumped in steps rather than in one jump. The sequence crosses two awaits
  // and a Timer, so each stage only advances once the previous one's
  // microtask has drained; a single large pump would skip past a clock that
  // nothing is waiting on yet. Bounded so a regression fails rather than
  // hangs.
  for (var i = 0; i < 40; i++) {
    if (find.byKey(successCheckKey).evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('draws, holds, then removes itself', (tester) async {
    await tester.pumpWidget(_app(animations: true, onTap: showSuccessCheck));

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.byKey(successCheckKey), findsOneWidget);

    await _runItOut(tester);

    // Gone without the caller having to dismiss it.
    expect(find.byKey(successCheckKey), findsNothing);
  });

  testWidgets('shows nothing at all when motion is off', (tester) async {
    // With motion off there must be no undismissable square left on screen.
    // The caller's own SnackBar still reports the outcome.
    await tester.pumpWidget(_app(animations: false, onTap: showSuccessCheck));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byKey(successCheckKey), findsNothing);
  });

  testWidgets('never blocks what is underneath it', (tester) async {
    // An overlay, not a dialog: it must not take focus, swallow a back press,
    // or stop the user carrying on.
    var taps = 0;

    await tester.pumpWidget(
      _app(
        animations: true,
        onTap: (context) {
          taps++;
          showSuccessCheck(context);
        },
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(successCheckKey), findsOneWidget);

    // The button underneath still works while the mark is on screen.
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(taps, 2);

    await _runItOut(tester);
    await _runItOut(tester);
  });

  testWidgets('leaves no timer behind if the screen goes away mid-hold', (
    tester,
  ) async {
    // Why the hold is a cancellable Timer and not Future.delayed: a future
    // cannot be cancelled, so popping the screen would leave a callback
    // outliving the widget.
    await tester.pumpWidget(_app(animations: true, onTap: showSuccessCheck));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(AppMotion.success);

    // Torn down while the mark is still holding.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  test('the draw takes the 700ms the design asks for', () {
    expect(AppMotion.success.inMilliseconds, 700);
  });
}
