import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Simple widget rendering smoke test', (
    WidgetTester tester,
  ) async {
    // Build a simple text widget and verify it renders.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('P.E.T Tracker'))),
    );

    expect(find.text('P.E.T Tracker'), findsOneWidget);
  });
}
