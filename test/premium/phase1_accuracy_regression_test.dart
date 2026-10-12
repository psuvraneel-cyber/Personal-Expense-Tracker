// Regression tests for the premium QA audit's Phase 1 findings.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/services/ai_copilot_service.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/anomaly_detection_service.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';

final now = DateTime(2026, 10, 12, 12);

TransactionRecord txn(String id, double amount, DateTime date,
        {String category = 'food',
        TransactionType type = TransactionType.expense}) =>
    TransactionRecord(
      id: id,
      amount: amount,
      type: type,
      categoryId: category,
      date: date,
      updatedAt: date,
    );

void main() {
  test('R4: a partly tracked first month is not a baseline (audit P4b)', () {
    final txns = [
      txn('sep', 400, DateTime(2026, 9, 28)), // installed 28 Sep
      txn('oct', 2500, DateTime(2026, 10, 10)),
    ];
    final base = AlertEvaluator.computeBaseline(txns, now: now);
    expect(base, isEmpty);
    expect(AnomalyDetectionService.detectSpikes(txns, base, now: now), isEmpty);
  });

  test('R4: tracking from the 1st counts that month', () {
    final base = AlertEvaluator.computeBaseline([
      txn('a', 3000, DateTime(2026, 9, 1, 8)),
      txn('b', 2000, DateTime(2026, 9, 20)),
    ], now: now);
    expect(base['food'], 5000);
  });

  test('R4: rent paid early in the month does not trigger pacing', () {
    final txns = [
      txn('rent', 15000, DateTime(2026, 10, 5), category: 'housing'),
      txn('fix', 400, DateTime(2026, 10, 9), category: 'housing'),
    ];
    final largest = AlertEvaluator.largestExpenseThisMonth(txns, now: now);
    const budgets = {'housing': 16000.0, 'food': 6000.0};
    const spent = {'housing': 15400.0, 'food': 4000.0};
    final alerts = AlertEvaluator.evaluateBudgetPacing(
      budgets: budgets,
      spent: spent,
      now: now,
      largestExpense: {...largest, 'food': 400},
    );
    // Food: ₹4,000 in 12 days is a real pace problem; housing isn't.
    expect(alerts.map((a) => a.categoryId), ['food']);
  });

  test('R5: AI totals are for the current month only', () {
    final t = AiCopilotService.monthTotals([
      txn('aug', 9999, DateTime(2026, 8, 20)),
      txn('oct1', 300, DateTime(2026, 10, 3)),
      txn('oct2', 200, DateTime(2026, 10, 9), category: 'transport'),
      txn('sal', 60000, DateTime(2026, 10, 1),
          type: TransactionType.income, category: 'salary'),
      txn('future', 5000, DateTime(2026, 10, 30)),
    ], now);
    expect([t.income, t.expense], [60000, 500]);
    expect(t.byCategory, {'food': 300, 'transport': 200});
  });

  group('R9: hiding amounts in notifications', () {
    test('masks rupee amounts in every common format', () {
      expect(
        NotificationPreferencesService.maskAmounts(
            'Detected: ₹1,240.50 at Swiggy. Rs. 500 left, INR 2000 due, '
            'Rs400 paid'),
        'Detected: ₹••• at Swiggy. ₹••• left, ₹••• due, ₹••• paid',
      );
      expect(NotificationPreferencesService.maskAmounts('3 bills due'),
          '3 bills due');
    });

    test('defaults to the biometric lock, then follows the setting', () async {
      SharedPreferences.setMockInitialValues({'biometricEnabled': true});
      expect(await NotificationPreferencesService.hideAmounts(), isTrue);
      await NotificationPreferencesService.setHideAmounts(false);
      expect(await NotificationPreferencesService.hideAmounts(), isFalse);
      SharedPreferences.setMockInitialValues({});
      expect(await NotificationPreferencesService.hideAmounts(), isFalse);
    });
  });
}
