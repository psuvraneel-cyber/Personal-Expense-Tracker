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
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/screens/alerts_screen.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/motion.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/widgets/amount_text.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:pet/core/widgets/category_avatar.dart';
import 'package:pet/core/widgets/home_summary.dart';
import 'package:pet/core/widgets/pet_section.dart';
import 'package:pet/core/widgets/sync_status_chip.dart';
import 'package:pet/core/widgets/transaction_row.dart';
import 'package:pet/screens/home/home_tabs.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/gradient_background.dart';
import 'package:pet/core/widgets/notification_permission_banner.dart';
import 'package:pet/core/widgets/oem_battery_dialog.dart';
import 'package:pet/premium/services/oem_optimization_service.dart';
import 'package:pet/core/widgets/spend_health_card.dart';
import 'package:pet/core/widgets/ai_copilot_teaser_card.dart';
import 'package:pet/core/widgets/subscriptions_found_card.dart';
import 'package:pet/core/widgets/money_wrap_entry_card.dart';
import 'package:pet/services/auth_service.dart';
import 'package:pet/services/spend_health_service.dart';
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

class _DashboardScreenState extends State<DashboardScreen> {
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

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

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
    _loadUserName();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final oemService = OemOptimizationService.instance;
      final isAggressive = await oemService.isAggressiveOem();
      final hasShown = await oemService.hasPromptBeenShown();

