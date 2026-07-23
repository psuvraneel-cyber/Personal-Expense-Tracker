import 'package:pet/premium/widgets/premium_gate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/services/spend_health_service.dart';
import 'package:pet/premium/screens/recurring_bills_screen.dart';
import 'package:pet/premium/screens/cashflow_screen.dart';
import 'package:pet/premium/screens/goals_screen.dart';
import 'package:pet/premium/screens/ai_copilot_screen.dart';
import 'package:pet/premium/screens/alerts_screen.dart';
import 'package:pet/premium/screens/spend_pause_screen.dart';
import 'package:pet/premium/screens/tax_buckets_screen.dart';
import 'package:pet/premium/screens/weekly_planner_screen.dart';
import 'package:pet/premium/widgets/feature_card.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/data/models/budget.dart';

class PremiumHubScreen extends StatefulWidget {
  const PremiumHubScreen({super.key});

  @override
  State<PremiumHubScreen> createState() => _PremiumHubScreenState();
}

class _PremiumHubScreenState extends State<PremiumHubScreen> {
  // Memoization cache
  List<TransactionRecord>? _lastTxns;
  List<SavingGoal>? _lastGoals;
  List<RecurringPayment>? _lastBills;
  List<Budget>? _lastBudgets;

  SpendHealthResult? _cachedHealth;
  double _monthIncome = 0.0;
  double _monthExpense = 0.0;

