import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/services/financial_ingestion_service.dart';

void main() {
  final timestamp = DateTime(2026, 9, 22, 16, 41);

  Future<String> category({
    required String body,
    required String sender,
    required bool isIncome,
  }) async {
    final classified = await ClassificationRuleEngine.classify(
      body,
      sender,
      timestamp,
      logUnknown: false,
    );
    expect(classified, isNotNull, reason: body);
    return FinancialIngestionService.importCategoryId(
      classified: classified,
      merchant: classified!.merchantName,
      isIncome: isIncome,
      text: body,
    );
  }

  test('Swiggy confirmation uses text evidence when clock text is not a payee',
      () async {
    final id = await category(
      body: 'Payment Confirmed! Your Swiggy Order #XX****1111 of Rs. 124.0 '
          'was successfully paid on 22/09/2026 at 04:41 PM. '
          'Txn ID: 4123000045670001.',
      sender: 'AD-SWIGGY-S',
      isIncome: false,
    );
    expect(id, 'cat_food');
  });

  test('named merchants map to expense categories', () async {
    expect(
      await category(
        body: 'Rs 450 debited from A/c XX1234 to VPA amazon@apl '
            'on 22-Sep-26. UPI Ref 512345678901.',
        sender: 'AD-HDFCBK',
        isIncome: false,
      ),
      'cat_shopping',
    );
    expect(
      await category(
        body: 'You paid Rs 200 to Paytm on 22-Sep-26. Ref 512345678902.',
        sender: 'AD-PAYTM',
        isIncome: false,
      ),
      // Paytm identifies the payment channel, not the purchased category;
      // keeping the safe fallback is preferable to guessing.
      'cat_other_expense',
    );
    expect(
      await category(
        body: 'Rs 350 debited from A/c XX1234 to VPA '
            'kirana@okaxis (LOCAL GROCERY STORE) on 22-Sep-26. Ref 512345678903.',
        sender: 'AD-HDFCBK',
        isIncome: false,
      ),
      'cat_groceries',
    );
  });

  test('person credits retain From people classification', () async {
    final classified = await ClassificationRuleEngine.classify(
      'Rs 1,200 credited to HDFC Bank A/c XX1234 on 22-Sep-26 from VPA '
          '9876500001@ybl (RAHUL SHARMA). UPI Ref 512345678904.',
      'AD-HDFCBK',
      timestamp,
      logUnknown: false,
    );
    expect(classified, isNotNull);
    expect(
      FinancialIngestionService.importCategoryId(
        classified: classified,
        merchant: classified!.merchantName,
        isIncome: true,
        text: 'person credit',
      ),
      'cat_from_people',
    );
  });

  test('refunds and cashback use safe income fallback categories', () async {
    expect(
      await category(
        body: 'Refund of Rs 299 credited to HDFC Bank A/c XX1234 from AMAZON '
            'on 22-Sep-26. Ref 512345678905.',
        sender: 'AD-HDFCBK',
        isIncome: true,
      ),
      'cat_other_income',
    );
    expect(
      await category(
        body: 'Cashback of Rs 25 credited to A/c XX1234 on 22-Sep-26. '
            'Ref 512345678906.',
        sender: 'AD-HDFCBK',
        isIncome: true,
      ),
      'cat_other_income',
    );
  });

  test('salary is distinct from ordinary credits', () async {
    expect(
      await category(
        body: 'Rs 50,000 credited by NEFT from ACME PVT LTD - SALARY.',
        sender: 'AD-HDFCBK',
        isIncome: true,
      ),
      'cat_salary',
    );
  });

  test('unknown payees and bank transfers keep safe handling', () async {
    expect(
      await category(
        body: 'Rs 75 debited from A/c XX1234. UPI Ref 512345678907.',
        sender: 'XX-UNKNOWN',
        isIncome: false,
      ),
      'cat_other_expense',
    );
    expect(
      FinancialIngestionService.isPossibleTransfer(
        'Rs 15,000 transferred to your own account on 22-Sep-26.',
      ),
      isTrue,
    );
  });
}