      if (isAggressive && !hasShown && mounted) {
        showDialog(
          context: context,
          builder: (_) => const OemBatteryDialog(),
        );
      }
    });
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

  /// First appearance only: each block fades up a few pixels, 30 ms after
  /// the one above. Spacers are left alone; reduced motion skips it all.
  bool _revealed = false;

  List<Widget> _reveal(List<Widget> children) {
    if (_revealed || Motion.reduced(context)) return children;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealed = true);
    var i = 0;
    return [
      for (final c in children)
        if (c is SizedBox)
          c
        else
          c
              .animate(delay: Duration(milliseconds: 30 * i++))
              .fadeIn(duration: Motion.emphasized, curve: Motion.easeOut)
              .moveY(
                begin: 10,
                end: 0,
                duration: Motion.emphasized,
                curve: Motion.easeOut,
              ),
    ];
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
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
          aiInsight = 'Your top spending is $catName at '
              '${formatter.format(topCat.value)} this month. ${healthResult.tip}';
        }

        return GradientBackground(
          animate: isDark,
          child: SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ─── App Bar with month selector ─────────────
                SliverAppBar(
                  // Scrolls away with the page: a floating transparent bar
                  // let content slide underneath the title.
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
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
                          tooltip: 'Calculator',
                          Icons.calculate_outlined,
                          isDark,
                          onTap: () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, anim, secAnim) =>
                                  const CalculatorScreen(),
                              transitionsBuilder:
                                  (context, anim, secAnim, child) =>
                                      SlideTransition(
                                position: Tween(
                                  begin: const Offset(1, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: anim,
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
                        Consumer<AlertProvider>(
                          builder: (context, alertProvider, _) {
                            final unread = alertProvider.unreadCount;
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AlertsScreen(),
                                ),
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withAlpha(8)
                                          : Colors.black.withAlpha(6),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      unread > 0
                                          ? Icons.notifications_active_rounded
                                          : Icons.notifications_none_rounded,
                                      size: 20,
                                      color: unread > 0
                                          ? AppTheme.expenseRed
                                          : (isDark
                                              ? AppTheme.textSecondary
                                              : AppTheme.textSecondaryLight),
                                    ),
                                  ),
                                  if (unread > 0)
                                    Positioned(
                                      top: -3,
                                      right: -3,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: AppTheme.expenseRed,
                                          shape: BoxShape.circle,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Text(
                                          unread > 9 ? '9+' : '$unread',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── Content ─────────────────────────────────
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Spacing.screenH,
                    Spacing.sm,
                    Spacing.screenH,
                    Spacing.tabBottom(context),
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const NotificationPermissionBanner(),
                      ..._reveal([
                        // ── Hero: this month's spend against the budget
                        HomeHero(
                          greeting: _userName.isNotEmpty
                              ? '${_getGreeting()}, ${_userName.split(' ').first}'
                              : _getGreeting(),
                          monthLabel: _monthNames[txnProvider.currentMonth - 1],
                          spent: expenses,
                          budget: totalBudget,
                          income: txnProvider.totalIncome,
                          status: const SyncStatusChip(),
                        ),
                        const SizedBox(height: Spacing.md),

                        // ── Three numbers at a glance
                        HomeStatStrip(
                          spentToday: todaySpent,
                          budget: totalBudget,
                          spentThisMonth: expenses,
                          score: healthResult.totalScore,
                        ),
                        const SizedBox(height: Spacing.sectionGap),

                        // ── Recent transactions
                        _buildTransactionSection(
                          context,
                          txnProvider,
                          catProvider,
                          formatter,
                          isDark,
                        ),

                        // ── Where the money went
                        if (categorySpending.isNotEmpty) ...[
                          _buildSectionHeader('Where it went', isDark),
                          const SizedBox(height: Spacing.md),
                          _buildCategoryBars(
                            txnProvider,
                            catProvider,
                            budgetProvider,
                            isDark,
                          ),
                          const SizedBox(height: Spacing.sectionGap),
                        ],

                        // ── Spending trend
                        _buildStatisticsSection(
                          context,
                          txnProvider,
                          formatter,
                          isDark,
                        ),
                        const SizedBox(height: Spacing.sectionGap),

                        // ── UPI tracking invite (only when it's off)
                        _buildRecentUpiSection(context, isDark, formatter),

                        // ── Last month's Money Wrap (first week of month)
                        const MoneyWrapEntryCard(),

                        // ── Subscriptions found (moment-of-value insight)
                        const SubscriptionsFoundCard(),

                        // ── Spend Health Score (the card has its title)
                        SpendHealthCard(result: healthResult),
                        const SizedBox(height: Spacing.md),

                        // ── AI Copilot teaser
                        AiCopilotTeaserCard(insight: aiInsight),
                        const SizedBox(height: Spacing.sectionGap),
                      ]),

                      // ── Empty state when no data
                      if (categorySpending.isEmpty && dailySpending.isEmpty)
                        _buildEmptyState(context, isDark),
                    ]),
                  ),
                ),
              ],
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
              color:
                  isDark ? Colors.white.withAlpha(200) : AppTheme.accentPurple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    bool isDark, {
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final button = GestureDetector(
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
    if (tooltip == null) return button;
    // Screen readers announce it as a labelled button.
    return Tooltip(
      message: tooltip,
      child: Semantics(button: true, label: tooltip, child: button),
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

  Widget _buildCategoryBars(
    TransactionProvider txnProvider,
    CategoryProvider catProvider,
    BudgetProvider budgetProvider,
    bool isDark,
  ) {
    final sorted = txnProvider.categoryWiseSpending.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final total = sorted.fold<double>(0, (sum, e) => sum + e.value);
    final largest = top.isEmpty ? 0.0 : top.first.value;

    return PetSection(
      children: [
        for (final entry in top)
          _CategoryShareRow(
            name: catProvider.getCategoryById(entry.key)?.name ?? 'Other',
            icon: catProvider.getCategoryById(entry.key)?.icon ??
                Icons.category_rounded,
            color: catProvider.getCategoryById(entry.key)?.color ??
                AppTheme.textTertiary,
            spent: entry.value,
            share: total > 0 ? entry.value / total : 0,
            budget: budgetProvider.budgets
                    .where((b) => b.categoryId == entry.key)
                    .firstOrNull
                    ?.amount ??
                0,
            // Without a budget, bars compare categories with each other.
            relative: largest > 0 ? entry.value / largest : 0,
          ),
      ],
    );
  }

  // ─────────────────────── KEPT FROM ORIGINAL ─────────────────────────────

  void _showMonthPicker(BuildContext context, TransactionProvider txnProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      useSafeArea: true,
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
                  color:
                      isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
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
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
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
    final muted = isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildSectionHeader('Spending trend', isDark)),
            _buildPeriodSwitch(isDark),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(Spacing.radiusLg),
            border: isDark
                ? null
                : Border.all(color: Colors.black.withAlpha(8), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStatIndicator(
                      label: 'In',
                      amount: stats.totalIncome,
                      color: AppTheme.incomeGreen,
                      isDark: isDark,
                    ),
                  ),
                  Expanded(
                    child: _buildStatIndicator(
                      label: 'Out',
                      amount: stats.totalExpenses,
                      color: AppTheme.expenseRed,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.base),
              if (stats.hasData)
                _buildLineChart(context, stats.values, stats.labels, isDark)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Nothing spent in this period yet',
                      style: AppTypography.bodySmall(color: muted),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Compact Days / Months / Years switch that sits on the section title.
  Widget _buildPeriodSwitch(bool isDark) {
    const labels = ['Days', 'Months', 'Years'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(8),
        borderRadius: BorderRadius.circular(Spacing.radiusSm + 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              selected: _statsTab == i,
              button: true,
              child: GestureDetector(
                onTap: () => setState(() => _statsTab = i),
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.quick),
                  curve: Motion.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _statsTab == i
                        ? (isDark ? AppTheme.cardDarkSurface : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(Spacing.radiusSm),
                  ),
                  child: Text(
                    labels[i],
                    style: AppTypography.labelMedium(
                      color: _statsTab == i
                          ? (isDark
                              ? AppTheme.textPrimary
                              : AppTheme.textPrimaryLight)
                          : (isDark
                              ? AppTheme.textSecondary
                              : AppTheme.textSecondaryLight),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
        final now = DateTime.now();
        final isCurrentMonth = txnProvider.currentYear == now.year &&
            txnProvider.currentMonth == now.month;
        // Days that haven't happened yet aren't zero spend; leave them off.
        final shownDays = isCurrentMonth ? now.day : daysInMonth;
        final values = List<double>.generate(
          shownDays,
          (index) => dailySpending[index + 1] ?? 0.0,
        );
        final labels = List<String>.generate(
          shownDays,
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
          if (txn.countsAsIncome) {
            income += txn.amount;
          } else if (txn.type == TransactionType.expense) {
            expenses += txn.amount;
            values[txn.date.month - 1] += txn.amount;
          }
        }
        final now = DateTime.now();
        final shownMonths = year == now.year ? now.month : 12;
        return _StatsSeries(
          values: values.sublist(0, shownMonths),
          labels: _months.sublist(0, shownMonths),
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
          if (txn.countsAsIncome) {
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

  Widget _buildStatIndicator({
    required String label,
    required double amount,
    required Color color,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.bodySmall(
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        AmountText(amount, size: 17),
      ],
    );
  }

  Widget _buildLineChart(
    BuildContext context,
    List<double> values,
    List<String> labels,
    bool isDark,
  ) {
    final maxValue =
        values.isNotEmpty ? values.reduce((a, b) => a > b ? a : b) : 0.0;
    final maxSpending = maxValue > 0 ? maxValue : 100.0;
    final labelPrefix = _statsTab == 0
        ? 'Day'
        : _statsTab == 1
            ? 'Month'
            : 'Year';

    // Spoken summary for screen readers (the chart itself is not readable).
    final total = values.fold<double>(0, (a, b) => a + b);
    final peakIndex = values.isEmpty ? -1 : values.indexOf(maxValue);
    final summary = values.isEmpty
        ? 'Spending trend: no data'
        : 'Spending trend over ${values.length} periods. Total '
            '₹${total.toStringAsFixed(0)}. Highest ₹${maxValue.toStringAsFixed(0)}'
            '${peakIndex >= 0 && peakIndex < labels.length ? ' in ${labels[peakIndex]}' : ''}.';

    return Semantics(
      label: summary,
      excludeSemantics: true,
      child: _lineChartBody(values, labels, isDark, maxSpending, labelPrefix),
    );
  }

  Widget _lineChartBody(
    List<double> values,
    List<String> labels,
    bool isDark,
    double maxSpending,
    String labelPrefix,
  ) {
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
                    shouldShow = index == 0 ||
                        index == lastIndex ||
                        (index + 1) % 2 == 0;
                  } else {
                    shouldShow = index == 0 ||
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
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
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
              tooltipBorderRadius: BorderRadius.circular(12),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  if (spot.y == 0) return null;
                  final index = spot.x.toInt();
                  final label =
                      index >= 0 && index < labels.length ? labels[index] : '';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          'Recent',
          isDark,
          onSeeAll: () => HomeTabs.show(HomeTabs.history),
        ),
        const SizedBox(height: Spacing.md),
        PetSection(
          children: [
            for (final txn in transactions.take(5))
              TransactionRow(
                transaction: txn,
                category: catProvider.getCategoryById(txn.categoryId),
                showDate: true,
                onTap: () => HomeTabs.show(HomeTabs.history),
              ),
          ],
        ),
        const SizedBox(height: Spacing.sectionGap),
      ],
    );
  }

  /// Bank-SMS transactions land in the ledger, so they already show under
  /// "Recent". This only invites people who haven't turned tracking on.
  Widget _buildRecentUpiSection(
    BuildContext context,
    bool isDark,
    NumberFormat formatter,
  ) {
    return Consumer<SmsTransactionProvider>(
      builder: (context, smsProvider, _) {
        if (!smsProvider.isSupported || smsProvider.smsFeatureEnabled) {
          return const SizedBox.shrink();
        }
        return _buildUpiEnableCard(context, isDark);
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
                    _upiFeaturePill(
                      Icons.lock_outline_rounded,
                      'On-device',
                      isDark,
                    ),
                    _upiFeaturePill(Icons.bolt_rounded, 'Real-time', isDark),
                    _upiFeaturePill(
                      Icons.account_balance_outlined,
                      '15+ banks',
                      isDark,
                    ),
                    _upiFeaturePill(
                      Icons.layers_clear_outlined,
                      'No duplicates',
                      isDark,
                    ),
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

  Widget _upiFeaturePill(IconData icon, String label, bool isDark) {
    final color = isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
        borderRadius: BorderRadius.circular(Spacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
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
                color:
                    isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
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

/// A category's share of the month: icon, name, amount and a filled bar.
/// With a budget the bar shows how much of it is used; without one it
/// compares the category with the largest spend.
class _CategoryShareRow extends StatelessWidget {
  const _CategoryShareRow({
    required this.name,
    required this.icon,
    required this.color,
    required this.spent,
    required this.share,
    required this.budget,
    required this.relative,
  });

  final String name;
  final IconData icon;
  final Color color;
  final double spent;
  final double share;
  final double budget;
  final double relative;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBudget = budget > 0;
    final fill = hasBudget ? (spent / budget) : relative;
    final barColor = hasBudget ? ColorTokens.budgetUse(fill) : color;
    final secondary =
        isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
    final caption = hasBudget
        ? '${(fill * 100).round()}% of ₹${AmountText.digits(budget)}'
        : '${(share * 100).round()}% of spending';

    return Semantics(
      label: '$name, ₹${AmountText.digits(spent)}, $caption',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          children: [
            CategoryAvatar(icon: icon, color: color),
            const SizedBox(width: Spacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleSmall(
                            color: isDark
                                ? AppTheme.textPrimary
                                : AppTheme.textPrimaryLight,
                          ).copyWith(fontSize: 15),
                        ),
                      ),
                      AmountText(spent),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Stack(
                        children: [
                          Container(
                            color: isDark
                                ? Colors.white.withAlpha(14)
                                : Colors.black.withAlpha(10),
                          ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: fill.clamp(0.0, 1.0)),
                            duration: Motion.of(context, Motion.emphasized * 2),
                            curve: Motion.easeOut,
                            builder: (_, v, __) => FractionallySizedBox(
                              widthFactor: v,
                              child: Container(color: barColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.xs + 2),
                  Text(
                    caption,
                    style: AppTypography.bodySmall(color: secondary)
                        .copyWith(fontSize: 12),
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
