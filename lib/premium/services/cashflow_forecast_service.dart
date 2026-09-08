import 'dart:math';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/services/recurrence_calculator.dart';

/// Single authoritative engine for cashflow forecasting across P.E.T.
///
/// Used by CashflowScreen, AlertEvaluator, AlertEvaluationCoordinator,
/// What-If Simulator, and the AI Copilot.
class CashflowForecastService {
  CashflowForecastService._();

  /// Default historical observation window (in days).
  static const int defaultLookbackDays = 60;

  /// Default projection horizon (in days).
  static const int defaultHorizonDays = 30;

  /// Supported projection horizons.
  static const List<int> supportedHorizons = [14, 30, 60, 90];

  /// Default safety buffer floor in rupees.
  static const double defaultSafetyBuffer = 5000.0;

  // ── Memoization Cache ──────────────────────────────────────────────────────
  static String _lastCacheKey = '';
  static CashflowForecast? _cachedForecast;

  /// Clears the memoization cache.
  static void clearCache() {
    _lastCacheKey = '';
    _cachedForecast = null;
  }

  /// Calculates the canonical cashflow forecast for the given dataset.
  static CashflowForecast forecast(
    List<TransactionRecord> transactions, {
    String? userId,
    List<RecurringPayment>? confirmedBills,
    int days = defaultHorizonDays,
    DateTime? referenceDate,
    double? openingBalanceOverride,
    double goalReserves = 0.0,
    double safetyBuffer = defaultSafetyBuffer,
    int lookbackDays = defaultLookbackDays,
  }) {
    final now = referenceDate ?? DateTime.now();

    // Cache lookup key based on hash of transactions and inputs (Defect 6 Fix)
    int txnsHash = 0;
    for (final t in transactions) {
      txnsHash = Object.hash(
        txnsHash,
        t.id,
        t.amount,
        t.type.name,
        t.date.millisecondsSinceEpoch,
        t.isRecurring,
        t.merchantName,
        t.recurringRuleId,
      );
    }
    int billsHash = 0;
    if (confirmedBills != null) {
      for (final b in confirmedBills) {
        billsHash = Object.hash(
          billsHash,
          b.id,
          b.merchantName,
          b.amount,
          b.frequency,
          b.nextDueAt.millisecondsSinceEpoch,
          b.status.name,
          b.categoryId,
        );
      }
    }

    final dateKey = referenceDate != null
        ? 'ref_${referenceDate.millisecondsSinceEpoch}'
        : 'live_${now.year}-${now.month}-${now.day}';

    final cacheKey = '${userId ?? "anon"}_${txnsHash}_${billsHash}_${days}_${lookbackDays}_'
        '${dateKey}_'
        '${openingBalanceOverride ?? "none"}_'
        '${goalReserves}_'
        '$safetyBuffer';

    if (_lastCacheKey == cacheKey && _cachedForecast != null) {
      return _cachedForecast!;
    }

    // ── 1. Filter out future-dated transactions ──────────────────────────────
    final pastTransactions = transactions
        .where((t) => !t.date.isAfter(now))
        .toList();

    // ── 2. Determine Starting Balance ────────────────────────────────────────
    double balance = openingBalanceOverride ?? 0.0;
    if (openingBalanceOverride == null) {
      for (final t in pastTransactions) {
        if (t.type == TransactionType.income) {
          balance += t.amount;
        } else if (t.type == TransactionType.expense) {
          balance -= t.amount;
        }
      }
    }
    final hasNegativeStartingBalance = balance < 0;

    // ── 3. Unified Rolling Baseline Window (CF-01 & CF-02 Fix) ───────────────
    final baselineStart = now.subtract(Duration(days: lookbackDays));
    final baselineTransactions = pastTransactions
        .where((t) => !t.date.isBefore(baselineStart))
        .toList();

    int effectiveDays = lookbackDays;
    if (pastTransactions.isNotEmpty) {
      final dates = pastTransactions.map((t) => t.date).toList()..sort();
      final totalHistoricalSpan = now.difference(dates.first).inDays + 1;
      effectiveDays = min(lookbackDays, max(1, totalHistoricalSpan));
    } else {
      effectiveDays = 1;
    }

    final double baselineIncome = baselineTransactions
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);

