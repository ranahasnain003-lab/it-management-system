/// Tests for [SearchablePickerField]: the dropdown replacement used wherever
/// a Bazaar, a source location, a destination or an asset is chosen from a
/// list long enough that scrolling it is worse than searching it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/shared/widgets/searchable_picker.dart';

Widget _harness({
  required List<PickerOption<String>> options,
  required ValueChanged<String?> onChanged,
  String? value,
  bool enabled = true,
  String? Function(String?)? validator,
}) {
  final formKey = GlobalKey<FormState>();

  return MaterialApp(
    home: Scaffold(
      body: Form(
        key: formKey,
        child: SearchablePickerField<String>(
          value: value,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Bazaar'),
          options: options,
          onChanged: onChanged,
          validator: validator,
        ),
      ),
    ),
  );
}

const _bazaars = [
  PickerOption(value: 'b1', label: 'Township Bazaar', subtitle: 'Lahore'),
  PickerOption(value: 'b2', label: 'Model Town Bazaar', subtitle: 'Lahore'),
  PickerOption(value: 'b3', label: 'Gulberg Bazaar', subtitle: 'Lahore'),
  PickerOption(value: 'b4', label: 'Multan Bazaar', subtitle: 'Multan'),
];

void main() {
  testWidgets('tapping the field opens a list with every option', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(options: _bazaars, onChanged: (_) {}));

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    for (final bazaar in _bazaars) {
      expect(find.text(bazaar.label), findsOneWidget);
    }
  });

  testWidgets('typing narrows the list to what matches', (tester) async {
    await tester.pumpWidget(_harness(options: _bazaars, onChanged: (_) {}));

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'multan');
    await tester.pumpAndSettle();

    expect(find.text('Multan Bazaar'), findsOneWidget);
    expect(find.text('Township Bazaar'), findsNothing);
    expect(find.text('Model Town Bazaar'), findsNothing);
    expect(find.text('Gulberg Bazaar'), findsNothing);
  });

  testWidgets('a search finds a match on the subtitle, not only the label', (
    tester,
  ) async {
    // Searching "Lahore" has to find the three Bazaars whose city is Lahore
    // without any of them having that word in their name.
    await tester.pumpWidget(_harness(options: _bazaars, onChanged: (_) {}));

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'lahore');
    await tester.pumpAndSettle();

    expect(find.text('Township Bazaar'), findsOneWidget);
    expect(find.text('Model Town Bazaar'), findsOneWidget);
    expect(find.text('Gulberg Bazaar'), findsOneWidget);
    expect(find.text('Multan Bazaar'), findsNothing);
  });

  testWidgets('a search matching nothing shows the empty message', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(options: _bazaars, onChanged: (_) {}));

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nowhere');
    await tester.pumpAndSettle();

    expect(
      find.text('Nothing matches that search.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping an option reports it and closes the list', (
    tester,
  ) async {
    String? chosen;

    await tester.pumpWidget(
      _harness(options: _bazaars, onChanged: (value) => chosen = value),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gulberg Bazaar'));
    await tester.pumpAndSettle();

    expect(chosen, 'b3');
    // The sheet/dialog is gone, and the field now shows the choice, with its
    // subtitle appended.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Gulberg Bazaar — Lahore'), findsOneWidget);
  });

  testWidgets('the chosen value is marked with a check in the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(options: _bazaars, value: 'b2', onChanged: (_) {}),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Model Town Bazaar'),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a disabled field does not open', (tester) async {
    await tester.pumpWidget(
      _harness(options: _bazaars, enabled: false, onChanged: (_) {}),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the validator runs through FormState as normal', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: SearchablePickerField<String>(
              decoration: const InputDecoration(labelText: 'Bazaar'),
              options: _bazaars,
              onChanged: (_) {},
              validator: (value) =>
                  value == null ? 'Please choose a Bazaar.' : null,
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Please choose a Bazaar.'), findsOneWidget);
  });

  testWidgets('closing without choosing leaves the value untouched', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      _harness(options: _bazaars, value: 'b1', onChanged: (_) => calls++),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    // Close with the dialog/sheet's own close button rather than choosing.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Township Bazaar — Lahore'), findsOneWidget);
  });
}
