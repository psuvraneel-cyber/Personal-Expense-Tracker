import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/repositories/invoice_repository.dart';
import 'package:pet/premium/screens/invoice_editor_screen.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:provider/provider.dart';

class _OfflineSync implements FirestoreSyncService {
  @override
  bool get isAuthenticated => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final invoice = Invoice(
    id: 'i1',
    number: 'INV/26-27/0001',
    billTo: const BillTo(name: 'Acme'),
    issueDate: DateTime(2026, 11, 2),
    dueDate: DateTime(2026, 11, 17),
    items: const [
      InvoiceItem(description: 'Logo design', rate: 10000),
      InvoiceItem(description: 'Revisions', quantity: 2, rate: 1500),
    ],
    createdAt: DateTime(2026, 11, 2),
    updatedAt: DateTime(2026, 11, 2),
  );

  Future<void> pump(WidgetTester tester) async {
    // A tall screen, so the totals card at the bottom of the list is built.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = InvoiceProvider(
      repository: InvoiceRepository(),
      firestoreSync: _OfflineSync(),
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(home: InvoiceEditorScreen(invoice: invoice)),
    ));
    await tester.pumpAndSettle();
  }

  String total(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('invoice_total'))).data!;

  testWidgets('shows the items and a live total', (tester) async {
    await pump(tester);
    expect(find.text('Logo design'), findsOneWidget);
    expect(total(tester), '₹13,000.00');
    expect(find.text('Rupees Thirteen Thousand Only'), findsOneWidget);
  });

  testWidgets('a discount updates the total as you type', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Discount (₹)'), '1000');
    await tester.pump();
    expect(total(tester), '₹12,000.00');
  });

  testWidgets('removing an item updates the total', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Remove item').last);
    await tester.pump();
    expect(find.text('Revisions'), findsNothing);
    expect(total(tester), '₹10,000.00');
  });
}
