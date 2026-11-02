import 'package:flutter/material.dart';
import 'package:pet/screens/budget/shared_budgets_screen.dart';
import 'package:provider/provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/motion.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/amount_text.dart';
import 'package:pet/core/widgets/category_avatar.dart';
import 'package:pet/core/widgets/pet_section.dart';
import 'package:pet/core/widgets/budget_progress_bar.dart';

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

        return SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              Spacing.tabBottom(context, fab: false),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, budgetProvider),
                const SizedBox(height: Spacing.base),

                // Overall budget summary
                if (budgets.isNotEmpty) ...[
                  _buildSummary(context, totalBudget, totalSpent),
                  const SizedBox(height: Spacing.base),
                ],

                // Over-budget alert
                if (budgetProvider.getOverBudgetCategories().isNotEmpty) ...[
                  _buildOverBudgetNote(
                    budgetProvider.getOverBudgetCategories().length,
                  ),
                  const SizedBox(height: Spacing.base),
                ],

                // Category budgets
                if (budgets.isEmpty)
                  _buildEmptyState(context, isDark, catProvider, budgetProvider)
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'CATEGORIES',
                            style: AppTypography.overline(
                              color: isDark
                                  ? AppTheme.textTertiary
                                  : AppTheme.textSecondaryLight,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showAddBudgetDialog(
                            context,
                            catProvider,
                            budgetProvider,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
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
                ],
                const SizedBox(height: Spacing.base),
                PetSection(
                  children: [
                    PetRow(
                      title: 'Household budgets',
                      subtitle: 'Share a monthly budget with family',
                      leading: const CategoryAvatar(
                        icon: Icons.home_rounded,
                        color: AppTheme.accentPurple,
                      ),
                      showChevron: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SharedBudgetsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, BudgetProvider budgetProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    void shift(int delta) {
      var m = budgetProvider.currentMonth + delta;
      var y = budgetProvider.currentYear;
      if (m < 1) {
        m = 12;
        y--;
      } else if (m > 12) {
        m = 1;
        y++;
      }
      budgetProvider.setMonth(m, y);
    }

    return Row(
      children: [
        Expanded(
          child: Text('Budget', style: AppTypography.displaySmall(color: text)),
        ),
        IconButton(
          tooltip: 'Previous month',
          visualDensity: VisualDensity.compact,
          onPressed: () => shift(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '${_months[budgetProvider.currentMonth - 1].substring(0, 3)} '
          '${budgetProvider.currentYear}',
          style: AppTypography.labelLarge(color: text)
              .copyWith(fontFeatures: AppTypography.tabularFigures),
        ),
        IconButton(
          tooltip: 'Next month',
          visualDensity: VisualDensity.compact,
          onPressed: () => shift(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _buildSummary(
    BuildContext context,
    double totalBudget,
    double totalSpent,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final used = totalBudget > 0 ? totalSpent / totalBudget : 0.0;
    final left = totalBudget - totalSpent;
    final muted = isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentPurple.withAlpha(40),
            AppTheme.accentTeal.withAlpha(20),
          ],
        ),
        borderRadius: BorderRadius.circular(Spacing.radiusLg),
        border: Border.all(color: AppTheme.accentPurple.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SPENT THIS MONTH', style: AppTypography.overline(color: muted)),
          const SizedBox(height: Spacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AmountText(totalSpent, size: 32),
              const SizedBox(width: Spacing.sm),
              Text(
                'of \u20B9${AmountText.digits(totalBudget)}',
                style: AppTypography.bodyMedium(color: muted)
                    .copyWith(fontFeatures: AppTypography.tabularFigures),
              ),
            ],
          ),
          const SizedBox(height: Spacing.base),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: used.clamp(0.0, 1.0)),
              duration: Motion.of(context, Motion.emphasized * 2),
              curve: Motion.easeOut,
              builder: (context, value, child) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: isDark
                    ? Colors.white.withAlpha(16)
                    : Colors.black.withAlpha(12),
                valueColor: AlwaysStoppedAnimation(ColorTokens.budgetUse(used)),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            left >= 0
                ? '\u20B9${AmountText.digits(left)} left \u00B7 '
                    '${(used * 100).round()}% used'
                : '\u20B9${AmountText.digits(-left)} over budget',
            style: AppTypography.bodySmall(
              color: left >= 0 ? muted : AppTheme.expenseRed,
            ).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: AppTypography.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverBudgetNote(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.expenseRed.withAlpha(20),
        borderRadius: BorderRadius.circular(Spacing.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.expenseRed,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? '1 category is over budget'
                  : '$count categories are over budget',
              style: const TextStyle(
                color: AppTheme.expenseRed,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildEmptyState(
    BuildContext context,
    bool isDark,
    CategoryProvider catProvider,
    BudgetProvider budgetProvider,
  ) {
    final muted = isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(Spacing.radiusLg),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withAlpha(8), width: 1),
      ),
      child: Column(
        children: [
          const CategoryAvatar(
            icon: Icons.donut_large_rounded,
            color: AppTheme.accentPurple,
            size: 56,
          ),
          const SizedBox(height: Spacing.base),
          Text(
            'No budgets yet',
            style: AppTypography.titleLarge(
              color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
            ),
          ),
          const SizedBox(height: Spacing.xs + 2),
          Text(
            'Give a category a monthly limit and P.E.T will show how much is '
            'left and warn you before you go over.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium(color: muted),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton.icon(
            onPressed: () =>
                _showAddBudgetDialog(context, catProvider, budgetProvider),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Set a budget'),
          ),
        ],
      ),
    );
  }
}
