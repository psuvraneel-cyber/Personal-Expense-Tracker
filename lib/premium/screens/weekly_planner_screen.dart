import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

class WeeklyPlannerScreen extends StatefulWidget {
  const WeeklyPlannerScreen({super.key});

  @override
  State<WeeklyPlannerScreen> createState() => _WeeklyPlannerScreenState();
}

class _WeeklyPlannerScreenState extends State<WeeklyPlannerScreen> {
  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  List<dynamic>? _lastSyncedTransactions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final planner = context.read<WeeklyPlannerProvider>();
      final txns = context.read<TransactionProvider>().allTransactions;
      _lastSyncedTransactions = txns;
      planner.load().then((_) => planner.refreshFromTransactions(txns));
    });
  }

  // Called by the Consumer2 whenever TransactionProvider changes.
  void _syncPlanner(
    WeeklyPlannerProvider planner,
    TransactionProvider txnProvider,
  ) {
    if (identical(_lastSyncedTransactions, txnProvider.allTransactions)) return;
    _lastSyncedTransactions = txnProvider.allTransactions;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      planner.refreshFromTransactions(txnProvider.allTransactions);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Weekly Planner'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          IconButton(
            onPressed: () => _showSetLimit(context, isDark),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.accentTeal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.edit_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PremiumGate(
        title: 'Weekly Planner',
        subtitle: 'Set per-category weekly limits and track daily spending.',
        child: Consumer2<WeeklyPlannerProvider, TransactionProvider>(
          builder: (context, planner, txnProvider, _) {
            // Sync planner after the frame — never call notifyListeners inside a builder.
            _syncPlanner(planner, txnProvider);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                _buildWeekHeader(context, planner, isDark),
                const SizedBox(height: 16),
                _buildDayStrip(context, planner, isDark),
                const SizedBox(height: 20),
                if (planner.entries.isEmpty)
                  _buildEmptyPrompt(isDark)
                else ...[
                  Text(
                    'Category Limits',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...planner.entries.map(
                    (e) => _buildCategoryCard(context, e, planner, isDark),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWeekHeader(
    BuildContext context,
    WeeklyPlannerProvider planner,
    bool isDark,
  ) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final dateFmt = DateFormat('dd MMM');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accentTeal.withAlpha(isDark ? 60 : 40),
            AppTheme.accentPurple.withAlpha(isDark ? 40 : 25),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentTeal.withAlpha(isDark ? 50 : 35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${dateFmt.format(monday)} – ${dateFmt.format(sunday)}',
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This Week Spent',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      _fmt.format(planner.totalWeekSpent),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (planner.hasLimits) ...[
                Container(
                  width: 1,
                  height: 44,
                  color: Colors.white.withAlpha(25),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekly Limit',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _fmt.format(planner.totalWeekLimit),
                        style: TextStyle(
                          color: planner.totalWeekSpent > planner.totalWeekLimit
                              ? AppTheme.expenseRed
                              : Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (planner.hasLimits) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: planner.totalWeekLimit > 0
                    ? (planner.totalWeekSpent / planner.totalWeekLimit).clamp(
                        0,
                        1,
                      )
                    : 0,
                minHeight: 8,
                backgroundColor: Colors.white.withAlpha(30),
                valueColor: AlwaysStoppedAnimation(
                  planner.totalWeekSpent > planner.totalWeekLimit
                      ? AppTheme.expenseRed
                      : Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayStrip(
    BuildContext context,
    WeeklyPlannerProvider planner,
    bool isDark,
  ) {
    final now = DateTime.now();
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxSpend = planner.weekDays.isEmpty
        ? 1.0
        : planner.weekDays.fold<double>(
            1.0,
            (m, d) => d.spent > m ? d.spent : m,
          );

    if (planner.weekDays.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Spend',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: planner.weekDays.map((day) {
            final isToday =
                day.date.year == now.year &&
                day.date.month == now.month &&
                day.date.day == now.day;
            final barFraction = maxSpend > 0 ? day.spent / maxSpend : 0.0;
            final barColor = isToday
                ? AppTheme.accentPurple
                : AppTheme.accentTeal;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    if (day.spent > 0)
                      Text(
                        NumberFormat.compact(locale: 'en_IN').format(day.spent),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      height: 64.0 * barFraction.clamp(0.05, 1.0),
                      decoration: BoxDecoration(
                        color: barColor.withAlpha(isDark ? 180 : 150),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dayLabels[day.date.weekday - 1],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        color: isToday
                            ? AppTheme.accentPurple
                            : AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    dynamic entry,
    WeeklyPlannerProvider planner,
    bool isDark,
  ) {
    final isOver = entry.isOverBudget;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOver
              ? AppTheme.expenseRed.withAlpha(40)
              : (isDark
                    ? Colors.white.withAlpha(10)
                    : Colors.black.withAlpha(7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                entry.categoryName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (isOver)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.expenseRed.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Over limit',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.expenseRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Text(
                  '${_fmt.format(entry.remaining)} left',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.incomeGreen,
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => planner.removeLimit(entry.categoryId),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 8,
              backgroundColor: isDark
                  ? Colors.white.withAlpha(12)
                  : Colors.black.withAlpha(7),
              valueColor: AlwaysStoppedAnimation(
                isOver ? AppTheme.expenseRed : AppTheme.accentTeal,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmt.format(entry.weeklySpent),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isOver ? AppTheme.expenseRed : AppTheme.accentTeal,
                ),
              ),
              Text(
                '/ ${_fmt.format(entry.weeklyLimit)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPrompt(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.accentTeal.withAlpha(isDark ? 40 : 28),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_view_week_rounded,
                size: 36,
                color: AppTheme.accentTeal,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Weekly Limits Set',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Set per-category weekly limits to stay on track.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showSetLimit(context, isDark),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Set Limit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentTeal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSetLimit(BuildContext context, bool isDark) async {
    final categories = context.read<CategoryProvider>().categories;
    if (categories.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No categories found.')));
      return;
    }
    String? selectedCategoryId = categories.first.id;
    final limitCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set Weekly Limit',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: categories
                    .map((c) => c.id)
                    .toSet()
                    .map((id) {
                      final c = categories.firstWhere((cat) => cat.id == id);
                      return DropdownMenuItem(value: c.id, child: Text(c.name));
                    })
                    .toList(),
                onChanged: (v) => setS(() => selectedCategoryId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Weekly limit (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final id = selectedCategoryId;
                    final limit = double.tryParse(limitCtrl.text.trim()) ?? 0;
                    if (id == null || limit <= 0) return;
                    final catName = categories
                        .firstWhere((c) => c.id == id)
                        .name;
                    // Read fresh from the outer screen context — not from ctx
                    // (the sheet's inner context) which will be disposed on pop.
                    context.read<WeeklyPlannerProvider>().setLimit(
                      categoryId: id,
                      categoryName: catName,
                      weeklyLimit: limit,
                    );
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentTeal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save Limit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
