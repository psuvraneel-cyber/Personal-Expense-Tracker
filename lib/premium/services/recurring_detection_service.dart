import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/services/recurrence_calculator.dart';
import 'package:uuid/uuid.dart';

class RecurringDetectionService {
  RecurringDetectionService._();

  static const Uuid _uuid = Uuid();

  /// Normalizes raw merchant names for robust grouping and duplicate avoidance.
  /// E.g. "NETFLIX INDIA PVT LTD" -> "Netflix", "Spotify.com" -> "Spotify".
  static String normalizeMerchantName(String raw) {
    if (raw.trim().isEmpty) return 'Unknown Merchant';
    var cleaned = raw.trim();

    // Remove common transaction prefixes
    cleaned = cleaned.replaceAll(
      RegExp(
        r'^(UPI[-/:\s]|POS[-/:\s]|VPA[-/:\s]|ACH[-/:\s]|NACH[-/:\s]|ECS[-/:\s]|BIL[-/:\s]|BILL[-/:\s]|Pay to |Payment to |Transfer to |Bill to )',
        caseSensitive: false,
      ),
      '',
    );

    // Remove domain suffixes
    cleaned = cleaned.replaceAll(
      RegExp(r'\.(com|co\.in|in|org|net|io|app)\b', caseSensitive: false),
      '',
    );

    // Remove legal/country entity words
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(pvt|ltd|private|limited|india|inc|corp|services|billdesk|bill\s*desk)\b', caseSensitive: false),
      '',
    );

    // Strip special noise characters and collapse whitespace
    cleaned = cleaned.replaceAll(RegExp(r'[\*\-_/\\#:@\.]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty) return raw.trim();

    // Capitalize words for clean display
    return cleaned.split(' ').map((w) {
      if (w.isEmpty) return '';
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  /// Analyzes SMS/transaction history to detect recurring payments and price changes.
  static List<RecurringPayment> detect(List<SmsTransaction> transactions) {
    // 1. Group debit transactions by normalized merchant identity
    final byMerchant = <String, List<SmsTransaction>>{};
    for (final t in transactions) {
      if (t.transactionType != 'debit') continue;
      final norm = normalizeMerchantName(t.merchantName).toLowerCase();
      if (norm.isEmpty || norm == 'unknown merchant') continue;
      byMerchant.putIfAbsent(norm, () => []).add(t);
    }

    final results = <RecurringPayment>[];

    for (final entry in byMerchant.entries) {
      final items = entry.value
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (items.length < 2) continue;

      // 2. Infer frequency and check consistency
      final freq = _inferFrequency(items);
      if (freq == null) continue;

      // 3. Analyze amounts for stable price vs. price change vs. variable spending
      final amountAnalysis = _analyzeAmounts(items);
      if (amountAnalysis == null) continue; // Discard erratic variable spending

      final last = items.last;
      final displayName = normalizeMerchantName(last.merchantName);
      final frequencyEnum = freq;
      final nextDue = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: last.timestamp,
        currentOccurrence: last.timestamp,
        frequency: frequencyEnum,
      );

      // Score confidence based on number of cycles and consistency
      double confidence = 0.65;
      if (items.length >= 3) confidence = 0.85;
      if (items.length >= 4) confidence = 0.95;

      final spanDays = items.last.timestamp.difference(items.first.timestamp).inDays;
      String reason = 'Detected from ${items.length} recurring payments over $spanDays days';
      if (amountAnalysis.isPriceChanged) {
        reason = 'Detected price change from ₹${amountAnalysis.previousAmount!.toStringAsFixed(0)} to ₹${amountAnalysis.currentAmount.toStringAsFixed(0)} ($reason)';
      }

      results.add(
        RecurringPayment(
          id: _uuid.v4(),
          merchantName: displayName,
          amount: amountAnalysis.currentAmount,
          frequency: frequencyEnum.name,
          lastPaidAt: last.timestamp,
          nextDueAt: nextDue,
          categoryId: 'other',
          confidence: confidence,
          source: last.source,
          status: RecurringStatus.detected,
          isAutopay: false,
          previousAmount: amountAnalysis.previousAmount,
          priceChangeDetectedAt: amountAnalysis.priceChangeDetectedAt,
          detectionReason: reason,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    return results;
  }

  /// Calculates average interval and maps to RecurringFrequency.
  static RecurringFrequency? _inferFrequency(List<SmsTransaction> items) {
    final diffs = <int>[];
    for (var i = 1; i < items.length; i++) {
      final diff = items[i].timestamp.difference(items[i - 1].timestamp).inDays;
      if (diff > 0) diffs.add(diff);
    }
    if (diffs.isEmpty) return null;

    final avgDays = diffs.reduce((a, b) => a + b) / diffs.length;

    // Reject if variance is excessive (e.g., diffs vary from 3 to 150 days randomly)
    final minDiff = diffs.reduce((a, b) => a < b ? a : b);
    final maxDiff = diffs.reduce((a, b) => a > b ? a : b);
    if (diffs.length >= 3 && (maxDiff - minDiff) > (avgDays * 0.75)) {
      return null;
    }

    if (avgDays >= 1 && avgDays <= 2) return RecurringFrequency.daily;
    if (avgDays >= 6 && avgDays <= 9) return RecurringFrequency.weekly;
    if (avgDays >= 26 && avgDays <= 35) return RecurringFrequency.monthly;
    if (avgDays >= 80 && avgDays <= 100) return RecurringFrequency.quarterly;
    if (avgDays >= 170 && avgDays <= 195) return RecurringFrequency.semiannual;
    if (avgDays >= 350 && avgDays <= 380) return RecurringFrequency.yearly;

    return null;
  }

  /// Evaluates amounts to distinguish fixed commitments, price updates, and random variable spending.
  static ({
    double currentAmount,
    double? previousAmount,
    DateTime? priceChangeDetectedAt,
    bool isPriceChanged,
  })? _analyzeAmounts(List<SmsTransaction> items) {
    final amounts = items.map((t) => t.amount).toList();
    final latestAmount = amounts.last;

    // Check if all amounts are identical within a ₹1 threshold
    final allEqual = amounts.every((a) => (a - latestAmount).abs() < 1.0);
    if (allEqual) {
      return (
        currentAmount: latestAmount,
        previousAmount: null,
        priceChangeDetectedAt: null,
        isPriceChanged: false,
      );
    }

    // Check for a clean step-up price change (e.g. [199, 199, 199, 249] or [199, 199, 249, 249])
    if (items.length >= 3) {
      final earlierAmounts = amounts.sublist(0, amounts.length - 1);
      final baselineAmount = earlierAmounts.first;
      final baselineConsistent = earlierAmounts.every((a) => (a - baselineAmount).abs() < 1.0);

      if (baselineConsistent && (latestAmount - baselineAmount).abs() >= 1.0) {
        return (
          currentAmount: latestAmount,
          previousAmount: baselineAmount,
          priceChangeDetectedAt: items.last.timestamp,
          isPriceChanged: true,
        );
      }
    }

    // If amounts fluctuate continuously (e.g. 150, 480, 210, 890), this is variable spending, not a fixed bill
    return null;
  }
}
