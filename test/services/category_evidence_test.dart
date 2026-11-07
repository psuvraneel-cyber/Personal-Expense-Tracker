import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/services/merchant_normalizer.dart';
import 'package:pet/services/category_mapper.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/services/financial_ingestion_service.dart';

/// When the payee is unknown, only a whole-word brand in the message may
/// pick the category; generic keywords must not match inside other words.
void main() {
  final ts = DateTime(2026, 10, 5, 12, 0);

  Future<String> categoryFor(String body, {bool income = false}) async {
    final c = await ClassificationRuleEngine.classify(body, 'AD-HDFCBK', ts,
        logUnknown: false);
    return FinancialIngestionService.importCategoryId(
      classified: c,
      merchant: c?.merchantName ?? 'Unknown',
      isIncome: income,
      text: body,
    );
  }

  group('unknown payee', () {
    test('a phone-number UPI payment from a Savings account is not Bills',
        () async {
      expect(
        await categoryFor('Rs 500 debited from Savings A/c XX1234 via UPI to '
            'VPA 9000000001@ybl on 05-Oct-26. UPI Ref 412300000001.'),
        'cat_other_expense',
      );
    });

    test('"customer service" wording does not make it Bills', () async {
      expect(
        await categoryFor('Rs 75 debited from A/c XX1234. UPI Ref '
            '512300000007. Call customer service if not you.'),
        'cat_other_expense',
      );
    });

    test('a brand named in the message still sets the category', () {
      expect(
        FinancialIngestionService.importCategoryId(
          classified: null,
          merchant: 'Unknown',
          isIncome: false,
          text: 'Payment confirmed for your Swiggy order of Rs. 124.0',
        ),
        'cat_food',
      );
    });
  });

  group('findBrandIn', () {
    test('finds a whole-word brand', () {
      expect(MerchantNormalizer.findBrandIn('Paid to ZOMATO LTD'), 'Zomato');
    });

    test('returns null when no brand is named', () {
      expect(MerchantNormalizer.findBrandIn('debited via UPI'), isNull);
    });
  });

  group('short keywords', () {
    test('"vi" does not match inside a name', () {
      expect(CategoryMapper.mapToCategoryId(merchantName: 'RAVI KUMAR'),
          'cat_other_expense');
    });

    test('"ola" does not match inside a word', () {
      expect(CategoryMapper.mapToCategoryId(merchantName: 'KOLAR STORES'),
          'cat_other_expense');
    });

    test('brands joined to other words still match', () {
      expect(CategoryMapper.mapToCategoryId(merchantName: 'OLACABS'),
          'cat_transport');
    });

    test('whole-word keywords still match', () {
      expect(CategoryMapper.mapToCategoryId(merchantName: 'VI PREPAID'),
          'cat_bills');
    });
  });
}
