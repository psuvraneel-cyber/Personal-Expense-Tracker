import 'package:flutter/foundation.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';

// Optional premium models — null-safe so free tier doesn't need them.
// ignore: avoid_classes_with_only_static_members
import 'package:pet/premium/models/saving_goal.dart';

/// A single dimension of the Spend Health Score.
@immutable
class HealthDimension {
  final String label;
  final String emoji;
  final int score; // 0–100 (per dimension)
  final String insight;

  const HealthDimension({
    required this.label,
    required this.emoji,
    required this.score,
    required this.insight,
  });
}

/// Result returned by [SpendHealthService.calculate].
///
/// The canonical spend health result used by **both** the home page
/// card and the premium hub detailed banner.
@immutable
class SpendHealthResult {
  /// Composite score 0–100.
  final int totalScore;

  /// Per-dimension breakdown (4 dimensions).
  final List<HealthDimension> dimensions;

  /// Actionable insights (max 3).
  final List<String> insights;

  /// Letter grade (A+, A, B, C, D).
  final String grade;

  /// One-line tip based on the weakest dimension.
  final String tip;

  const SpendHealthResult({
    required this.totalScore,
    required this.dimensions,
    required this.insights,
    required this.grade,
    required this.tip,
  });
}

/// Computes a 0–100 "Spend Health Score" from the user's financial data.
///
/// ## Pillars
///
/// | #  | Dimension         | Weight | Data source                    |
/// |----|-------------------|--------|--------------------------------|
/// | 1  | Budget Adherence  | 30%    | category budgets vs spending   |
/// | 2  | Savings Progress  | 25%    | savings goals, income-to-save  |
/// | 3  | Consistency       | 20%    | days with transactions tracked |
/// | 4  | Spend Discipline  | 25%    | impulse category ratio         |
///
/// Free-tier callers may omit `goals` and `bills` — the service
/// gracefully defaults to neutral scores for those data points.
class SpendHealthService {
  SpendHealthService._();
  static final SpendHealthService instance = SpendHealthService._();

  double _safeRatio(double num, double den) {
    if (den <= 0 || num.isNaN || den.isNaN) return 0.0;
    final r = num / den;
    return r.isFinite ? r : 0.0;
  }

  /// Calculate the spend health score from this month's data.
  ///
  /// All parameters are optional except [transactions].
  /// Missing data yields a neutral mid-range score so users
  /// aren't penalised for features they haven't set up yet.
  SpendHealthResult calculate({
    required List<TransactionRecord> transactions,
    Map<String, double> categoryBudgets = const {},
    List<SavingGoal> goals = const [],
    Map<String, double>? budgetSpent,
  }) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthTxns = transactions.where((t) {
      return t.date.isAfter(monthStart.subtract(const Duration(days: 1)));
    }).toList();

    final dims = <HealthDimension>[];
    final insights = <String>[];

    // ── 1. Budget Adherence (30%) ─────────────────────────────────────
    final budgetDim = _budgetAdherence(
      monthTxns,
      categoryBudgets,
      budgetSpent,
      insights,
    );
    dims.add(budgetDim);

    // ── 2. Savings Progress (25%) ─────────────────────────────────────
    final savingsDim = _savingsProgress(monthTxns, goals, insights);
    dims.add(savingsDim);

    // ── 3. Consistency (20%) ──────────────────────────────────────────
    final consistencyDim = _consistency(monthTxns, now, insights);
    dims.add(consistencyDim);

    // ── 4. Spend Discipline (25%) ─────────────────────────────────────
    final disciplineDim = _spendDiscipline(monthTxns, insights);
    dims.add(disciplineDim);

    // ── Composite (weighted) ──────────────────────────────────────────
    const weights = [0.30, 0.25, 0.20, 0.25];
    final composite = dims.asMap().entries.fold(
      0.0,
      (sum, e) => sum + e.value.score * weights[e.key],
    );
    final total = composite.round().clamp(0, 100);
    final grade = _grade(total);

    // Find weakest pillar for the tip
    final weakest = dims.reduce((a, b) => a.score < b.score ? a : b);
    final tip = _tip(weakest.label, total);

