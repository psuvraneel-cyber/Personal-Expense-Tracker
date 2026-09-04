import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/premium/widgets/premium_gate.dart';
import 'package:pet/data/models/transaction.dart';

import 'package:pet/premium/providers/recurring_provider.dart';

class CashflowScreen extends StatefulWidget {
  const CashflowScreen({super.key});

  @override
  State<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends State<CashflowScreen> {
  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecurringProvider>().load();
    });
  }

  String _computeIncomeRisk(List<TransactionRecord> transactions) {
    final incomes = transactions
        .where((t) => t.type == TransactionType.income)
        .map((t) => t.amount)
        .toList();
    if (incomes.length < 2) return 'Low';
    final avg = incomes.reduce((a, b) => a + b) / incomes.length;
    if (avg <= 0) return 'Low';
    double variance = 0;
    for (final income in incomes) {
      variance += (income - avg) * (income - avg);
    }
    variance /= incomes.length;
    final std = variance == 0 ? 0.0 : sqrt(variance);
    final cv = std / avg;
    if (cv >= 0.6) return 'High';
    if (cv >= 0.3) return 'Medium';
    return 'Low';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Cash Flow Forecast'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      ),
      body: PremiumGate(
        title: 'Cash Flow Forecast',
        subtitle: 'See your next 30 days and safe-to-spend.',
        child: Consumer2<TransactionProvider, RecurringProvider>(
          builder: (context, provider, recurringProvider, _) {
            CashflowForecast forecast;
            String incomeRisk;
            
            try {
              forecast = CashflowForecastService.forecast(
                provider.allTransactions,
                confirmedBills: recurringProvider.confirmedBills,
              );
              incomeRisk = _computeIncomeRisk(provider.allTransactions);
            } catch (e) {
              return _buildError(isDark, e.toString());
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                _buildSafeToSpendHero(forecast.safeToSpend, forecast.hasNegativeStartingBalance, isDark),
                if (forecast.hasNegativeStartingBalance) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.expenseRed.withAlpha(isDark ? 25 : 15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.expenseRed.withAlpha(isDark ? 50 : 30),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('⚠️ ', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Recorded expenses exceed recorded income by ${_fmt.format(forecast.startingBalance.abs())}. '
                            'Safe-to-spend is paused at ₹0 until recorded cashflow becomes positive.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppTheme.textTertiary
                                  : AppTheme.textSecondaryLight,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (forecast.hasInsufficientData) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warningYellow.withAlpha(isDark ? 18 : 12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.warningYellow.withAlpha(isDark ? 40 : 25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('ℹ️ ', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Less than 7 days of recorded data — projections may be tentative. '
                            'Continue logging transactions to increase projection accuracy.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppTheme.textTertiary
                                  : AppTheme.textSecondaryLight,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _buildStatsRow(forecast, incomeRisk, isDark),
                const SizedBox(height: 20),
                _buildForecastChart(forecast, isDark),
                const SizedBox(height: 20),
                Text(
                  'Next 7 Days',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...forecast.dailyPoints.take(7).map((p) {
                  final isNegative = p.balance < 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isNegative
                            ? AppTheme.expenseRed.withAlpha(40)
                            : (isDark
                                  ? Colors.white.withAlpha(8)
                                  : Colors.black.withAlpha(6)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('EEE, dd MMM').format(p.date),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          _fmt.format(p.balance),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isNegative
                                ? AppTheme.expenseRed
                                : AppTheme.incomeGreen,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(bool isDark, String errorMsg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppTheme.expenseRed,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load forecast',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              errorMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeToSpendHero(double amount, bool hasNegativeBase, bool isDark) {
    final isZeroOrNegative = amount <= 0 || hasNegativeBase;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: isZeroOrNegative
            ? LinearGradient(
                colors: [
                  AppTheme.expenseRed.withAlpha(isDark ? 60 : 40),
                  AppTheme.expenseRed.withAlpha(isDark ? 30 : 20),
                ],
              )
            : AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isZeroOrNegative ? AppTheme.expenseRed : AppTheme.accentPurple)
                .withAlpha(50),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Safe to Spend Today',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _fmt.format(amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasNegativeBase
                ? 'Recorded deficit — reduce spend to recover'
                : (amount <= 0
                    ? 'No remaining daily spending budget'
                    : 'Estimated daily spending budget'),
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(CashflowForecast forecast, String incomeRisk, bool isDark) {
    final isStartingNegative = forecast.startingBalance < 0;
    final items = [
      (
        'Recorded net',
        _fmt.format(forecast.startingBalance),
        isStartingNegative ? AppTheme.expenseRed : AppTheme.incomeGreen,
      ),
      (
        'End of month',
        _fmt.format(forecast.projectedEndingBalance),
        forecast.projectedEndingBalance < 0
            ? AppTheme.expenseRed
            : AppTheme.accentTeal,
      ),
      ('Income risk', incomeRisk, AppTheme.warningYellow),
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : Colors.black.withAlpha(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: item.$3,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildForecastChart(CashflowForecast forecast, bool isDark) {
    final points = forecast.dailyPoints.take(30).toList();
    if (points.isEmpty) return const SizedBox.shrink();

    final maxBalance = points.fold<double>(
      1,
      (m, p) => max(m, p.balance.abs().toDouble()),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '30-Day Balance Forecast',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: CustomPaint(
            size: const Size(double.infinity, 120),
            painter: _BarChartPainter(
              points: points
                  .map((p) => p.balance / maxBalance)
                  .toList()
                  .cast<double>(),
              isDark: isDark,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Day 1',
              style: TextStyle(fontSize: 10, color: AppTheme.textTertiary),
            ),
            Text(
              'Day 30',
              style: TextStyle(fontSize: 10, color: AppTheme.textTertiary),
            ),
          ],
        ),
      ],
    );
  }

}

class _BarChartPainter extends CustomPainter {
  final List<double> points;
  final bool isDark;

  _BarChartPainter({required this.points, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final barWidth = size.width / points.length * 0.7;
    final gap = size.width / points.length;
    final midY = size.height * 0.5;

    final positivePaint = Paint()
      ..color = AppTheme.incomeGreen.withAlpha(200)
      ..style = PaintingStyle.fill;
    final negativePaint = Paint()
      ..color = AppTheme.expenseRed.withAlpha(200)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final x = gap * i + gap * 0.15;
      final value = points[i].clamp(-1.0, 1.0);
      final barHeight = (value.abs() * midY * 0.9).toDouble();
      final paint = value >= 0 ? positivePaint : negativePaint;
      final rect = value >= 0
          ? Rect.fromLTWH(x, midY - barHeight, barWidth, barHeight)
          : Rect.fromLTWH(x, midY, barWidth, barHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }

    // Zero line
    final linePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(20)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), linePaint);
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      !listEquals(old.points, points) || old.isDark != isDark;
}