    final avgDailyIncome = baselineIncome / effectiveDays;

    final hasInsufficientData = pastTransactions.isEmpty || effectiveDays < 7;

    // ── 4. Process Active & Overdue Bills (CF-04 & Defect 1 Fix) ─────────────
    final activeBills = (confirmedBills ?? [])
        .where((b) => b.status == RecurringStatus.confirmed)
        .toList();

    final billMerchantNames = activeBills
        .map((b) => b.merchantName.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();

    // Isolate genuine variable expenses from history without cannibalization (Defect 1 Fix).
    // Transactions representing recurring commitments (marked isRecurring, having a recurringRuleId,
    // or matching an active confirmed bill's merchant) are excluded from variable baseline to prevent
    // double counting, while unrelated genuine living expenses (food, transport, etc.) are fully preserved.
    final double baselineVariableExpense = baselineTransactions
        .where((t) => t.type == TransactionType.expense)
        .where((t) {
          if (t.isRecurring) return false;
          if (t.recurringRuleId != null && t.recurringRuleId!.isNotEmpty) return false;
          if (t.merchantName != null &&
              billMerchantNames.contains(t.merchantName!.trim().toLowerCase())) {
            return false;
          }
          return true;
        })
        .fold(0.0, (sum, t) => sum + t.amount);

    final variableDailyExpense = baselineVariableExpense / effectiveDays;

    final recurringMonthlyBurn = activeBills.fold(
      0.0,
      (sum, b) => sum + b.monthlyEquivalentAmount,
    );
    final recurringDailyBurn = recurringMonthlyBurn / 30.0;

    // Canonical horizon boundary: [referenceDate, referenceDate + H) (Defect 5 Fix)
    final todayFloor = DateTime(now.year, now.month, now.day);
    final horizonEndExclusive = DateTime(now.year, now.month, now.day + days);

    final billDeductionsByDate = <String, double>{};
    final billNamesByDate = <String, List<String>>{};
    final majorEvents = <CashflowEvent>[];

    for (final bill in activeBills) {
      // Overdue bill handling: If nextDueAt is before today and unpaid, treat as due TODAY
      var occ = bill.nextDueAt;
      if (occ.isBefore(todayFloor)) {
        final todayKey = '${todayFloor.year}-${todayFloor.month}-${todayFloor.day}';
        billDeductionsByDate[todayKey] =
            (billDeductionsByDate[todayKey] ?? 0.0) + bill.amount;
        billNamesByDate.putIfAbsent(todayKey, () => []).add('${bill.merchantName} (Overdue)');

        majorEvents.add(CashflowEvent(
          date: todayFloor,
          title: '${bill.merchantName} (Overdue)',
          amount: bill.amount,
          isIncome: false,
          categoryId: bill.categoryId,
          billId: bill.id,
        ));

        // Advance to next future occurrence after today
        occ = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: bill.nextDueAt,
          currentOccurrence: todayFloor,
          frequency: bill.frequencyEnum,
        );
      }

      var safety = 0;
      while (occ.isBefore(horizonEndExclusive) && safety < 100) {
        safety++;
        if (!occ.isBefore(todayFloor)) {
          final key = '${occ.year}-${occ.month}-${occ.day}';
          billDeductionsByDate[key] = (billDeductionsByDate[key] ?? 0.0) + bill.amount;
          billNamesByDate.putIfAbsent(key, () => []).add(bill.merchantName);

          majorEvents.add(CashflowEvent(
            date: occ,
            title: bill.merchantName,
            amount: bill.amount,
            isIncome: false,
            categoryId: bill.categoryId,
            billId: bill.id,
          ));
        }

        occ = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: bill.nextDueAt,
          currentOccurrence: occ,
          frequency: bill.frequencyEnum,
        );
      }
    }

    // Sort major events chronologically
    majorEvents.sort((a, b) => a.date.compareTo(b.date));

    // ── 5. Project Daily Trajectory & Troughs ─────────────────────────────────
    final dailyPoints = <CashflowPoint>[];
    double rollingBalance = balance;
    double lowestBalance = balance;
    DateTime lowestDate = now;
    DateTime? firstDeficitDate;
    String? troughDriver;

    double totalBillsInHorizon = 0.0;

    for (var i = 0; i < days; i++) {
      final date = DateTime(now.year, now.month, now.day + i);
      final dateKey = '${date.year}-${date.month}-${date.day}';

      final billsDueToday = billDeductionsByDate[dateKey] ?? 0.0;
      final billNamesToday = billNamesByDate[dateKey] ?? const <String>[];
      totalBillsInHorizon += billsDueToday;

      final netDailyChange = (avgDailyIncome - variableDailyExpense) - billsDueToday;
      rollingBalance += netDailyChange;

      if (rollingBalance < lowestBalance) {
        lowestBalance = rollingBalance;
        lowestDate = date;
        if (billNamesToday.isNotEmpty) {
          troughDriver = '${billNamesToday.first} (₹${billsDueToday.toStringAsFixed(0)})';
        }
      }

      if (rollingBalance < 0 && firstDeficitDate == null) {
        firstDeficitDate = date;
      }

      dailyPoints.add(CashflowPoint(
        date: date,
        balance: rollingBalance,
        netChange: netDailyChange,
        incomeAmount: avgDailyIncome,
        variableExpenseAmount: variableDailyExpense,
        billsAmount: billsDueToday,
        billNames: billNamesToday,
        isLowestPoint: false, // will update post-loop
        isFirstDeficit: firstDeficitDate != null &&
            firstDeficitDate.year == date.year &&
            firstDeficitDate.month == date.month &&
            firstDeficitDate.day == date.day,
      ));
    }

    // Flag the lowest point in dailyPoints
    for (var i = 0; i < dailyPoints.length; i++) {
      if (dailyPoints[i].date.year == lowestDate.year &&
          dailyPoints[i].date.month == lowestDate.month &&
          dailyPoints[i].date.day == lowestDate.day) {
        dailyPoints[i] = CashflowPoint(
          date: dailyPoints[i].date,
          balance: dailyPoints[i].balance,
          netChange: dailyPoints[i].netChange,
          incomeAmount: dailyPoints[i].incomeAmount,
          variableExpenseAmount: dailyPoints[i].variableExpenseAmount,
          billsAmount: dailyPoints[i].billsAmount,
          billNames: dailyPoints[i].billNames,
          isLowestPoint: true,
          isFirstDeficit: dailyPoints[i].isFirstDeficit,
        );
        break;
      }
    }

    // ── 6. Rolling Safe-to-Spend Model (CF-03 Fix) ────────────────────────────
    // Safe-to-spend is path-dependent: preserves lowest projected balance >= safetyBuffer + goalReserves
    final double spendableHeadroom =
        (lowestBalance - safetyBuffer - goalReserves).clamp(0.0, double.infinity);
    final double safeToSpend = (spendableHeadroom > 0 && days > 0)
        ? spendableHeadroom / days
        : 0.0;

    // ── 7. Runway & Daily Burn Calculation (CF-12 Fix) ───────────────────────
    final double totalDailyExpense = variableDailyExpense + recurringDailyBurn;
    final double netDailyBurn = totalDailyExpense - avgDailyIncome;
    final double monthlyNetCashflow = (avgDailyIncome - totalDailyExpense) * 30.0;
    final bool isCashflowPositive = netDailyBurn <= 0;

    int? runwayDays;
    if (isCashflowPositive && balance >= 0) {
      runwayDays = null; // Infinite / Cashflow Positive
    } else if (firstDeficitDate != null) {
      runwayDays = max(0, firstDeficitDate.difference(now).inDays);
    } else if (netDailyBurn > 0 && balance > 0) {
      runwayDays = max(0, (balance / netDailyBurn).floor());
    } else {
      runwayDays = 0;
    }

    // ── 8. Risk Level & Confidence Evaluation (CF-05 Fix) ───────────────────
    final CashflowRiskLevel riskLevel;
    if (hasInsufficientData) {
      riskLevel = CashflowRiskLevel.insufficientData;
    } else if (lowestBalance < 0 || hasNegativeStartingBalance) {
      riskLevel = CashflowRiskLevel.deficitExpected;
    } else if (lowestBalance < safetyBuffer) {
      riskLevel = CashflowRiskLevel.atRisk;
    } else if (netDailyBurn > 0) {
      riskLevel = CashflowRiskLevel.watch;
    } else {
      riskLevel = CashflowRiskLevel.healthy;
    }

    final CashflowConfidence confidence;
    final confidenceReasons = <String>[];

    if (hasInsufficientData) {
      confidence = CashflowConfidence.insufficientData;
      confidenceReasons.add('Less than 7 days of recorded data.');
    } else if (effectiveDays < 21) {
      confidence = CashflowConfidence.low;
      confidenceReasons.add('Only $effectiveDays days of history — projections are tentative.');
    } else if (effectiveDays < 45) {
      confidence = CashflowConfidence.moderate;
      confidenceReasons.add('Based on $effectiveDays days of historical activity.');
    } else {
      confidence = CashflowConfidence.high;
      confidenceReasons.add('Based on $effectiveDays days of solid historical baseline.');
    }

    if (activeBills.isNotEmpty) {
      confidenceReasons.add('${activeBills.length} confirmed recurring commitments included.');
    }
    if (goalReserves > 0) {
      confidenceReasons.add('Protected ₹${goalReserves.toStringAsFixed(0)} goal reserves.');
    }

    final endingBalance =
        dailyPoints.isNotEmpty ? dailyPoints.last.balance : balance;

    final result = CashflowForecast(
      referenceDate: now,
      horizonDays: days,
      startingBalance: balance,
      projectedEndingBalance: endingBalance,
      safeToSpend: safeToSpend,
      totalSafeToSpend: spendableHeadroom,
      expectedIncome: avgDailyIncome * days,
      expectedVariableExpenses: variableDailyExpense * days,
      expectedBills: totalBillsInHorizon,
      expectedGoalReserves: goalReserves,
      safetyBuffer: safetyBuffer,
      dailyBurnRate: netDailyBurn,
      runwayDays: runwayDays,
      isCashflowPositive: isCashflowPositive,
      monthlyNetCashflow: monthlyNetCashflow,
      lowestProjectedBalance: lowestBalance,
      lowestProjectedDate: lowestDate,
      firstDeficitDate: firstDeficitDate,
      troughDriver: troughDriver,
      riskLevel: riskLevel,
      confidence: confidence,
      confidenceReasons: confidenceReasons,
      majorEvents: majorEvents,
      dailyPoints: dailyPoints,
      hasInsufficientData: hasInsufficientData,
      hasNegativeStartingBalance: hasNegativeStartingBalance,
    );

    _lastCacheKey = cacheKey;
    _cachedForecast = result;
    return result;
  }

  /// Simulates a hypothetical one-off expenditure (What-If purchase).
  ///
  /// Does NOT mutate canonical database transactions. Returns a scenario overlay
  /// that can be compared against the base forecast.
  static CashflowForecast simulateExpense(
    CashflowForecast base, {
    required double amount,
    required DateTime date,
    String title = 'Simulated Purchase',
  }) {
    if (amount <= 0) return base;

    final horizonDays = base.horizonDays;
    final now = base.referenceDate;

    // Days offset from today
    final dayOffset = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (dayOffset < 0 || dayOffset >= horizonDays) {
      return base;
    }

    final scenarioPoints = <CashflowPoint>[];
    double scenarioLowest = double.infinity;
    DateTime scenarioLowestDate = base.lowestProjectedDate;
    DateTime? scenarioFirstDeficit;

    for (var i = 0; i < base.dailyPoints.length; i++) {
      final p = base.dailyPoints[i];
      final isAfterPurchase = i >= dayOffset;
      final scenarioBalance = isAfterPurchase ? p.balance - amount : p.balance;

      if (scenarioBalance < scenarioLowest) {
        scenarioLowest = scenarioBalance;
        scenarioLowestDate = p.date;
      }

      if (scenarioBalance < 0 && scenarioFirstDeficit == null) {
        scenarioFirstDeficit = p.date;
      }

      scenarioPoints.add(CashflowPoint(
        date: p.date,
        balance: p.balance,
        netChange: p.netChange,
        incomeAmount: p.incomeAmount,
        variableExpenseAmount: p.variableExpenseAmount,
        billsAmount: p.billsAmount,
        billNames: p.billNames,
        isLowestPoint: false,
        isFirstDeficit: false,
        scenarioBalance: scenarioBalance,
      ));
    }

    final double scenarioHeadroom =
        (scenarioLowest - base.safetyBuffer - base.expectedGoalReserves)
            .clamp(0.0, double.infinity);
    final double scenarioSafeToSpend =
        (scenarioHeadroom > 0 && horizonDays > 0) ? scenarioHeadroom / horizonDays : 0.0;

    final CashflowRiskLevel scenarioRisk;
    if (scenarioLowest < 0) {
      scenarioRisk = CashflowRiskLevel.deficitExpected;
    } else if (scenarioLowest < base.safetyBuffer) {
      scenarioRisk = CashflowRiskLevel.atRisk;
    } else {
      scenarioRisk = CashflowRiskLevel.healthy;
    }

    final scenarioOverlay = CashflowForecast(
      referenceDate: base.referenceDate,
      horizonDays: base.horizonDays,
      startingBalance: base.startingBalance,
      projectedEndingBalance: base.projectedEndingBalance - amount,
      safeToSpend: scenarioSafeToSpend,
      totalSafeToSpend: scenarioHeadroom,
      expectedIncome: base.expectedIncome,
      expectedVariableExpenses: base.expectedVariableExpenses,
      expectedBills: base.expectedBills + amount,
      expectedGoalReserves: base.expectedGoalReserves,
      safetyBuffer: base.safetyBuffer,
      dailyBurnRate: base.dailyBurnRate,
      runwayDays: scenarioFirstDeficit != null
          ? max(0, scenarioFirstDeficit.difference(now).inDays)
          : base.runwayDays,
      isCashflowPositive: base.isCashflowPositive,
      monthlyNetCashflow: base.monthlyNetCashflow,
      lowestProjectedBalance: scenarioLowest,
      lowestProjectedDate: scenarioLowestDate,
      firstDeficitDate: scenarioFirstDeficit,
      troughDriver: scenarioLowestDate == date ? title : base.troughDriver,
      riskLevel: scenarioRisk,
      confidence: base.confidence,
      confidenceReasons: base.confidenceReasons,
      majorEvents: [
        ...base.majorEvents,
        CashflowEvent(
          date: date,
          title: title,
          amount: amount,
          isIncome: false,
        ),
      ]..sort((a, b) => a.date.compareTo(b.date)),
      dailyPoints: scenarioPoints,
      hasInsufficientData: base.hasInsufficientData,
      hasNegativeStartingBalance: base.hasNegativeStartingBalance,
    );

    return scenarioOverlay;
  }
}
