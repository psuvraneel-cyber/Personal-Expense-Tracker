import 'package:flutter/foundation.dart';

/// Risk level classification for cashflow stability over the forecast window.
enum CashflowRiskLevel {
  healthy('Healthy'),
  watch('Watch'),
  atRisk('At Risk'),
  deficitExpected('Deficit Expected'),
  insufficientData('Insufficient Data');

  final String displayName;
  const CashflowRiskLevel(this.displayName);
}

/// Confidence rating for projection reliability based on historical data depth.
enum CashflowConfidence {
  high('High Confidence'),
  moderate('Moderate Confidence'),
  low('Low Confidence'),
  insufficientData('Insufficient Data');

  final String displayName;
  const CashflowConfidence(this.displayName);
}

/// A significant financial event on the cashflow forecast timeline.
@immutable
class CashflowEvent {
  final DateTime date;
  final String title;
  final double amount;
  final bool isIncome;
  final String? categoryId;
  final String? billId;

  const CashflowEvent({
    required this.date,
    required this.title,
    required this.amount,
    required this.isIncome,
    this.categoryId,
    this.billId,
  });
}

/// Canonical domain model representing a comprehensive cashflow projection.
@immutable
class CashflowForecast {
  /// Reference starting date of the forecast.
  final DateTime referenceDate;

  /// Horizon window in days (e.g. 14, 30, 60, 90).
  final int horizonDays;

  /// Balance at reference date (sum of canonical ledger transactions or linked accounts).
  final double startingBalance;

  /// Projected balance at the end of the forecast horizon.
  final double projectedEndingBalance;

  /// Recommended daily safe spending limit that preserves safety buffer and goal reserves.
  final double safeToSpend;

  /// Total spendable headroom across the full horizon before breaching safety buffer.
  final double totalSafeToSpend;

  /// Total expected income over the forecast horizon.
  final double expectedIncome;

  /// Total expected baseline variable expenses over the forecast horizon.
  final double expectedVariableExpenses;

  /// Total upcoming bills and recurring commitments in the forecast horizon.
  final double expectedBills;

  /// Amount reserved for savings goals over the forecast horizon.
  final double expectedGoalReserves;

  /// Configured minimum safety buffer floor (default: ₹5,000).
  final double safetyBuffer;

  /// Net daily burn rate (daily variable + daily bills - daily income).
  final double dailyBurnRate;

  /// Projected days of runway before balance reaches zero.
  /// Null if cashflow is positive.
  final int? runwayDays;

  /// Whether current net cashflow is positive (income >= expenses + bills).
  final bool isCashflowPositive;

  /// Monthly cashflow surplus (positive) or deficit (negative).
  final double monthlyNetCashflow;

  /// Lowest projected balance during the horizon.
  final double lowestProjectedBalance;

  /// Date when the lowest balance is reached.
  final DateTime lowestProjectedDate;

  /// First date when balance dips below zero (null if no deficit).
  final DateTime? firstDeficitDate;

  /// Primary recurring commitment or event driving the lowest point.
  final String? troughDriver;

  /// Overall cashflow risk classification.
  final CashflowRiskLevel riskLevel;

  /// Projection confidence grade.
  final CashflowConfidence confidence;

  /// Explanations for confidence rating and assumptions.
  final List<String> confidenceReasons;

  /// Significant bills, income credits, or deficit events across the horizon.
  final List<CashflowEvent> majorEvents;

  /// Day-by-day projected trajectory.
  final List<CashflowPoint> dailyPoints;

  /// True when less than 7 days of transaction history are available.
  final bool hasInsufficientData;

  /// True when recorded expenses exceed recorded income, yielding a negative baseline.
  final bool hasNegativeStartingBalance;

  /// Optional scenario forecast overlay when What-If simulation is active.
  final CashflowForecast? scenarioOverlay;

  const CashflowForecast({
    required this.referenceDate,
    this.horizonDays = 30,
    required this.startingBalance,
    required this.projectedEndingBalance,
    required this.safeToSpend,
    this.totalSafeToSpend = 0.0,
    this.expectedIncome = 0.0,
    this.expectedVariableExpenses = 0.0,
    this.expectedBills = 0.0,
    this.expectedGoalReserves = 0.0,
    this.safetyBuffer = 5000.0,
    this.dailyBurnRate = 0.0,
    this.runwayDays,
    this.isCashflowPositive = false,
    this.monthlyNetCashflow = 0.0,
    required this.lowestProjectedBalance,
    required this.lowestProjectedDate,
    this.firstDeficitDate,
    this.troughDriver,
    this.riskLevel = CashflowRiskLevel.healthy,
    this.confidence = CashflowConfidence.moderate,
    this.confidenceReasons = const [],
    this.majorEvents = const [],
    required this.dailyPoints,
    this.hasInsufficientData = false,
    this.hasNegativeStartingBalance = false,
    this.scenarioOverlay,
  });

  /// Alias for startingBalance for domain alignment.
  double get openingBalance => startingBalance;

  /// Effective observation window lookback in days.
  int get lookbackDays => 60;
}

/// A single day's projected balance and event breakdown.
@immutable
class CashflowPoint {
  final DateTime date;
  final double balance;
  final double netChange;
  final double incomeAmount;
  final double variableExpenseAmount;
  final double billsAmount;
  final List<String> billNames;
  final bool isLowestPoint;
  final bool isFirstDeficit;
  final double? scenarioBalance;

  const CashflowPoint({
    required this.date,
    required this.balance,
    this.netChange = 0.0,
    this.incomeAmount = 0.0,
    this.variableExpenseAmount = 0.0,
    this.billsAmount = 0.0,
    this.billNames = const [],
    this.isLowestPoint = false,
    this.isFirstDeficit = false,
    this.scenarioBalance,
  });

  bool get isSalaryDeposit => incomeAmount > 0;
  bool get isRecurringBillDue => billsAmount > 0;
  String? get eventTitle => billNames.isNotEmpty
      ? billNames.join(', ')
      : (incomeAmount > 0 ? 'Expected Income' : null);
}
