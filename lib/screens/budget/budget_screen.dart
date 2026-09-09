import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/widgets/budget_progress_bar.dart';
import 'package:intl/intl.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final List<String> _months = [
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

  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer2<BudgetProvider, CategoryProvider>(
      builder: (context, budgetProvider, catProvider, child) {
        final budgets = budgetProvider.budgets;
        final totalBudget = budgets.fold(0.0, (sum, b) => sum + b.amount);
        final totalSpent = budgetProvider.spentAmounts.values.fold(
          0.0,
          (sum, s) => sum + s,
        );
        final formatter = _formatter;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month selector
              _buildMonthSelector(context, budgetProvider),
              const SizedBox(height: 20),

              // Overall budget summary
              if (budgets.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.accentPurple.withAlpha(40),
                        AppTheme.accentTeal.withAlpha(20),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.accentPurple.withAlpha(60),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Budget',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                formatter.format(totalBudget),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Spent',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                formatter.format(totalSpent),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: totalSpent > totalBudget
                                          ? AppTheme.expenseRed
                                          : AppTheme.incomeGreen,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: totalBudget > 0
                              ? (totalSpent / totalBudget).clamp(0.0, 1.0)
                              : 0.0,
                        ),
                        duration: const Duration(milliseconds: 1000),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 10,
                              backgroundColor: isDark
                                  ? AppTheme.surfaceDark
                                  : const Color(0xFFE2E8F0),
                              valueColor: AlwaysStoppedAnimation(
                                value < 0.7
                                    ? AppTheme.incomeGreen
                                    : value < 0.9
                                        ? AppTheme.warningYellow
                                        : AppTheme.expenseRed,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        totalBudget > totalSpent
                            ? '${formatter.format(totalBudget - totalSpent)} remaining'
                            : 'Over budget by ${formatter.format(totalSpent - totalBudget)}',
                        style: TextStyle(
                          color: totalBudget > totalSpent
                              ? AppTheme.incomeGreen
                              : AppTheme.expenseRed,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Over-budget alerts
              if (budgetProvider.getOverBudgetCategories().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.expenseRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.expenseRed.withAlpha(60),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.expenseRed,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${budgetProvider.getOverBudgetCategories().length} categor${budgetProvider.getOverBudgetCategories().length == 1 ? 'y' : 'ies'} over budget!',
                          style: const TextStyle(
                            color: AppTheme.expenseRed,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Category budgets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Category Budgets',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  IconButton(
                    onPressed: () => _showAddBudgetDialog(
                      context,
                      catProvider,
                      budgetProvider,
                    ),
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.accentPurple,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (budgets.isEmpty)
                _buildEmptyState(context, isDark)
              else
                ...budgets.map((budget) {
                  final cat = catProvider.getCategoryById(budget.categoryId);
                  final spent = budgetProvider.getSpentForCategory(
                    budget.categoryId,
                  );
                  return BudgetProgressBar(
                    categoryName: cat?.name ?? 'Unknown',
                    categoryIcon: cat?.icon ?? Icons.category,
                    categoryColor: cat?.color ?? Colors.grey,
                    budgetAmount: budget.amount,
                    spentAmount: spent,
                    onTap: () => _showEditBudgetDialog(
                      context,
                      budget,
                      cat,
                      budgetProvider,
                    ),
                  );
                }),

              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMonthSelector(
    BuildContext context,
    BudgetProvider budgetProvider,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () {
            int m = budgetProvider.currentMonth - 1;
            int y = budgetProvider.currentYear;
            if (m < 1) {
              m = 12;
              y--;
            }
            budgetProvider.setMonth(m, y);
          },
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
          ),
        ),
        Text(
          '${_months[budgetProvider.currentMonth - 1]} ${budgetProvider.currentYear}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        IconButton(
          onPressed: () {
            int m = budgetProvider.currentMonth + 1;
            int y = budgetProvider.currentYear;
            if (m > 12) {
              m = 1;
              y++;
            }
            budgetProvider.setMonth(m, y);
          },
          icon: Icon(
            Icons.chevron_right,
            color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
          ),
        ),
      ],
    );
  }

  void _showAddBudgetDialog(
    BuildContext context,
    CategoryProvider catProvider,
    BudgetProvider budgetProvider,
  ) {
    String? selectedCategoryId;
    final amountController = TextEditingController();
    final expenseCategories = catProvider.expenseCategories;

    // Filter out categories that already have budgets
    final existingBudgetCatIds =
        budgetProvider.budgets.map((b) => b.categoryId).toSet();
    final availableCategories = expenseCategories
        .where((c) => !existingBudgetCatIds.contains(c.id))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Set Budget'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (availableCategories.isEmpty)
                    const Text('All categories already have budgets set.')
                  else ...[
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Category'),
                      initialValue: selectedCategoryId,
                      items: availableCategories
                          .map(
                            (cat) => DropdownMenuItem(
                              value: cat.id,
                              child: Row(
                                children: [
                                  Icon(cat.icon, color: cat.color, size: 18),
                                  const SizedBox(width: 8),
                                  Text(cat.name),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedCategoryId = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Budget Amount (₹)',
                        prefixText: '₹ ',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                if (availableCategories.isNotEmpty)
                  ElevatedButton(
                    onPressed: () {
                      if (selectedCategoryId != null &&
                          amountController.text.isNotEmpty) {
                        final amount = double.tryParse(amountController.text);
                        if (amount != null && amount > 0) {
                          budgetProvider.setBudget(
                            categoryId: selectedCategoryId!,
                            amount: amount,
                          );
                          Navigator.pop(ctx);
                        }
                      }
                    },
                    child: const Text('Set Budget'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditBudgetDialog(
    BuildContext context,
    dynamic budget,
    dynamic cat,
    BudgetProvider budgetProvider,
  ) {
    final amountController = TextEditingController(
      text: budget.amount.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Edit ${cat?.name ?? "Budget"}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Budget Amount (₹)',
                  prefixText: '₹ ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                budgetProvider.deleteBudget(budget.categoryId);
                Navigator.pop(ctx);
              },
              child: const Text(
                'Remove',
                style: TextStyle(color: AppTheme.expenseRed),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount != null && amount > 0) {
                  budgetProvider.setBudget(
                    categoryId: budget.categoryId,
                    amount: amount,
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.pie_chart_outline,
              size: 80,
              color: isDark ? AppTheme.textTertiary : AppTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No budgets set',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: isDark
                        ? AppTheme.textSecondary
                        : AppTheme.textSecondaryLight,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to set your first category budget',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
