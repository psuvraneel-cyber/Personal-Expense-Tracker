import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/screens/settings/trusted_messages_screen.dart';
import 'package:pet/services/trusted_template_service.dart';

class _FakeService extends TrustedTemplateService {
  final List<TrustedTemplate> items;
  _FakeService(this.items);

  @override
  Future<List<TrustedTemplate>> all() async => List.of(items);

  @override
  Future<void> remove(String templateHash) async =>
      items.removeWhere((t) => t.templateHash == templateHash);
}

void main() {
  testWidgets('removing a trusted message type updates the list',
      (tester) async {
    final service = _FakeService([
      TrustedTemplate(
        templateHash: 'h1',
        sender: 'HDFCBK',
        direction: 'debit',
        example: 'rs # debited at unknown shop. info txn.',
        createdAt: DateTime(2026, 11, 2),
        useCount: 1,
        lastUsedAt: DateTime(2026, 11, 2),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: TrustedMessagesScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('HDFCBK · money out'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop auto-adding'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('HDFCBK · money out'), findsNothing);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('Removed.'), findsOneWidget);
  });
}
