import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/screens/cashflow_screen.dart';

void main() {
  Future<double?> openAndSave(WidgetTester tester, String? typed) async {
    double? result;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<double>(
              context: context,
              builder: (_) => const BalanceDialog(),
            );
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (typed != null) await tester.enterText(find.byType(TextField), typed);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    if (!closed) return null;
    return result;
  }

  testWidgets('saving closes the dialog cleanly with the amount',
      (tester) async {
    expect(await openAndSave(tester, '30000'), 30000);
    // The old dialog disposed its controller while still closing, which
    // tripped a framework assertion here.
    expect(tester.takeException(), isNull);
    expect(find.byType(BalanceDialog), findsNothing);
  });

  testWidgets('an empty amount shows an error and keeps the dialog open',
      (tester) async {
    await openAndSave(tester, '');
    expect(find.text('Enter an amount in rupees'), findsOneWidget);
    expect(find.byType(BalanceDialog), findsOneWidget);
  });

  testWidgets('a zero balance is allowed', (tester) async {
    expect(await openAndSave(tester, '0'), 0);
  });
}
