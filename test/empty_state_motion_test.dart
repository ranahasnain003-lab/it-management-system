/// Tests for the empty-state float.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/shared/widgets/app_states.dart';
import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/widgets/motion/gentle_float.dart';

Widget _app(Widget child, {bool animations = true}) {
  return MotionScope(
    enabled: animations,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

double _offset(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(of: find.byType(GentleFloat), matching: find.byType(Transform))
        .first,
  );
  return transform.transform.getTranslation().y;
}

void main() {
  testWidgets('stays still, with no controller, when motion is off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const GentleFloat(animate: false, child: Icon(Icons.inbox)),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(GentleFloat),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('never drifts further than 3px', (tester) async {
    // The whole point is that it is barely noticeable. A larger drift would
    // turn an empty inventory screen into a decoration.
    await tester.pumpWidget(
      _app(const GentleFloat(animate: true, child: Icon(Icons.inbox))),
    );

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        _offset(tester).abs(),
        lessThanOrEqualTo(AppMotion.floatDistance + 0.01),
      );
    }
  });

  testWidgets('actually moves', (tester) async {
    await tester.pumpWidget(
      _app(const GentleFloat(animate: true, child: Icon(Icons.inbox))),
    );

    final start = _offset(tester);
    await tester.pump(const Duration(milliseconds: 750));

    expect((_offset(tester) - start).abs(), greaterThan(1.0));
  });

  group('AppEmptyState', () {
    testWidgets('floats its icon but never its text', (tester) async {
      await tester.pumpWidget(
        _app(
          const AppEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No assets yet',
            message: 'Added assets will appear here.',
          ),
        ),
      );

      // The icon is inside the float; the words are not. Moving text is
      // harder to read, and this is often the first thing someone sees.
      expect(find.byType(GentleFloat), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GentleFloat),
          matching: find.text('No assets yet'),
        ),
        findsNothing,
      );
      expect(find.text('No assets yet'), findsOneWidget);
    });

    testWidgets('settles completely when motion is off', (tester) async {
      await tester.pumpWidget(
        _app(
          const AppEmptyState(icon: Icons.inbox, title: 'Nothing here'),
          animations: false,
        ),
      );

      // Would hang if the float were still looping.
      await tester.pumpAndSettle();
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('still shows its action button', (tester) async {
      await tester.pumpWidget(
        _app(
          AppEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No assets yet',
            action: FilledButton(onPressed: () {}, child: const Text('Add asset')),
          ),
        ),
      );

      expect(find.text('Add asset'), findsOneWidget);
    });
  });
}
