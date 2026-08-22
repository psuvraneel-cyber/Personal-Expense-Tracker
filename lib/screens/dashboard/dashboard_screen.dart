import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/pet_colors.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/gradient_background.dart';
import 'package:pet/core/widgets/hero_greeting_card.dart';
import 'package:pet/core/widgets/metric_pill_row.dart';
import 'package:pet/core/widgets/category_progress_bar_new.dart';
import 'package:pet/core/widgets/spend_health_card.dart';
import 'package:pet/core/widgets/ai_copilot_teaser_card.dart';
import 'package:pet/core/widgets/expense_card.dart';
import 'package:pet/services/auth_service.dart';
import 'package:pet/services/spend_health_service.dart';
import 'package:pet/screens/sms_transactions/sms_transactions_screen.dart';
import 'package:pet/screens/sms_transactions/sms_permission_screen.dart';
import 'package:pet/screens/calculator/calculator_screen.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/data/models/budget.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  String _userName = '';

  // Statistics tab selection
  int _statsTab = 1; // 0=Day, 1=Month, 2=Year

  // Cached formatter to avoid recreation on every build
  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  // Memoization cache for SpendHealthService
  List<TransactionRecord>? _lastTxns;
  List<SavingGoal>? _lastGoals;
  List<RecurringPayment>? _lastBills;
  List<Budget>? _lastBudgets;
  SpendHealthResult? _cachedHealth;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final name = AuthService.userName;
    if (name != null && name.isNotEmpty) {
      setState(() => _userName = name);
    } else {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('userName') ?? '';
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _updateHealthCache(
    TransactionProvider txnProvider,
    GoalProvider goalProvider,
    RecurringProvider recurringProvider,
    BudgetProvider budgetProvider,
    double totalBudget,
  ) {
    bool txnsChanged = !identical(_lastTxns, txnProvider.allTransactions);
    bool goalsChanged = !identical(_lastGoals, goalProvider.goals);
    bool billsChanged = !identical(_lastBills, recurringProvider.recurring);
    bool budgetsChanged = !identical(_lastBudgets, budgetProvider.budgets);

    if (txnsChanged ||
        goalsChanged ||
        billsChanged ||
        budgetsChanged ||
        _cachedHealth == null) {
      _lastTxns = txnProvider.allTransactions;
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
    final formatter = _formatter;

    return Consumer3<TransactionProvider, CategoryProvider, BudgetProvider>(
      builder: (context, txnProvider, catProvider, budgetProvider, child) {
        final expenses = txnProvider.totalExpenses;
        final categorySpending = txnProvider.categoryWiseSpending;
        final dailySpending = txnProvider.dailySpending;

        // Compute today's spending
        final today = DateTime.now().day;
        final todaySpent = dailySpending[today] ?? 0.0;

        // Compute total monthly budget
        double totalBudget = 0;
        for (final b in budgetProvider.budgets) {
          totalBudget += b.amount;
        }
        final budgetRemaining = totalBudget - expenses;

        // Compute daily budget (simple: total / days in month)
        final daysInMonth = DateTime(
          txnProvider.currentYear,
          txnProvider.currentMonth + 1,
          0,
        ).day;
        final dailyBudget = totalBudget > 0 ? totalBudget / daysInMonth : 0.0;

        // Compute spend health score — pass goals/bills for parity with premium hub
        final goalProvider = Provider.of<GoalProvider>(context, listen: false);
        final recurringProvider = Provider.of<RecurringProvider>(
          context,
          listen: false,
        );

        _updateHealthCache(
          txnProvider,
          goalProvider,
          recurringProvider,
          budgetProvider,
          totalBudget,
        );

        final healthResult = _cachedHealth!;

        // Generate AI insight from health data
        String? aiInsight;
        if (categorySpending.isNotEmpty) {
          final topCat = categorySpending.entries.reduce(
            (a, b) => a.value > b.value ? a : b,
          );
          final cat = catProvider.getCategoryById(topCat.key);
          final catName = cat?.name ?? 'a category';
          aiInsight =
              'Your top spending is $catName at '
              '${formatter.format(topCat.value)} this month. ${healthResult.tip}';
        }

        return FadeTransition(
          opacity: _fadeAnimation,
          child: GradientBackground(
            animate: isDark,
            child: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ─── App Bar with month selector ─────────────
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    flexibleSpace: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.screenH,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'PET',
                            style: AppTypography.titleLarge(
                              color: isDark
                                  ? AppTheme.textPrimary
                                  : AppTheme.textPrimaryLight,
                            ),
                          ),
                          const Spacer(),
                          _buildMonthChip(context, txnProvider, isDark),
                          const SizedBox(width: 10),
                          _buildIconButton(
                            Icons.calculate_outlined,
                            isDark,
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, a, _) =>
                                    const CalculatorScreen(),
                                transitionsBuilder: (_, a, _, child) =>
                                    SlideTransition(
                                      position:
                                          Tween(
                                            begin: const Offset(1, 0),
                                            end: Offset.zero,
                                          ).animate(
                                            CurvedAnimation(
                                              parent: a,
                                              curve: Curves.easeOutCubic,
                                            ),
                                          ),
                                      child: child,
                                    ),
                                transitionDuration: const Duration(
                                  milliseconds: 300,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildIconButton(
                            Icons.notifications_none_rounded,
                            isDark,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ─── Content ─────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.screenH,
                      Spacing.sm,
                      Spacing.screenH,
                      Spacing.navBarClearance,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ── Hero Greeting Card
                        HeroGreetingCard(
                          greeting: _getGreeting(),
                          todaySpent: todaySpent,
                          dailyBudget: dailyBudget,
                          userName: _userName,
                        ),
                        const SizedBox(height: Spacing.lg),

                        // ── Metric Pills
                        MetricPillRow(
                          spentToday: todaySpent,
                          budgetRemaining: budgetRemaining,
                          spendScore: healthResult.totalScore,
                        ),
                        const SizedBox(height: Spacing.sectionGap),

                        // ── Budget Donut Chart
                        if (totalBudget > 0) ...[
                          _buildSectionHeader('This Month', isDark),
                          const SizedBox(height: Spacing.md),
                          _buildDonutChart(expenses, totalBudget, isDark),
                          const SizedBox(height: Spacing.sectionGap),
                        ],

                        // ── Top Categories
                        if (categorySpending.isNotEmpty) ...[
                          _buildSectionHeader('Top Categories', isDark),
                          const SizedBox(height: Spacing.sm),
                          _buildCategoryBars(
                            txnProvider,
                            catProvider,
                            budgetProvider,
                            isDark,
                          ),
                          const SizedBox(height: Spacing.sectionGap),
                        ],

                        // ── Statistics (line chart — kept from original)
                        _buildStatisticsSection(
                          context,
                          txnProvider,
                          formatter,
                          isDark,
                        ),
                        const SizedBox(height: Spacing.sectionGap),

                        // ── Recent Transactions
                        _buildTransactionSection(
                          context,
                          txnProvider,
                          catProvider,
                          formatter,
                          isDark,
                        ),

                        // ── Recent UPI Activity
                        _buildRecentUpiSection(context, isDark, formatter),

                        // ── Spend Health Score
                        _buildSectionHeader('Spend Health', isDark),
                        const SizedBox(height: Spacing.md),
                        SpendHealthCard(result: healthResult),
                        const SizedBox(height: Spacing.sectionGap),

                        // ── AI Copilot Teaser (replaces premium CTA)
                        AiCopilotTeaserCard(insight: aiInsight),
                        const SizedBox(height: Spacing.sectionGap),

                        // ── Empty state when no data
                        if (categorySpending.isEmpty && dailySpending.isEmpty)
                          _buildEmptyState(context, isDark),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────── NEW WIDGETS ────────────────────────────────────

  Widget _buildMonthChip(
    BuildContext context,
    TransactionProvider txnProvider,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () => _showMonthPicker(context, txnProvider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.accentPurple.withAlpha(isDark ? 30 : 18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_months[txnProvider.currentMonth - 1]} ${txnProvider.currentYear}',
              style: AppTypography.labelSmall(
                color: isDark
                    ? Colors.white.withAlpha(200)
                    : AppTheme.accentPurple,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isDark
                  ? Colors.white.withAlpha(200)
                  : AppTheme.accentPurple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, bool isDark, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    bool isDark, {
    VoidCallback? onSeeAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.sectionHeader(
            color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              'See all',
              style: AppTypography.labelMedium(color: AppTheme.accentPurple),
            ),
          ),
      ],
    );
  }

  Widget _buildDonutChart(double spent, double budget, bool isDark) {
    final percent = budget > 0 ? (spent / budget) : 0.0;
    final ringColor = PETColors.budgetRingColor(percent);
    final remaining = budget - spent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.grey).withAlpha(
              isDark ? 15 : 10,
            ),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(
                        value: spent.clamp(0.01, double.infinity),
                        color: ringColor,
                        radius: 20,
                        showTitle: false,
                      ),
                      if (remaining > 0)
                        PieChartSectionData(
                          value: remaining,
                          color: isDark
                              ? Colors.white.withAlpha(10)
                              : Colors.grey.shade200,
                          radius: 20,
                          showTitle: false,
                        ),
                    ],
                    centerSpaceRadius: 55,
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                  ),
                ),
                // Center text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: percent * 100),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, _) => Text(
                        '${value.toInt()}%',
                        style: AppTypography.displaySmall(color: ringColor),
                      ),
                    ),
                    Text(
                      'used',
                      style: AppTypography.caption(
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_formatter.format(spent)} of ${_formatter.format(budget)}',
            style: AppTypography.financialMedium(
              color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBars(
    TransactionProvider txnProvider,
    CategoryProvider catProvider,
    BudgetProvider budgetProvider,
    bool isDark,
  ) {
    final categorySpending = txnProvider.categoryWiseSpending;

    // Sort by spending amount (highest first)
    final sorted = categorySpending.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Show top 5 categories
    final top = sorted.take(5);

    return Column(
      children: top.map((entry) {
        final cat = catProvider.getCategoryById(entry.key);
        final budget = budgetProvider.budgets
            .where((b) => b.categoryId == entry.key)
            .firstOrNull;

        return CategoryProgressBarNew(
          categoryName: cat?.name ?? 'Unknown',
          emoji: _categoryEmoji(cat?.name),
          spent: entry.value,
          budget: budget?.amount ?? 0,
        );
      }).toList(),
    );
  }

  String? _categoryEmoji(String? name) {
    if (name == null) return null;
    final lower = name.toLowerCase();
    if (lower.contains('food') || lower.contains('dining')) return '🍔';
    if (lower.contains('hous') || lower.contains('rent')) return '🏠';
    if (lower.contains('transport') || lower.contains('travel')) return '🚗';
    if (lower.contains('bill') || lower.contains('util')) return '📱';
    if (lower.contains('health') || lower.contains('medical')) return '💊';
    if (lower.contains('entertain') || lower.contains('game')) return '🎮';
    if (lower.contains('shop')) return '🛍️';
    if (lower.contains('education')) return '📚';
    if (lower.contains('personal')) return '💅';
    if (lower.contains('invest')) return '📈';
    if (lower.contains('salary') || lower.contains('income')) return '💰';
    return '📦';
  }

  // ─────────────────────── KEPT FROM ORIGINAL ─────────────────────────────

  void _showMonthPicker(BuildContext context, TransactionProvider txnProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(30)
                      : Colors.black.withAlpha(20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select Month',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppTheme.textPrimary
                      : AppTheme.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 20),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.2,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  final isSelected = txnProvider.currentMonth == index + 1;
                  return GestureDetector(
                    onTap: () {
                      txnProvider.setCurrentMonth(
                        index + 1,
                        txnProvider.currentYear,
                      );
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.accentPurple
                            : (isDark
                                  ? Colors.white.withAlpha(8)
                                  : Colors.grey.withAlpha(20)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          _months[index],
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                      ? AppTheme.textSecondary
                                      : AppTheme.textSecondaryLight),
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatisticsSection(
    BuildContext context,
    TransactionProvider txnProvider,
    NumberFormat formatter,
    bool isDark,
  ) {
    final stats = _computeStatsSeries(txnProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Statistics', isDark),
        const SizedBox(height: 16),

        // Tab selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withAlpha(6)
                : Colors.grey.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _statsTabButton('Day', 0, isDark),
              _statsTabButton('Month', 1, isDark),
              _statsTabButton('Year', 2, isDark),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Income / Expense summary
        Row(
          children: [
            _buildStatIndicator(
              label: 'Income',
              amount: formatter.format(stats.totalIncome),
              color: AppTheme.incomeGreen,
              isDark: isDark,
            ),
            const SizedBox(width: 24),
            _buildStatIndicator(
              label: 'Expense',
              amount: formatter.format(stats.totalExpenses),
              color: AppTheme.expenseRed,
              isDark: isDark,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Line chart
        if (stats.hasData)
          _buildLineChart(context, stats.values, stats.labels, isDark)
        else
          _buildEmptyStatsState(isDark),
      ],
    );
  }

  _StatsSeries _computeStatsSeries(TransactionProvider txnProvider) {
    switch (_statsTab) {
      case 0:
        final daysInMonth = DateTime(
          txnProvider.currentYear,
          txnProvider.currentMonth + 1,
          0,
        ).day;
        final dailySpending = txnProvider.dailySpending;
        final values = List<double>.generate(
          daysInMonth,
          (index) => dailySpending[index + 1] ?? 0.0,
        );
        final labels = List<String>.generate(
          daysInMonth,
          (index) => '${index + 1}',
        );
        return _StatsSeries(
          values: values,
          labels: labels,
          totalIncome: txnProvider.totalIncome,
          totalExpenses: txnProvider.totalExpenses,
        );
      case 1:
        final year = txnProvider.currentYear;
        final values = List<double>.filled(12, 0.0);
        double income = 0.0;
        double expenses = 0.0;
        for (final txn in txnProvider.allTransactions) {
          if (txn.date.year != year) continue;
          if (txn.type == TransactionType.income) {
            income += txn.amount;
          } else if (txn.type == TransactionType.expense) {
            expenses += txn.amount;
            values[txn.date.month - 1] += txn.amount;
          }
        }
        return _StatsSeries(
          values: values,
          labels: _months,
          totalIncome: income,
          totalExpenses: expenses,
        );
      case 2:
        final endYear = txnProvider.currentYear;
        final startYear = endYear - 4;
        final years = [for (int y = startYear; y <= endYear; y++) y];
        final values = List<double>.filled(years.length, 0.0);
        double income = 0.0;
        double expenses = 0.0;
        for (final txn in txnProvider.allTransactions) {
          if (txn.date.year < startYear || txn.date.year > endYear) continue;
          final index = txn.date.year - startYear;
          if (txn.type == TransactionType.income) {
            income += txn.amount;
          } else if (txn.type == TransactionType.expense) {
            expenses += txn.amount;
            values[index] += txn.amount;
          }
        }
        return _StatsSeries(
          values: values,
          labels: years.map((y) => y.toString()).toList(),
          totalIncome: income,
          totalExpenses: expenses,
        );
      default:
        return const _StatsSeries(
          values: [],
          labels: [],
          totalIncome: 0,
          totalExpenses: 0,
        );
    }
  }

  Widget _buildEmptyStatsState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.centerLeft,
      child: Text(
        'No stats for this period yet.',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
        ),
      ),
    );
  }

  Widget _statsTabButton(String label, int index, bool isDark) {
    final isSelected = _statsTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _statsTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? AppTheme.textSecondary
                          : AppTheme.textSecondaryLight),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatIndicator({
    required String label,
    required String amount,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppTheme.textTertiary
                    : AppTheme.textSecondaryLight,
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.textPrimary
                    : AppTheme.textPrimaryLight,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLineChart(
    BuildContext context,
    List<double> values,
    List<String> labels,
    bool isDark,
  ) {
    final maxValue = values.isNotEmpty
        ? values.reduce((a, b) => a > b ? a : b)
        : 0.0;
    final maxSpending = maxValue > 0 ? maxValue : 100.0;
    final labelPrefix = _statsTab == 0
        ? 'Day'
        : _statsTab == 1
        ? 'Month'
        : 'Year';

    return Container(
      height: 200,
      padding: const EdgeInsets.only(right: 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxSpending > 0 ? maxSpending / 3 : 100,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : Colors.black.withAlpha(8),
                strokeWidth: 1,
                dashArray: [5, 5],
              );
            },
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= labels.length) {
                    return const Text('');
                  }

                  final lastIndex = labels.length - 1;
                  bool shouldShow;
                  if (labels.length <= 12) {
                    shouldShow = true;
                  } else if (labels.length <= 20) {
                    shouldShow =
                        index == 0 ||
                        index == lastIndex ||
                        (index + 1) % 2 == 0;
                  } else {
                    shouldShow =
                        index == 0 ||
                        index == lastIndex ||
                        (index + 1) % 5 == 0;
                  }

                  if (!shouldShow) return const Text('');

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(values.length, (index) {
                return FlSpot(index.toDouble(), values[index]);
              }),
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppTheme.accentPurple,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  if (spot.y > 0) {
                    return FlDotCirclePainter(
                      radius: 3,
                      color: AppTheme.accentPurple,
                      strokeWidth: 1.5,
                      strokeColor: isDark ? AppTheme.primaryDark : Colors.white,
                    );
                  }
                  return FlDotCirclePainter(
                    radius: 0,
                    color: Colors.transparent,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.accentPurple.withAlpha(40),
                    AppTheme.accentPurple.withAlpha(0),
                  ],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 12,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  if (spot.y == 0) return null;
                  final index = spot.x.toInt();
                  final label = index >= 0 && index < labels.length
                      ? labels[index]
                      : '';
                  return LineTooltipItem(
                    '$labelPrefix $label\n₹${spot.y.toStringAsFixed(0)}',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          minY: 0,
          maxY: maxSpending * 1.2,
        ),
      ),
    );
  }

  Widget _buildTransactionSection(
    BuildContext context,
    TransactionProvider txnProvider,
    CategoryProvider catProvider,
    NumberFormat formatter,
    bool isDark,
  ) {
    final transactions = txnProvider.transactions;
    if (transactions.isEmpty) return const SizedBox.shrink();

    final recent = transactions.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Recent', isDark),
        const SizedBox(height: 16),
        ...recent.map((txn) {
          final cat = catProvider.getCategoryById(txn.categoryId);
          return ExpenseCard(
            transaction: txn,
            category: cat,
            compact: true,
            onTap: () {},
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildRecentUpiSection(
    BuildContext context,
    bool isDark,
    NumberFormat formatter,
  ) {
    return Consumer<SmsTransactionProvider>(
      builder: (context, smsProvider, _) {
        // Not supported on this platform (iOS / web)
        if (!smsProvider.isSupported) return const SizedBox.shrink();

        // Feature not yet enabled — show the enable/promo card
        if (!smsProvider.smsFeatureEnabled) {
          return _buildUpiEnableCard(context, isDark);
        }

        // Feature enabled, still loading
        if (smsProvider.isLoading) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Recent UPI Activity', isDark),
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 28),
            ],
          );
        }

        // Feature enabled — no transactions yet
        final txns = smsProvider.transactions;
        if (txns.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                'Recent UPI Activity',
                isDark,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SmsTransactionsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(6)
                      : Colors.black.withAlpha(5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withAlpha(10)
                        : Colors.black.withAlpha(8),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inbox_rounded,
                      color: isDark
                          ? AppTheme.textTertiary
                          : AppTheme.textSecondaryLight,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No UPI transactions detected yet.\nNew bank SMS messages will appear here automatically.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppTheme.textSecondary
                              : AppTheme.textSecondaryLight,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        }

        // Feature enabled with transactions
        final recent = List.of(txns)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final display = recent.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Recent UPI Activity',
              isDark,
              onSeeAll: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SmsTransactionsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ...display.map((txn) {
              final isDebit = txn.transactionType == 'debit';
              final amountColor = isDebit
                  ? AppTheme.expenseRed
                  : AppTheme.incomeGreen;
              final prefix = isDebit ? '- ' : '+ ';
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final txnDate = DateTime(
                txn.timestamp.year,
                txn.timestamp.month,
                txn.timestamp.day,
              );

              String timeLabel;
              if (txnDate == today) {
                timeLabel = DateFormat('hh:mm a').format(txn.timestamp);
              } else if (txnDate == today.subtract(const Duration(days: 1))) {
                timeLabel = 'Yesterday';
              } else {
                timeLabel = DateFormat('dd MMM').format(txn.timestamp);
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: amountColor.withAlpha(isDark ? 25 : 18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isDebit
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: amountColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            txn.merchantName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.textPrimary
                                  : AppTheme.textPrimaryLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${txn.bankName}  •  $timeLabel',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.textTertiary
                                  : AppTheme.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$prefix${formatter.format(txn.amount)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 28),
          ],
        );
      },
    );
  }

  /// Promo card shown on dashboard when UPI auto-tracking is not yet enabled.
  Widget _buildUpiEnableCard(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('UPI Auto-Tracking', isDark),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.accentPurple.withAlpha(isDark ? 40 : 28),
                AppTheme.accentTeal.withAlpha(isDark ? 30 : 20),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.accentPurple.withAlpha(isDark ? 50 : 35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentPurple.withAlpha(60),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-Detect UPI Transactions',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppTheme.textPrimary
                                  : AppTheme.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Track bank SMS payments automatically',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.textSecondary
                                  : AppTheme.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _upiFeaturePill('🔒 On-device', isDark),
                    _upiFeaturePill('⚡ Real-time', isDark),
                    _upiFeaturePill('🏦 15+ Banks', isDark),
                    _upiFeaturePill('🚫 No duplicates', isDark),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmsPermissionScreen(),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.sms_rounded, size: 18),
                    label: const Text(
                      'Enable UPI Tracking',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _upiFeaturePill(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accentPurple.withAlpha(20),
                    AppTheme.accentPurple.withAlpha(5),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 64,
                color: AppTheme.accentPurple.withAlpha(isDark ? 150 : 120),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No transactions yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.textPrimary
                    : AppTheme.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first transaction to see\nbeautiful insights here!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppTheme.purpleGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentPurple.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Tap + to get started',
                    style: TextStyle(
                      color: Colors.white.withAlpha(220),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsSeries {
  final List<double> values;
  final List<String> labels;
  final double totalIncome;
  final double totalExpenses;

  const _StatsSeries({
    required this.values,
    required this.labels,
    required this.totalIncome,
    required this.totalExpenses,
  });

  bool get hasData => values.any((value) => value > 0);
}
