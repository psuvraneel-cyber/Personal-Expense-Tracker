import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/screens/sms_transactions/pending_review_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeProvider extends SmsTransactionProvider {
  _FakeProvider(this.items);

  final List<SmsTransaction> items;
  final accepted = <String, String?>{};
  final rejected = <String>[];

  @override
  List<SmsTransaction> get uncertainTransactions => items;

  @override
  bool get isLoading => false;

  @override
  Future<void> loadTransactions() async {}

  @override
  Future<void> acceptUncertainTransaction(
    String id, {
    String? overrideType,
    double? overrideAmount,
    String? overrideMerchant,
    String? overrideCategoryId,
  }) async {
    accepted[id] = overrideType;
  }

  @override
  Future<void> rejectUncertainTransaction(String id) async {
    rejected.add(id);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const sms = 'Dear BOB UPI User: Your account is credited with INR 75.00 on '
      '2026-10-10 12:41:33 PM by UPI Ref No 628300011122; '
      'AvlBal: Rs305.77 - BOB';

  SmsTransaction item() => SmsTransaction(
        id: 'obs_1',
        amount: 75,
        merchantName: 'Unknown',
        bankName: 'Bank of Baroda',
        transactionType: 'credit',
        timestamp: DateTime(2026, 10, 10, 12, 41),
        rawSmsBody: sms,
        smsSender: 'JK-BOBSMS-S',
        smsHash: 'h1',
        category: 'Uncategorized',
        confidence: 0.75,
        source: 'sms',
      );

  Future<_FakeProvider> pumpScreen(WidgetTester tester) async {
    final provider = _FakeProvider([item()]);
    await tester.pumpWidget(
      ChangeNotifierProvider<SmsTransactionProvider>.value(
        value: provider,
        child: const MaterialApp(home: PendingReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(find.text('Unknown'));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a review item shows its details and original SMS',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text(sms), findsNothing);

    await openDetails(tester);

    expect(find.text('Review Transaction'), findsOneWidget);
    expect(find.text('Original SMS'), findsOneWidget);
    expect(find.text(sms), findsOneWidget);
    expect(find.text('JK-BOBSMS-S'), findsOneWidget);
    expect(find.text('Credit (money in)'), findsOneWidget);
    expect(find.text('75% sure'), findsWidgets);
  });

  testWidgets('accepting from the details sheet accepts that item',
      (tester) async {
    final provider = await pumpScreen(tester);
    await openDetails(tester);

    await tester.ensureVisible(find.text('Accept as credit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept as credit'));
    await tester.pumpAndSettle();

    expect(provider.accepted, {'obs_1': 'credit'});
    expect(find.text('Review Transaction'), findsNothing);
  });

  testWidgets('rejecting from the details sheet rejects that item',
      (tester) async {
    final provider = await pumpScreen(tester);
    await openDetails(tester);

    await tester.ensureVisible(find.text('Not a transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a transaction'));
    await tester.pumpAndSettle();

    expect(provider.rejected, ['obs_1']);
  });

  testWidgets('the card buttons still act without opening the sheet',
      (tester) async {
    final provider = await pumpScreen(tester);

    await tester.tap(find.text('Credit'));
    await tester.pumpAndSettle();

    expect(provider.accepted, {'obs_1': 'credit'});
    expect(find.text('Review Transaction'), findsNothing);
  });
}