    return SpendHealthResult(
      totalScore: total,
      dimensions: dims,
      insights: insights.take(3).toList(),
      grade: grade,
      tip: tip,
    );
  }

  // ── Pillar 1: Budget Adherence ──────────────────────────────────────

  HealthDimension _budgetAdherence(
    List<TransactionRecord> txns,
    Map<String, double> catBudgets,
    Map<String, double>? precomputedSpent,
    List<String> insights,
  ) {
    if (catBudgets.isEmpty) {
      return const HealthDimension(
        label: 'Budget Adherence',
        emoji: '🎯',
        score: 50,
        insight: 'No budgets set — add budgets for a better score',
      );
    }

    // Compute spending per category from transactions if not provided.
    final catSpend = precomputedSpent ?? <String, double>{};
    if (precomputedSpent == null) {
      for (final t in txns.where((t) => t.type == TransactionType.expense)) {
        catSpend[t.categoryId] = (catSpend[t.categoryId] ?? 0) + t.amount;
      }
    }

    double totalLimit = 0;
    double overBudget = 0;
    int within = 0;
    int total = 0;
    for (final entry in catBudgets.entries) {
      if (entry.value <= 0) continue;
      total++;
      totalLimit += entry.value;
      final spent = catSpend[entry.key] ?? 0;
      if (spent <= entry.value) {
        within++;
      } else {
        overBudget += (spent - entry.value);
      }
    }

    if (total == 0) {
      return const HealthDimension(
        label: 'Budget Adherence',
        emoji: '🎯',
        score: 50,
        insight: 'No budgets set',
      );
    }

    final overRatio = _safeRatio(overBudget, totalLimit);
    final score = ((1 - overRatio.clamp(0.0, 1.0)) * 100).round().clamp(0, 100);

    if (overRatio > 0.2) {
      insights.add(
        'You\'re over-budget in ${total - within} categor${(total - within) > 1 ? 'ies' : 'y'} — try cutting back before month-end.',
      );
    }

    return HealthDimension(
      label: 'Budget Adherence',
      emoji: '🎯',
      score: score,
      insight: score >= 80
          ? 'Staying within your limits!'
          : '$within of $total categories within budget',
    );
  }

  // ── Pillar 2: Savings Progress ──────────────────────────────────────

  HealthDimension _savingsProgress(
    List<TransactionRecord> txns,
    List<SavingGoal> goals,
    List<String> insights,
  ) {
    double income = 0;
    double expense = 0;
    for (final t in txns) {
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else if (t.type == TransactionType.expense) {
        expense += t.amount;
      }
    }

    int score;
    String insightText;

    if (goals.isNotEmpty) {
      // Use goals-based progress
      final totalTarget = goals.fold(0.0, (s, g) => s + g.targetAmount);
      final totalSaved = goals.fold(0.0, (s, g) => s + g.currentAmount);
      final goalProgress = _safeRatio(totalSaved, totalTarget);
      score = (goalProgress.clamp(0.0, 1.0) * 100).round().clamp(0, 100);
      insightText =
          '${(goalProgress.clamp(0.0, 1.0) * 100).round()}% of savings target reached';

      if (income > 0) {
        final savingsRate = _safeRatio(totalSaved, income);
        if (savingsRate < 0.1) {
          insights.add(
            'Try saving at least 10% of your income — currently at ${(savingsRate * 100).round()}%.',
          );
        }
      }
    } else if (income > 0) {
      // Fall back to income-vs-expense savings rate
      final rate = _safeRatio(income - expense, income);
      // 20%+ saving → 100%, 0% → 0%
      score = (rate.clamp(0.0, 0.3) / 0.3 * 100).round().clamp(0, 100);
      insightText = rate > 0
          ? 'Saving ${(rate * 100).round()}% of income'
          : 'Spending exceeds income';

      if (rate < 0.1) {
        insights.add(
          'Try the 50-30-20 rule: 50% needs, 30% wants, 20% savings.',
        );
      }
    } else {
      score = 50; // Neutral — no income data
      insightText = 'Add income transactions for better insights';
      insights.add('Add income transactions to unlock savings insights.');
    }

    return HealthDimension(
      label: 'Savings Progress',
      emoji: '🏦',
      score: score,
      insight: insightText,
    );
  }

  // ── Pillar 3: Consistency ───────────────────────────────────────────

  HealthDimension _consistency(
    List<TransactionRecord> txns,
    DateTime now,
    List<String> insights,
  ) {
    if (txns.isEmpty) {
      insights.add(
        'Log transactions daily for better insights. Even ₹10 chai counts!',
      );
      return const HealthDimension(
        label: 'Consistency',
        emoji: '📊',
        score: 0,
        insight: 'No transactions this month',
      );
    }

    final daysWithTxn = <int>{};
    for (final t in txns) {
      daysWithTxn.add(t.date.day);
    }
    final daysSoFar = now.day > 0 ? now.day : 1;
    // If user tracked on >60% of days so far, full marks
    final ratio = _safeRatio(
      daysWithTxn.length.toDouble(),
      daysSoFar.toDouble(),
    );
    final score = (ratio.clamp(0.0, 0.6) / 0.6 * 100).round().clamp(0, 100);

    if (ratio < 0.4) {
      insights.add(
        'You\'ve logged transactions on ${daysWithTxn.length} of $daysSoFar days. Try logging daily!',
      );
    }

    return HealthDimension(
      label: 'Consistency',
      emoji: '📊',
      score: score,
      insight: 'Tracked ${daysWithTxn.length} of $daysSoFar days',
    );
  }

  // ── Pillar 4: Spend Discipline ──────────────────────────────────────

  HealthDimension _spendDiscipline(
    List<TransactionRecord> txns,
    List<String> insights,
  ) {
    final expenses = txns
        .where((t) => t.type == TransactionType.expense)
        .toList();
    if (expenses.isEmpty) {
      return const HealthDimension(
        label: 'Spend Discipline',
        emoji: '🧘',
        score: 50,
        insight: 'No expense data yet',
      );
    }

    const impulseIds = [
      'food',
      'entertainment',
      'shopping',
      'dining',
      'cat_food',
      'cat_entertainment',
      'cat_shopping',
    ];
    double totalExpense = 0;
    double impulseExpense = 0;
    for (final t in expenses) {
      totalExpense += t.amount;
      if (impulseIds.any((c) => t.categoryId.toLowerCase().contains(c))) {
        impulseExpense += t.amount;
      }
    }

    if (totalExpense == 0) {
      return const HealthDimension(
        label: 'Spend Discipline',
        emoji: '🧘',
        score: 50,
        insight: 'No expense data',
      );
    }

    final impulseRatio = _safeRatio(impulseExpense, totalExpense);
    final score = (100 * (1 - (impulseRatio.clamp(0.0, 0.6) / 0.6)))
        .round()
        .clamp(0, 100);

    if (impulseRatio > 0.4) {
      insights.add(
        'You\'re spending ${(impulseRatio * 100).round()}% on discretionary categories — consider cutting back.',
      );
    }

    return HealthDimension(
      label: 'Spend Discipline',
      emoji: '🧘',
      score: score,
      insight: impulseRatio < 0.25
          ? 'Great spending discipline!'
          : '${(impulseRatio * 100).round()}% on discretionary items',
    );
  }

  // ── Grading ─────────────────────────────────────────────────────────

  String _grade(int score) {
    if (score >= 85) return 'A+';
    if (score >= 70) return 'A';
    if (score >= 55) return 'B';
    if (score >= 40) return 'C';
    return 'D';
  }

  String _tip(String weakest, int totalScore) {
    switch (weakest) {
      case 'Budget Adherence':
        return 'You exceeded some budgets this month. Consider adjusting them or cutting back.';
      case 'Savings Progress':
        return 'Try the 50-30-20 rule: 50% needs, 30% wants, 20% savings.';
      case 'Consistency':
        return 'Log transactions daily for better insights. Even ₹10 chai counts!';
      case 'Spend Discipline':
        return 'Your spending is concentrated in discretionary categories. Diversifying can help.';
      default:
        return 'Keep tracking consistently for a better score!';
    }
  }
}
