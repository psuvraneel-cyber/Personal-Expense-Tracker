import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/screens/purchase_screen.dart';
import 'package:pet/screens/budget/shared_budgets_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/category_avatar.dart';
import 'package:pet/core/widgets/pet_section.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/services/spend_health_service.dart';
import 'package:pet/premium/screens/recurring_bills_screen.dart';
import 'package:pet/premium/screens/cashflow_screen.dart';
import 'package:pet/premium/screens/goals_screen.dart';
import 'package:pet/premium/screens/invoices_screen.dart';
import 'package:pet/premium/screens/ai_copilot_screen.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/screens/alerts_screen.dart';
import 'package:pet/premium/screens/spend_pause_screen.dart';
import 'package:pet/premium/screens/tax_buckets_screen.dart';
import 'package:pet/premium/screens/weekly_planner_screen.dart';
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
          if (t.countsAsIncome) {
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
    final fmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Premium Hub')),
      // Open to everyone: free users browse the features and each one
      // shows a preview of their own data before asking them to upgrade.
      body: Consumer4<TransactionProvider, GoalProvider, RecurringProvider,
          BudgetProvider>(
        builder: (
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

          final unreadAlerts = context.watch<AlertProvider>().unreadCount;
          final isPremium = context.watch<PremiumProvider>().isPremium;

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
              'Nudges on paused categories',
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
              Icons.request_quote_rounded,
              'Invoices',
              'Bill clients, get paid by UPI',
              const Color(0xFF6366F1),
              isPremium ? null : 'Try free',
              () => _push(context, const InvoicesScreen()),
            ),
            (
              Icons.auto_awesome_rounded,
              'AI Copilot',
              'Ask your finances anything',
              const Color(0xFFec4899),
              isPremium ? null : 'Try free',
              () => _push(context, const AiCopilotScreen()),
            ),
            (
              Icons.home_rounded,
              'Household Budgets',
              'Share budgets with family',
              const Color(0xFFF43F5E),
              isPremium ? null : 'Join free',
              () => _push(context, const SharedBudgetsScreen()),
            ),
            (
              Icons.notifications_active_rounded,
              'Alerts Centre',
              'Budget & anomaly alerts',
              AppTheme.expenseRed,
              unreadAlerts > 0 ? '$unreadAlerts unread' : null,
              () => _push(context, const AlertsScreen()),
            ),
          ];

          // No "Coming Soon" cards here: unbuilt features next to the paywall
          // read as part of what a subscription buys (Play store-listing and
          // subscription-transparency rules).

          Widget featureRow(int index) {
            final f = features[index];
            final locked = !isPremium && !_freeToTry.contains(f.$2);
            return PetRow(
              title: f.$2,
              subtitle: f.$3,
              leading: CategoryAvatar(icon: f.$1, color: f.$4),
              trailing: locked
                  ? Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: isDark
                          ? AppTheme.textTertiary
                          : AppTheme.textSecondaryLight,
                    )
                  : (f.$5 == null ? null : _Badge(f.$5!, color: f.$4)),
              showChevron: true,
              onTap: f.$6,
            );
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(
              Spacing.base,
              Spacing.sm,
              Spacing.base,
              MediaQuery.paddingOf(context).bottom + Spacing.xl,
            ),
            children: [
              if (!isPremium) ...[
                _buildUpgradeBanner(context, isDark),
                const SizedBox(height: Spacing.md),
              ],
              _buildHealthBanner(context, health, isDark),
              const SizedBox(height: Spacing.md),
              _buildQuickStats(
                context,
                totalSaved,
                billsDueSoon,
                _monthIncome,
                _monthExpense,
                fmt,
                isDark,
              ),
              const SizedBox(height: Spacing.xl),
              PetSection(
                title: 'Plan',
                children: [for (var i = 0; i < 5; i++) featureRow(i)],
              ),
              const SizedBox(height: Spacing.xl),
              PetSection(
                title: 'Tools',
                children: [
                  for (var i = 5; i < features.length; i++) featureRow(i),
                ],
              ),
              if (health.insights.isNotEmpty) ...[
                const SizedBox(height: Spacing.xl),
                PetSection(
                  title: 'Insights for you',
                  children: [
                    for (final tip in health.insights)
                      _buildInsightCard(context, tip, isDark),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Features free users can use in part (AI allowance, joining a
  /// household).
  static const _freeToTry = {'AI Copilot', 'Household Budgets', 'Invoices'};

  Widget _buildUpgradeBanner(BuildContext context, bool isDark) {
    return Material(
      color: AppTheme.accentPurple.withAlpha(isDark ? 50 : 30),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PurchaseScreen(source: 'Premium Hub'),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Colors.amber, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Go Premium',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap any feature below to preview it with your own '
                      'data.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthBanner(
    BuildContext context,
    SpendHealthResult health,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(Spacing.radiusLg),
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
                        style: AppTypography.amount(
                          size: 48,
                          color: Colors.white,
                        ).copyWith(height: 1),
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
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(Spacing.radiusSm),
                ),
                child: Text(
                  health.grade,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
                      Icon(
                        _dimensionIcon(d.emoji),
                        size: 16,
                        color: Colors.white.withAlpha(220),
                      ),
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

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(Spacing.radiusLg),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withAlpha(8), width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                const VerticalDivider(width: 1, indent: 4, endIndent: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          stats[i].$3,
                          style: AppTypography.amount(
                            size: 17,
                            color: stats[i].$4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stats[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall(
                          color: isDark
                              ? AppTheme.textSecondary
                              : AppTheme.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard(BuildContext context, String insight, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 20,
            color: AppTheme.warningYellow,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              insight,
              style:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// The health service tags each dimension with an emoji; show an icon.
  static IconData _dimensionIcon(String emoji) => switch (emoji) {
        '\u{1F3AF}' => Icons.track_changes_rounded,
        '\u{1F3E6}' => Icons.savings_outlined,
        '\u{1F4CA}' => Icons.insights_rounded,
        '\u{1F9D8}' => Icons.self_improvement_rounded,
        _ => Icons.circle_outlined,
      };

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

/// A short status next to a feature ("3 tracked", "Try free").
class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(Spacing.radiusSm),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