  void _recomputeIfNeeded(
    TransactionProvider txnProvider,
    GoalProvider goalProvider,
    RecurringProvider recurringProvider,
    BudgetProvider budgetProvider,
  ) {
    bool txnsChanged = !identical(_lastTxns, txnProvider.allTransactions);
    bool goalsChanged = !identical(_lastGoals, goalProvider.goals);
    bool billsChanged = !identical(_lastBills, recurringProvider.recurring);
    bool budgetsChanged = !identical(_lastBudgets, budgetProvider.budgets);

    if (txnsChanged) {
      _lastTxns = txnProvider.allTransactions;

      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final cutoff = monthStart.subtract(const Duration(days: 1));

      double income = 0.0;
      double expense = 0.0;
      for (final t in _lastTxns!) {
        if (t.date.isAfter(cutoff)) {
          if (t.type == TransactionType.income) {
            income += t.amount;
          } else if (t.type == TransactionType.expense) {
            expense += t.amount;
          }
        }
      }
      _monthIncome = income;
      _monthExpense = expense;
    }

    if (txnsChanged || goalsChanged || billsChanged || budgetsChanged) {
      _lastGoals = goalProvider.goals;
      _lastBills = recurringProvider.recurring;
      _lastBudgets = budgetProvider.budgets;

      _cachedHealth = SpendHealthService.instance.calculate(
        transactions: _lastTxns!,
        categoryBudgets: {
          for (final b in _lastBudgets!) b.categoryId: b.amount,
        },
        goals: _lastGoals!,
        budgetSpent: budgetProvider.spentAmounts,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Premium Hub'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: PremiumGate(
        title: 'Unlock Premium Features',
        subtitle: 'Get advanced insights, AI guidance, and financial tools.',
        child:
            Consumer4<
              TransactionProvider,
              GoalProvider,
              RecurringProvider,
              BudgetProvider
            >(
              builder:
                  (
                    context,
                    txnProvider,
                    goalProvider,
                    recurringProvider,
                    budgetProvider,
                    _,
                  ) {
                    _recomputeIfNeeded(
                      txnProvider,
                      goalProvider,
                      recurringProvider,
                      budgetProvider,
                    );

                    final health = _cachedHealth!;
                    final now = DateTime.now();

                    final totalSaved = goalProvider.goals.fold(
                      0.0,
                      (s, g) => s + g.currentAmount,
                    );
                    final billsDueSoon = recurringProvider.recurring
                        .where(
                          (b) =>
                              b.nextDueAt.isAfter(now) &&
                              b.nextDueAt.difference(now).inDays <= 7,
                        )
                        .length;

                    final goalBadge = goalProvider.goals.isEmpty
                        ? null
                        : '${goalProvider.goals.length} goal${goalProvider.goals.length > 1 ? 's' : ''} · '
                              '${fmt.format(totalSaved)} saved';

                    final billBadge = recurringProvider.recurring.isEmpty
                        ? null
                        : '${recurringProvider.recurring.length} tracked';

                    final features = [
                      (
                        Icons.flag_rounded,
                        'Savings Goals',
                        'Set targets & top up',
                        AppTheme.accentPurple,
                        goalBadge,
                        () => _push(context, const GoalsScreen()),
                      ),
                      (
                        Icons.repeat_rounded,
                        'Bills & Subscriptions',
                        'Upcoming payments',
                        AppTheme.accentTeal,
                        billBadge,
                        () => _push(context, const RecurringBillsScreen()),
                      ),
                      (
                        Icons.insights_rounded,
                        'Cash Flow',
                        'Safe-to-spend & runway',
                        const Color(0xFF8B5CF6),
                        null,
                        () => _push(context, const CashflowScreen()),
                      ),
                      (
                        Icons.calendar_view_week_rounded,
                        'Weekly Planner',
                        'Daily spend tracker',
                        AppTheme.accentTeal,
                        null,
                        () => _push(context, const WeeklyPlannerScreen()),
                      ),
                      (
                        Icons.pause_circle_rounded,
                        'Focus Mode',
                        'Pause impulse spending',
                        const Color(0xFFf59e0b),
                        null,
                        () => _push(context, const SpendPauseScreen()),
                      ),
                      (
                        Icons.receipt_long_rounded,
                        'Tax Buckets',
                        '80C, 80D, HRA & more',
                        const Color(0xFF10b981),
                        null,
                        () => _push(context, const TaxBucketsScreen()),
                      ),
                      (
                        Icons.auto_awesome_rounded,
                        'AI Copilot',
                        'Ask your finances anything',
                        const Color(0xFFec4899),
                        null,
                        () => _push(context, const AiCopilotScreen()),
                      ),
                      (
                        Icons.notifications_active_rounded,
                        'Alerts Centre',
                        'Budget & anomaly alerts',
                        AppTheme.expenseRed,
                        null,
                        () => _push(context, const AlertsScreen()),
                      ),
                    ];

                    final comingSoonFeatures = [
                      (
                        Icons.account_balance_rounded,
                        'Linked Bank Accounts',
                        'Connect your bank feeds automatically.',
                        const Color(0xFF3B82F6),
                      ),
                      (
                        Icons.people_alt_rounded,
                        'Family Sharing Mode',
                        'Share budgets and track household spending.',
                        const Color(0xFFF43F5E),
                      ),
                      (
                        Icons.receipt_long_rounded,
                        'Smart Receipt Scanner',
                        'Snap a picture of receipts to log transactions.',
                        const Color(0xFF10B981),
                      ),
                    ];

                    return CustomScrollView(
                      slivers: [
                        _buildAppBar(context, isDark),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              const SizedBox(height: 8),
                              _buildHealthBanner(context, health, isDark),
                              const SizedBox(height: 14),
                              _buildQuickStats(
                                context,
                                totalSaved,
                                billsDueSoon,
                                _monthIncome,
                                _monthExpense,
                                fmt,
                                isDark,
                              ),
                              const SizedBox(height: 20),
                              _buildSectionTitle(context, 'Features'),
                              const SizedBox(height: 10),
                            ]),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1.1,
                                ),
                            delegate: SliverChildBuilderDelegate((_, i) {
                              final f = features[i];
                              return FeatureCard(
                                icon: f.$1,
                                title: f.$2,
                                subtitle: f.$3,
                                accentColor: f.$4,
                                badge: f.$5,
                                onTap: f.$6,
                              );
                            }, childCount: features.length),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              _buildSectionTitle(context, 'Coming Soon'),
                              const SizedBox(height: 10),
                            ]),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1.1,
                                ),
                            delegate: SliverChildBuilderDelegate((_, i) {
                              final f = comingSoonFeatures[i];
                              return FeatureCard(
                                icon: f.$1,
                                title: f.$2,
                                subtitle: f.$3,
                                accentColor: f.$4,
                                onTap: null,
                              );
                            }, childCount: comingSoonFeatures.length),
                          ),
                        ),
                        if (health.insights.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                _buildSectionTitle(
                                  context,
                                  '💡 Insights for You',
                                ),
                                const SizedBox(height: 10),
                                ...health.insights.map(
                                  (tip) =>
                                      _buildInsightCard(context, tip, isDark),
                                ),
                              ]),
                            ),
                          )
                        else
                          const SliverPadding(
                            padding: EdgeInsets.only(bottom: 80),
                          ),
                      ],
                    );
                  },
            ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      snap: true,
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Text('Premium Hub'),
        ],
      ),
    );
  }

  Widget _buildHealthBanner(
    BuildContext context,
    SpendHealthResult health,
    bool isDark,
  ) {
    final scoreColor = health.totalScore >= 70
        ? AppTheme.incomeGreen
        : health.totalScore >= 50
        ? AppTheme.warningYellow
        : AppTheme.expenseRed;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentPurple.withAlpha(70),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Spend Health Score',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${health.totalScore}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                      const Text(
                        ' / 100',
                        style: TextStyle(color: Colors.white60, fontSize: 18),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scoreColor.withAlpha(80)),
                ),
                child: Text(
                  health.grade,
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: health.dimensions.map((d) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    children: [
                      Text(d.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: d.score / 100,
                          minHeight: 5,
                          backgroundColor: Colors.white.withAlpha(25),
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d.score}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(
    BuildContext context,
    double totalSaved,
    int billsDueSoon,
    double monthIncome,
    double monthExpense,
    NumberFormat fmt,
    bool isDark,
  ) {
    final net = monthIncome - monthExpense;
    final stats = [
      (
        Icons.savings_rounded,
        'Saved',
        fmt.format(totalSaved),
        AppTheme.accentPurple,
      ),
      (
        Icons.calendar_today_rounded,
        'Bills this week',
        '$billsDueSoon due',
        AppTheme.warningYellow,
      ),
      (
        net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        'Month net',
        fmt.format(net),
        net >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
      ),
    ];

    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(10)
                    : Colors.black.withAlpha(7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(s.$1, size: 18, color: s.$4),
                const SizedBox(height: 6),
                Text(
                  s.$3,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: s.$4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.$2,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _buildInsightCard(BuildContext context, String insight, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warningYellow.withAlpha(isDark ? 20 : 12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.warningYellow.withAlpha(isDark ? 50 : 35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              insight,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}
