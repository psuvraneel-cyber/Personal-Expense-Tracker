class CashflowForecast {
  final double startingBalance;
  final double projectedEndingBalance;
  final double safeToSpend;
  final List<CashflowPoint> dailyPoints;

  /// True when less than 7 days of transaction history are available,
  /// meaning projections may be unreliable.
  final bool hasInsufficientData;

  /// True when recorded expenses exceed recorded income, yielding a negative baseline.
  final bool hasNegativeStartingBalance;

  CashflowForecast({
    required this.startingBalance,
    required this.projectedEndingBalance,
    required this.safeToSpend,
    required this.dailyPoints,
    this.hasInsufficientData = false,
    this.hasNegativeStartingBalance = false,
  });
}

class CashflowPoint {
  final DateTime date;
  final double balance;

  CashflowPoint({required this.date, required this.balance});
}
