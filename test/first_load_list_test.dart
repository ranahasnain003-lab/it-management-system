/// Tests for "list rows animate on the first load and never again".
///
/// This is the rule most likely to be broken by a later change, and the one
/// users notice fastest when it is: a list that fades rows in as you scroll
/// turns polish into irritation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/motion/entrance.dart';
import 'package:it_management_system/core/widgets/motion/first_load_list.dart';

/// A list that uses the latch exactly as the real screens do.
class _Harness extends StatefulWidget {
  const _Harness({required this.rows, required this.entrance});

  final int rows;
  final FirstLoadEntrance entrance;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: widget.rows,
      itemBuilder: (context, index) {
        final row = SizedBox(height: 40, child: Text('row $index'));

        if (index >= FirstLoadEntrance.maxRows - 1) widget.entrance.spend();

        return widget.entrance.wrap(context, index, row);
      },
    );
  }
}

Widget _app(Widget child, {AnimationLevel level = AnimationLevel.rich}) {
  return MotionScope(
    level: level,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

int _animatedRows(WidgetTester tester) =>
    find.byType(EntranceFadeSlide).evaluate().length;

void main() {
  testWidgets('the first rows animate on the first load', (tester) async {
    final entrance = FirstLoadEntrance();

    await tester.pumpWidget(_app(_Harness(rows: 30, entrance: entrance)));

    expect(_animatedRows(tester), greaterThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('only the first handful animate, however long the list', (
    tester,
  ) async {
    // A list of two thousand assets must not stagger for a minute.
    final entrance = FirstLoadEntrance();

    await tester.pumpWidget(_app(_Harness(rows: 500, entrance: entrance)));

    expect(_animatedRows(tester), lessThanOrEqualTo(FirstLoadEntrance.maxRows));
    await tester.pumpAndSettle();
  });

  testWidgets('a refresh does not replay it', (tester) async {
    // The latch is spent, so rebuilding the same screen with new data - which
    // is what a pull-to-refresh and a Firestore push both look like - leaves
    // the rows alone.
    final entrance = FirstLoadEntrance();

    await tester.pumpWidget(_app(_Harness(rows: 30, entrance: entrance)));
    await tester.pumpAndSettle();

    expect(entrance.isPending, isFalse);

    await tester.pumpWidget(_app(_Harness(rows: 42, entrance: entrance)));
    await tester.pump();

    expect(_animatedRows(tester), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('scrolling never animates a row', (tester) async {
    final entrance = FirstLoadEntrance();

    await tester.pumpWidget(_app(_Harness(rows: 200, entrance: entrance)));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();

    expect(_animatedRows(tester), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('a new visit to the screen animates again', (tester) async {
    // The latch belongs to the screen's State, so leaving and coming back is
    // a new visit - which is what makes the entrance feel like arriving
    // somewhere rather than a one-time curiosity.
    await tester.pumpWidget(
      _app(_Harness(rows: 30, entrance: FirstLoadEntrance())),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _app(_Harness(rows: 30, entrance: FirstLoadEntrance())),
    );
    await tester.pump();

    expect(_animatedRows(tester), greaterThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('nothing animates when motion is off', (tester) async {
    final entrance = FirstLoadEntrance();

    await tester.pumpWidget(
      _app(
        _Harness(rows: 30, entrance: entrance),
        level: AnimationLevel.off,
      ),
    );

    expect(_animatedRows(tester), 0);
    await tester.pumpAndSettle();
  });
}
