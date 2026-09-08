import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/premium/widgets/premium_gate.dart';
import 'package:pet/providers/transaction_provider.dart';

class CashflowScreen extends StatefulWidget {
  const CashflowScreen({super.key});

  @override
  State<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends State<CashflowScreen> {
  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  int _selectedHorizon = 30; // 14, 30, 60, 90
  String _timelineFilter = 'all'; // 'all', 'events', 'deficits'
  int? _scrubbedIndex;
  bool _lastScrubbedWasDeficit = false;

  // What-If Simulator state
  bool _showSimulator = false;
  final TextEditingController _simulatorAmountController = TextEditingController();
  DateTime _simulatorDate = DateTime.now().add(const Duration(days: 1));
  double? _simulatedAmount;
  CashflowForecast? _simulatedForecast;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecurringProvider>().load();
    });
  }

  @override
  void dispose() {
    _simulatorAmountController.dispose();
    super.dispose();
  }

  void _runSimulation(CashflowForecast baseForecast, double? amount, DateTime date) {
    setState(() {
      _simulatedAmount = amount;
      _simulatorDate = date;
      if (amount != null && amount > 0) {
        _simulatedForecast = CashflowForecastService.simulateExpense(
          baseForecast,
          amount: amount,
          date: date,
        );
      } else {
        _simulatedForecast = null;
      }
    });
  }

  void _clearSimulation() {
    setState(() {
      _simulatedAmount = null;
      _simulatedForecast = null;
      _simulatorAmountController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Cash Flow Forecast'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          IconButton(
            tooltip: 'What-If Simulator',
            icon: Icon(
              _showSimulator ? Icons.science : Icons.science_outlined,
              color: _showSimulator ? AppTheme.accentPurple : null,
            ),
            onPressed: () {
              setState(() => _showSimulator = !_showSimulator);
            },
          ),
        ],
      ),
      body: PremiumGate(
        title: 'Cash Flow Forecast',
        subtitle: 'See your next 30 days and safe-to-spend.',
        child: Consumer<TransactionProvider>(
          builder: (context, provider, _) {
            CashflowForecast forecast;
            String incomeRisk;

            try {
              forecast = CashflowForecastService.forecast(
                provider.allTransactions,
              );
              incomeRisk = _computeIncomeRisk(provider.allTransactions);
        subtitle: 'See your future balance, safe-to-spend allowance & runway.',
        child: Consumer2<TransactionProvider, RecurringProvider>(
          builder: (context, provider, recurringProvider, _) {
            double goalReserves = 0.0;
            try {
              goalReserves = Provider.of<GoalProvider>(context).totalActiveGoalReserves;
            } catch (_) {
              goalReserves = 0.0;
            }
            final CashflowForecast baseForecast;
            try {
              baseForecast = CashflowForecastService.forecast(
                provider.allTransactions,
                confirmedBills: recurringProvider.confirmedBills,
                days: _selectedHorizon,
                goalReserves: goalReserves,
              );
            } catch (e) {
              return _buildError(isDark, e.toString());
            }

            // Keep simulated forecast in sync with horizon / transactions
            final activeForecast = (_simulatedAmount != null && _simulatedAmount! > 0)
                ? CashflowForecastService.simulateExpense(
                    baseForecast,
                    amount: _simulatedAmount!,
                    date: _simulatorDate,
                  )
                : baseForecast;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                _buildSafeToSpendHero(forecast.safeToSpend, isDark),
                if (forecast.hasInsufficientData) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warningYellow.withAlpha(isDark ? 18 : 12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.warningYellow.withAlpha(
                          isDark ? 40 : 25,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('⚠️ ', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Less than 7 days of data — projections may be unreliable. '
                            'Keep using the app to improve accuracy.',
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
                // 1. Data quality & confidence banner
                _buildConfidenceBanner(baseForecast, isDark),
                const SizedBox(height: 12),

                // 2. Horizon Segmented Control
                _buildHorizonSelector(isDark),
                const SizedBox(height: 16),

                // 3. Hero Card: Safe-to-Spend with info affordance
                _buildSafeToSpendHero(baseForecast, isDark),
                const SizedBox(height: 12),

                // 4. Runway & Health Row
                _buildRunwayAndHealthRow(baseForecast, isDark),
                const SizedBox(height: 16),

                // 5. "Can I Afford This?" What-If Simulator Card
                if (_showSimulator) ...[
                  _buildWhatIfSimulatorCard(baseForecast, isDark),
                  const SizedBox(height: 16),
                ],

                // 6. Interactive Forecast Chart with Scrubber
                _buildInteractiveChartSection(
                  baseForecast,
                  activeForecast,
                  isDark,
                ),
                const SizedBox(height: 20),

                // 7. Danger Zone / Trough Driver Card
                _buildTroughInsightCard(baseForecast, isDark),
                const SizedBox(height: 20),

                // 8. Full Daily Timeline with Filters
                _buildTimelineHeader(baseForecast, isDark),
                const SizedBox(height: 8),
                _buildTimelineList(baseForecast, isDark),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Confidence & Data Quality Banner
  // ---------------------------------------------------------------------------
  Widget _buildConfidenceBanner(CashflowForecast forecast, bool isDark) {
    if (forecast.hasInsufficientData) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.warningYellow.withAlpha(isDark ? 22 : 14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.warningYellow.withAlpha(isDark ? 50 : 30),
          ),
        ),
        child: Row(
          children: [
            const Text('⚠️ ', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Limited history: Projections are tentative. Add more transactions to improve forecast reliability.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Icon(
          Icons.verified_outlined,
          size: 14,
          color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Based on ${forecast.lookbackDays}-day rolling baseline · ${_selectedHorizon}D outlook',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withAlpha(10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            forecast.confidence.displayName,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Horizon Segmented Control
  // ---------------------------------------------------------------------------
  Widget _buildHorizonSelector(bool isDark) {
    const horizons = [14, 30, 60, 90];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: horizons.map((h) {
          final isSelected = _selectedHorizon == h;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_selectedHorizon != h) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedHorizon = h;
                    _scrubbedIndex = null;
                    if (_simulatedAmount != null && _simulatedAmount! > 0) {
                      // Clamp simulation date if beyond new horizon
                      final maxDate = DateTime.now().add(Duration(days: h - 1));
                      if (_simulatorDate.isAfter(maxDate)) {
                        _simulatorDate = maxDate;
                      }
                    }
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentPurple
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${h}D',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Hero Card: Safe-to-Spend
  // ---------------------------------------------------------------------------
  Widget _buildSafeToSpendHero(CashflowForecast forecast, bool isDark) {
    final amount = forecast.safeToSpend;
    final isZero = amount <= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isZero
            ? LinearGradient(
                colors: [
                  AppTheme.expenseRed.withAlpha(isDark ? 60 : 45),
                  AppTheme.expenseRed.withAlpha(isDark ? 30 : 20),
                ],
              )
            : AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (isZero ? AppTheme.expenseRed : AppTheme.accentPurple).withAlpha(45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(
                      child: Text(
                        'Safe to Spend Allowance',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showSafeToSpendExplanation(forecast, isDark),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_selectedHorizon-Day Window',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _fmt.format(amount),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                ' / day',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isZero
                ? 'Safe spending room is paused to protect your ${_fmt.format(forecast.safetyBuffer)} safety buffer & bills.'
                : '${_fmt.format(forecast.totalSafeToSpend)} total spendable over $_selectedHorizon days preserving ${_fmt.format(forecast.safetyBuffer)} buffer.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
    CashflowForecast forecast,
    String incomeRisk,
    bool isDark,
  ) {
    final items = [
      (
        'Starting balance',
        _fmt.format(forecast.startingBalance),
        AppTheme.incomeGreen,
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
  // ---------------------------------------------------------------------------
  // 4. Runway & Health Cards Row
  // ---------------------------------------------------------------------------
  Widget _buildRunwayAndHealthRow(CashflowForecast forecast, bool isDark) {
    final bool isPositive = forecast.isCashflowPositive;
    final int runwayDays = forecast.runwayDays ?? 0;

    final String runwayTitle;
    final String runwayValue;
    final Color runwayColor;

    if (forecast.hasInsufficientData) {
      runwayTitle = 'Runway';
      runwayValue = 'Insufficient data';
      runwayColor = AppTheme.warningYellow;
    } else if (isPositive) {
      runwayTitle = 'Monthly Surplus';
      runwayValue = '+${_fmt.format(forecast.monthlyNetCashflow)}';
      runwayColor = AppTheme.incomeGreen;
    } else if (runwayDays < 7) {
      runwayTitle = 'Critical Runway';
      runwayValue = '< 7 days';
      runwayColor = AppTheme.expenseRed;
    } else {
      runwayTitle = 'Runway';
      runwayValue = '$runwayDays days';
      runwayColor = AppTheme.warningYellow;
    }

    final riskColor = switch (forecast.riskLevel) {
      CashflowRiskLevel.healthy => AppTheme.incomeGreen,
      CashflowRiskLevel.watch => AppTheme.accentTeal,
      CashflowRiskLevel.atRisk => AppTheme.warningYellow,
      CashflowRiskLevel.deficitExpected => AppTheme.expenseRed,
      CashflowRiskLevel.insufficientData => AppTheme.textTertiary,
    };

    return Row(
      children: [
        // Runway card
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.timelapse,
                      size: 14,
                      color: runwayColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      runwayTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  runwayValue,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: runwayColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Risk card
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 14, color: riskColor),
                    const SizedBox(width: 4),
                    const Text(
                      'Cashflow Risk',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  forecast.riskLevel.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: riskColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. "Can I Afford This?" What-If Simulator Card
  // ---------------------------------------------------------------------------
  Widget _buildWhatIfSimulatorCard(CashflowForecast baseForecast, bool isDark) {
    final quickAmounts = [2000.0, 5000.0, 15000.0, 25000.0];
    final sim = _simulatedForecast;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.accentPurple.withAlpha(isDark ? 80 : 40),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentPurple.withAlpha(isDark ? 25 : 15),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.science_rounded,
                  size: 16,
                  color: AppTheme.accentPurple,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Can I Afford This? (Simulator)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_simulatedAmount != null && _simulatedAmount! > 0)
                TextButton(
                  onPressed: _clearSimulation,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppTheme.textTertiary,
                  ),
                  child: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Amount Field & Date Picker
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _simulatorAmountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    labelText: 'Simulate Purchase',
                    hintText: '25000',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) {
                    final amt = double.tryParse(val.replaceAll(',', '').trim());
                    _runSimulation(baseForecast, amt, _simulatorDate);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _simulatorDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(Duration(days: _selectedHorizon - 1)),
                    );
                    if (picked != null) {
                      _runSimulation(baseForecast, _simulatedAmount, picked);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Date', style: TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
                      Text(
                        DateFormat('d MMM').format(_simulatorDate),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quick amount chips
          Wrap(
            spacing: 6,
            children: quickAmounts.map((amt) {
              final isSelected = _simulatedAmount == amt;
              return ChoiceChip(
                label: Text('₹${_fmt.format(amt)}', style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (sel) {
                  final newAmt = sel ? amt : null;
                  _simulatorAmountController.text = newAmt != null ? newAmt.toStringAsFixed(0) : '';
                  _runSimulation(baseForecast, newAmt, _simulatorDate);
                },
              );
            }).toList(),
          ),
          if (sim != null) ...[
            const SizedBox(height: 12),
            _buildSimulationResultBanner(baseForecast, sim, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildSimulationResultBanner(
    CashflowForecast base,
    CashflowForecast sim,
    bool isDark,
  ) {
    final isDeficit = sim.lowestProjectedBalance < 0;
    final isBufferBreach = sim.lowestProjectedBalance < sim.safetyBuffer;
    final bannerColor = isDeficit
        ? AppTheme.expenseRed
        : (isBufferBreach ? AppTheme.warningYellow : AppTheme.incomeGreen);

    final String verdict;
    if (isDeficit) {
      verdict = 'Deficit Risk: Would push projected balance to ${_fmt.format(sim.lowestProjectedBalance)} on ${DateFormat('d MMM').format(sim.lowestProjectedDate)}.';
    } else if (isBufferBreach) {
      verdict = 'Buffer Breach: Projected balance dips to ${_fmt.format(sim.lowestProjectedBalance)}, below your ${_fmt.format(sim.safetyBuffer)} safety buffer.';
    } else {
      verdict = 'Likely Safe: Projected lowest balance remains healthy at ${_fmt.format(sim.lowestProjectedBalance)}.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bannerColor.withAlpha(isDark ? 25 : 15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bannerColor.withAlpha(isDark ? 60 : 35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDeficit ? Icons.error_outline : (isBufferBreach ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                size: 16,
                color: bannerColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  verdict,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: bannerColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Safe-to-spend changes from ${_fmt.format(base.safeToSpend)}/d → ${_fmt.format(sim.safeToSpend)}/d. No actual transaction created.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Interactive Forecast Chart with Scrubber
  // ---------------------------------------------------------------------------
  Widget _buildInteractiveChartSection(
    CashflowForecast baseForecast,
    CashflowForecast activeForecast,
    bool isDark,
  ) {
    final points = activeForecast.dailyPoints;
    if (points.isEmpty) return const SizedBox.shrink();

    final scrubbedPoint = _scrubbedIndex != null && _scrubbedIndex! < points.length
        ? points[_scrubbedIndex!]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$_selectedHorizon-Day Projection',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (scrubbedPoint != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${DateFormat('d MMM').format(scrubbedPoint.date)}: ${_fmt.format(scrubbedPoint.balance)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentPurple,
                  ),
                ),
              )
            else
              Text(
                'Drag across to inspect',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 180,
          padding: const EdgeInsets.only(top: 10, bottom: 8, left: 6, right: 6),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) => _handleScrub(d.localPosition.dx, constraints.maxWidth, points.length, points),
                onPanUpdate: (d) => _handleScrub(d.localPosition.dx, constraints.maxWidth, points.length, points),
                onPanEnd: (_) => setState(() => _scrubbedIndex = null),
                onPanCancel: () => setState(() => _scrubbedIndex = null),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _SplineChartPainter(
                    basePoints: baseForecast.dailyPoints,
                    scenarioPoints: _simulatedForecast?.dailyPoints,
                    scrubbedIndex: _scrubbedIndex,
                    isDark: isDark,
                    safetyBuffer: baseForecast.safetyBuffer,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Day 1 (${DateFormat('d MMM').format(points.first.date)})', style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
            Text('End of Forecast (${DateFormat('d MMM').format(points.last.date)})', style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
          ],
        ),
      ],
    );
  }

  void _handleScrub(double dx, double width, int totalPoints, List<CashflowPoint> points) {
    if (width <= 0 || totalPoints <= 0) return;
    final double rawIndex = (dx / width) * totalPoints;
    final int index = rawIndex.clamp(0.0, totalPoints - 1.0).toInt();

    if (index != _scrubbedIndex) {
      final isDeficit = points[index].balance < 0;
      if (isDeficit != _lastScrubbedWasDeficit) {
        HapticFeedback.selectionClick();
        _lastScrubbedWasDeficit = isDeficit;
      }
      setState(() => _scrubbedIndex = index);
    }
  }

  // ---------------------------------------------------------------------------
  // 7. Danger Zone / Trough Driver Card
  // ---------------------------------------------------------------------------
  Widget _buildTroughInsightCard(CashflowForecast forecast, bool isDark) {
    final lowestBal = forecast.lowestProjectedBalance;
    final lowestDate = forecast.lowestProjectedDate;
    final dateStr = DateFormat('EEE, d MMM').format(lowestDate);
    final isDeficit = lowestBal < 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDeficit
              ? AppTheme.expenseRed.withAlpha(isDark ? 60 : 35)
              : (isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isDeficit ? AppTheme.expenseRed : AppTheme.accentTeal).withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDeficit ? Icons.warning_amber_rounded : Icons.south_rounded,
              size: 20,
              color: isDeficit ? AppTheme.expenseRed : AppTheme.accentTeal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDeficit ? 'Projected Deficit Trough' : 'Lowest Projected Balance',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt.format(lowestBal)} on $dateStr',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDeficit ? AppTheme.expenseRed : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                if (forecast.troughDriver != null && forecast.troughDriver!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Key Driver: ${forecast.troughDriver}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 8. Full Daily Timeline & Filters
  // ---------------------------------------------------------------------------
  Widget _buildTimelineHeader(CashflowForecast forecast, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Daily Timeline ($_selectedHorizon Days)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${forecast.dailyPoints.length} days',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTimelineFilterChip('all', 'All', isDark),
              const SizedBox(width: 6),
              _buildTimelineFilterChip('events', 'Bills & Income', isDark),
              const SizedBox(width: 6),
              _buildTimelineFilterChip('deficits', 'Deficits', isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineFilterChip(String key, String label, bool isDark) {
    final isSelected = _timelineFilter == key;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _timelineFilter = key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentPurple
              : (isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : (isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineList(CashflowForecast forecast, bool isDark) {
    var points = forecast.dailyPoints;

    if (_timelineFilter == 'events') {
      points = points.where((p) => p.isSalaryDeposit || p.isRecurringBillDue || p.eventTitle != null).toList();
    } else if (_timelineFilter == 'deficits') {
      points = points.where((p) => p.balance < 0).toList();
    }

    if (points.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(
          _timelineFilter == 'deficits' ? 'No projected deficit days! 🎉' : 'No matching events found.',
          style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
        ),
      );
    }

    return Column(
      children: points.map((p) {
        final isNegative = p.balance < 0;
        final isTrough = p.date.year == forecast.lowestProjectedDate.year &&
            p.date.month == forecast.lowestProjectedDate.month &&
            p.date.day == forecast.lowestProjectedDate.day;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isNegative
                  ? AppTheme.expenseRed.withAlpha(40)
                  : (isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        DateFormat('EEE, d MMM').format(p.date),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (isTrough) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.expenseRed.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Trough',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.expenseRed),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _fmt.format(p.balance),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isNegative ? AppTheme.expenseRed : AppTheme.incomeGreen,
                    ),
                  ),
                ],
              ),
              if (p.eventTitle != null || p.isRecurringBillDue || p.isSalaryDeposit) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      p.isSalaryDeposit ? Icons.arrow_downward : Icons.receipt_long,
                      size: 13,
                      color: p.isSalaryDeposit ? AppTheme.incomeGreen : AppTheme.accentTeal,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      p.eventTitle ?? (p.isSalaryDeposit ? 'Salary Deposit' : 'Upcoming Bill'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Safe-to-Spend Math Deconstruction Bottom Sheet
  // ---------------------------------------------------------------------------
  void _showSafeToSpendExplanation(CashflowForecast forecast, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.primaryDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textTertiary.withAlpha(40),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Safe-to-Spend Math Deconstruction',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Safe-to-spend is anchored to your projected lowest balance over the next $_selectedHorizon days '
                  'while guaranteeing your projected liquidity never breaches your ${_fmt.format(forecast.safetyBuffer)} safety buffer.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _buildMathRow(
                  'Projected Lowest Balance',
                  _fmt.format(forecast.lowestProjectedBalance),
                  isPositive: forecast.lowestProjectedBalance >= forecast.safetyBuffer,
                  isNegative: forecast.lowestProjectedBalance < 0,
                ),
                _buildMathRow(
                  'Safety Buffer Floor',
                  '-${_fmt.format(forecast.safetyBuffer)}',
                  isNegative: true,
                ),
                if (forecast.expectedGoalReserves > 0)
                  _buildMathRow(
                    'Goal Reserves Protected',
                    '-${_fmt.format(forecast.expectedGoalReserves)}',
                    isNegative: true,
                  ),
                const Divider(height: 20),
                _buildMathRow(
                  'Total Spendable Capacity',
                  _fmt.format(forecast.totalSafeToSpend),
                  isBold: true,
                  isPositive: forecast.totalSafeToSpend > 0,
                ),
                _buildMathRow(
                  '÷ Horizon Length',
                  '$_selectedHorizon days',
                  isBold: false,
                ),
                const Divider(height: 20),
                _buildMathRow(
                  'Daily Safe-to-Spend',
                  '${_fmt.format(forecast.safeToSpend)} / day',
                  isBold: true,
                  color: AppTheme.accentPurple,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight),
                          const SizedBox(width: 6),
                          Text(
                            'Path-Dependent Headroom',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AppTheme.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Safe-to-Spend protects your account on its lowest projected day (trough: ${_fmt.format(forecast.lowestProjectedBalance)}), rather than a simple sum of overall inflows and outflows. This ensures your balance never breaches your safety buffer on any day.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMathRow(
    String label,
    String value, {
    bool isPositive = false,
    bool isNegative = false,
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? null : AppTheme.textTertiary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ??
                  (isNegative
                      ? AppTheme.expenseRed
                      : (isPositive ? AppTheme.incomeGreen : null)),
            ),
          ),
        ],
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
            const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.expenseRed),
            const SizedBox(height: 12),
            const Text('Could not calculate forecast', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(errorMsg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Interactive Spline & Area Chart Painter with Scrubber & Scenario Overlays
// -----------------------------------------------------------------------------
class _SplineChartPainter extends CustomPainter {
  final List<CashflowPoint> basePoints;
  final List<CashflowPoint>? scenarioPoints;
  final int? scrubbedIndex;
  final bool isDark;
  final double safetyBuffer;

  _SplineChartPainter({
    required this.basePoints,
    this.scenarioPoints,
    this.scrubbedIndex,
    required this.isDark,
    this.safetyBuffer = CashflowForecastService.defaultSafetyBuffer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (basePoints.isEmpty) return;

    final n = basePoints.length;
    double minVal = basePoints.fold(double.infinity, (m, p) => min(m, p.balance));
    double maxVal = basePoints.fold(-double.infinity, (m, p) => max(m, p.balance));

    if (scenarioPoints != null && scenarioPoints!.isNotEmpty) {
      for (final p in scenarioPoints!) {
        final bal = p.scenarioBalance ?? p.balance;
        minVal = min(minVal, bal);
        maxVal = max(maxVal, bal);
      }
    }

    // Include ₹0 and configured safety buffer in scale bounds
    minVal = min(minVal, 0.0);
    maxVal = max(maxVal, max(6000.0, safetyBuffer * 1.2));

    final span = (maxVal - minVal).abs();
    final padding = span * 0.15;
    final chartMin = minVal - padding;
    final chartMax = maxVal + padding;
    final chartSpan = (chartMax - chartMin).clamp(1.0, double.infinity);

    double getY(double bal) {
      final ratio = (bal - chartMin) / chartSpan;
      return size.height - (ratio * size.height);
    }

    final double zeroY = getY(0.0).clamp(0.0, size.height);
    final double bufferY = getY(safetyBuffer).clamp(0.0, size.height);

    // 1. Draw Zero Line
    final zeroLinePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(30)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroLinePaint);

    // 2. Draw Safety Buffer Line
    final bufferLinePaint = Paint()
      ..color = AppTheme.warningYellow.withAlpha(isDark ? 80 : 60)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(0, bufferY), Offset(size.width, bufferY), bufferLinePaint);

    // 3. Build Base Spline Path
    final Path basePath = Path();
    final Path baseAreaPath = Path();

    final stepX = size.width / (n - 1).clamp(1, double.infinity);

    final List<Offset> baseCoords = [];
    for (int i = 0; i < n; i++) {
      final x = i * stepX;
      final y = getY(basePoints[i].balance);
      baseCoords.add(Offset(x, y));
    }

    basePath.moveTo(baseCoords.first.dx, baseCoords.first.dy);
    baseAreaPath.moveTo(baseCoords.first.dx, zeroY);
    baseAreaPath.lineTo(baseCoords.first.dx, baseCoords.first.dy);

    for (int i = 0; i < n - 1; i++) {
      final p0 = i > 0 ? baseCoords[i - 1] : baseCoords[i];
      final p1 = baseCoords[i];
      final p2 = baseCoords[i + 1];
      final p3 = i < n - 2 ? baseCoords[i + 2] : p2;

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

      basePath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      baseAreaPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    baseAreaPath.lineTo(baseCoords.last.dx, zeroY);
    baseAreaPath.close();

    // 4. Fill Area Gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.accentPurple.withAlpha(isDark ? 80 : 60),
          AppTheme.accentTeal.withAlpha(isDark ? 20 : 10),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(baseAreaPath, fillPaint);

    // 5. Stroke Base Line
    final strokePaint = Paint()
      ..color = AppTheme.accentPurple
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(basePath, strokePaint);

    // 6. Draw Scenario Overlay Curve if present
    if (scenarioPoints != null && scenarioPoints!.isNotEmpty) {
      final Path simPath = Path();
      final List<Offset> simCoords = [];
      for (int i = 0; i < scenarioPoints!.length; i++) {
        final x = i * stepX;
        final y = getY(scenarioPoints![i].scenarioBalance ?? scenarioPoints![i].balance);
        simCoords.add(Offset(x, y));
      }

      simPath.moveTo(simCoords.first.dx, simCoords.first.dy);
      for (int i = 0; i < scenarioPoints!.length - 1; i++) {
        final p0 = i > 0 ? simCoords[i - 1] : simCoords[i];
        final p1 = simCoords[i];
        final p2 = simCoords[i + 1];
        final p3 = i < scenarioPoints!.length - 2 ? simCoords[i + 2] : p2;

        final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

        simPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }

      final simPaint = Paint()
        ..color = AppTheme.warningYellow
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawPath(simPath, simPaint);
    }

    // 7. Event Dots on Timeline
    for (int i = 0; i < n; i++) {
      final pt = basePoints[i];
      if (pt.isRecurringBillDue || pt.isSalaryDeposit) {
        final coord = baseCoords[i];
        final dotPaint = Paint()
          ..color = pt.isSalaryDeposit ? AppTheme.incomeGreen : AppTheme.expenseRed
          ..style = PaintingStyle.fill;
        canvas.drawCircle(coord, 3.5, dotPaint);
      }
    }

    // 8. Scrubber Indicator
    if (scrubbedIndex != null && scrubbedIndex! >= 0 && scrubbedIndex! < n) {
      final scrubCoord = baseCoords[scrubbedIndex!];
      final scrubLinePaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withAlpha(120)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(scrubCoord.dx, 0),
        Offset(scrubCoord.dx, size.height),
        scrubLinePaint,
      );

      final outerDot = Paint()
        ..color = AppTheme.accentPurple
        ..style = PaintingStyle.fill;
      final innerDot = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawCircle(scrubCoord, 6, outerDot);
      canvas.drawCircle(scrubCoord, 3, innerDot);
    }
  }

  @override
  bool shouldRepaint(_SplineChartPainter old) {
    return old.scrubbedIndex != scrubbedIndex ||
        old.basePoints != basePoints ||
        old.scenarioPoints != scenarioPoints ||
        old.safetyBuffer != safetyBuffer ||
        old.isDark != isDark;
  }
}
