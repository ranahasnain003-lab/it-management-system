import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/app.dart';

void main() {
  testWidgets('IT Management System app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    expect(find.byType(App), findsOneWidget);
  });
}