import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/widgets/home_summary.dart';
import 'package:pet/core/widgets/transaction_row.dart';
import 'package:pet/data/models/category.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/screens/home/home_tabs.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

TransactionRecord _txn({
  String note = '',
  String? merchant,
  TransactionType type = TransactionType.expense,
  double amount = 240,
}) =>
    TransactionRecord(
      id: 't1',
      amount: amount,
      type: type,
      categoryId: 'health',
      date: DateTime(2026, 11, 2, 18, 4),
      note: note,
      merchantName: merchant,
    );

final _health = Category(
  id: 'health',
  name: 'Health',
  icon: Icons.local_hospital_rounded,
  color: Colors.teal,
);

void main() {
  group('TransactionRow title', () {
    test('prefers the merchant, then the note without the bank', () {
      expect(
        TransactionRow.titleFor(_txn(merchant: 'Raju Medicals'), _health),
        'Raju Medicals',
      );
      expect(
        TransactionRow.titleFor(
          _txn(note: 'Gupta Sweets (HDFC Bank)'),
          _health,
        ),
        'Gupta Sweets',
      );
    });

    test('falls back to the category for unknown counterparties', () {
      expect(
        TransactionRow.titleFor(_txn(note: 'Unknown (HDFC Bank)'), _health),
        'Health',
      );
      expect(TransactionRow.titleFor(_txn(), null), 'Transaction');
    });
  });

  testWidgets('a row shows merchant, category and a signed amount', (t) async {
    await t.pumpWidget(_app(TransactionRow(
      transaction: _txn(note: 'Raju Medicals (HDFC Bank)'),
      category: _health,
    )));
    expect(find.text('Raju Medicals'), findsOneWidget);
    expect(find.text('Health · 6:04 PM'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Raju Medicals, expense ₹240')),
      findsOneWidget,
    );
  });

  group('HomeStatStrip', () {
    testWidgets('without a budget it never claims you are over budget',
        (t) async {
      await t.pumpWidget(_app(const HomeStatStrip(
        spentToday: 2473,
        budget: 0,
        spentThisMonth: 3248,
        score: 82,
      )));
      expect(find.text('Over budget'), findsNothing);
      expect(find.text('Daily average'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
    });

    testWidgets('over budget is shown only when a budget is exceeded',
        (t) async {
      await t.pumpWidget(_app(const HomeStatStrip(
        spentToday: 100,
        budget: 3000,
        spentThisMonth: 3248,
        score: 40,
      )));
      expect(find.text('Over budget'), findsOneWidget);
    });
  });

  testWidgets('the hero shows the month spend and what is left', (t) async {
    await t.pumpWidget(_app(const HomeHero(
      greeting: 'Good evening, Tester',
      monthLabel: 'November',
      spent: 3248,
      budget: 20000,
      income: 103500,
    )));
    await t.pumpAndSettle();
    expect(find.text('Good evening, Tester'), findsOneWidget);
    expect(find.text('Spent in November'), findsOneWidget);
    expect(find.text('₹16,752 left of ₹20,000'), findsOneWidget);
    expect(find.bySemanticsLabel('₹3,248'), findsOneWidget);
  });

  test('HomeTabs re-notifies when the same tab is asked for twice', () {
    var calls = 0;
    void listener() {
      if (HomeTabs.request.value != null) calls++;
    }

    HomeTabs.request.addListener(listener);
    HomeTabs.show(HomeTabs.history);
    HomeTabs.show(HomeTabs.history);
    HomeTabs.request.removeListener(listener);
    expect(calls, 2);
  });
}
