import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';

class CategorySpike {
  final String categoryId;
  final double currentSpend;
  final double baselineSpend;
  final double ratio;

  const CategorySpike({
    required this.categoryId,
    required this.currentSpend,
    required this.baselineSpend,
    required this.ratio,
  });
}

class AnomalyDetectionService {
  AnomalyDetectionService._();

  /// Detects category spikes scoped strictly to the current evaluation month.
  ///
  /// Prevents comparing cumulative lifetime spending against a monthly baseline.
  /// Transactions are filtered to match [referenceTime]'s year and month.
  ///
  /// A spike qualifies if:
  /// 1. Baseline is positive (> 0).
  /// 2. Current period spending is >= [threshold] * baseline (default 1.8x).
  /// 3. The absolute increase is at least [minSpendDelta] (default 300) to prevent
  ///    noisy alerts on tiny transactions (e.g. ₹10 -> ₹20).
  static List<CategorySpike> detectSpikes(
    List<TransactionRecord> transactions,
    Map<String, double> baseline, {
    DateTime? now,
    double threshold = 1.8,
    double minSpendDelta = 300.0,
  }) {
    final referenceTime = now ?? DateTime.now();
    final current = <String, double>{};

    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      // Strictly scope to the current calendar month
      if (t.date.year != referenceTime.year ||
          t.date.month != referenceTime.month) {
        continue;
      }
      current[t.categoryId] = (current[t.categoryId] ?? 0) + t.amount;
    }

    final spikes = <CategorySpike>[];
    for (final entry in current.entries) {
      final base = baseline[entry.key] ?? 0;
      if (base <= 0) continue;
      final ratio = entry.value / base;
      final delta = entry.value - base;

      if (ratio >= threshold && delta >= minSpendDelta) {
        spikes.add(
          CategorySpike(
            categoryId: entry.key,
            currentSpend: entry.value,
            baselineSpend: base,
            ratio: ratio,
          ),
        );
      }
    }
    return spikes;
  }

  /// Backward-compatible API returning a Map of categoryId -> ratio.
  static Map<String, double> detectCategorySpikes(
    List<TransactionRecord> transactions,
    Map<String, double> baseline, {
    DateTime? now,
    double threshold = 1.8,
    double minSpendDelta = 0.0, // 0 for compatibility with existing unit tests
  }) {
    final spikes = detectSpikes(
      transactions,
      baseline,
      now: now,
      threshold: threshold,
      minSpendDelta: minSpendDelta,
    );

    return {for (final s in spikes) s.categoryId: s.ratio};
  }
}
