import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/services/household_service.dart';

TransactionRecord _txn(String id, double amount, String category,
        {TransactionType type = TransactionType.expense}) =>
    TransactionRecord(
      id: id,
      amount: amount,
      type: type,
      categoryId: category,
      date: DateTime(2026, 10, 5),
      updatedAt: DateTime(2026, 10, 5),
    );

void main() {
  test('invite codes use the unambiguous alphabet and match the rules', () {
    final code = HouseholdService.newInviteCode(Random(1));
    expect(code, matches(RegExp(r'^[A-Z2-9]{8}$')));
    expect(code, isNot(matches(RegExp('[01IOL]'))));
  });

  test('typed invite codes are normalised', () {
    expect(HouseholdService.normaliseInviteCode(' abcd-2345 '), 'ABCD2345');
    expect(HouseholdService.normaliseInviteCode('short'), isNull);
  });

  test('spending doc ids match the security rules pattern', () {
    expect(HouseholdService.spendingDocId('uid123', DateTime(2026, 3, 15)),
        'uid123_202603');
    expect(HouseholdService.monthKey(DateTime(2026, 3, 15)), '2026-03');
  });

  test('only expense totals per category are shared', () {
    final totals = HouseholdSync.categoryTotals([
      _txn('a', 100, 'food'),
      _txn('b', 50.5, 'food'),
      _txn('c', 999, 'salary', type: TransactionType.income),
      _txn('d', 20, 'travel'),
    ]);
    expect(totals, {'food': 150.5, 'travel': 20});
  });
}
