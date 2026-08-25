import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/widgets/gradient_background.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/recurring_transaction_provider.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/screens/transactions/add_edit_transaction_screen.dart';

class RecurringTransactionsScreen extends StatelessWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recurringProvider = context.watch<RecurringTransactionProvider>();
    final catProvider = context.watch<CategoryProvider>();
    final rules = recurringProvider.allRules;

    final currFmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check Due Occurrences',
            onPressed: () async {
              final gen = await recurringProvider.checkAndGenerateDue();
              if (context.mounted) {
                if (gen.isNotEmpty) {
                  context.read<TransactionProvider>().loadTransactions();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Generated ${gen.length} due occurrences!'),
                      backgroundColor: AppTheme.incomeGreen,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All recurring transactions are up to date'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddEditTransactionScreen(),
            ),
          );
        },
        backgroundColor: AppTheme.accentTeal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Rule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: GradientBackground(
        animate: false,
        child: recurringProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : rules.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.repeat_outlined,
                            size: 64,
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Recurring Transactions',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create recurring rules for regular salaries, rent, subscriptions, or utility bills to auto-generate ledger entries.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await recurringProvider.loadRules();
                      final gen = await recurringProvider.checkAndGenerateDue();
                      if (gen.isNotEmpty && context.mounted) {
                        context.read<TransactionProvider>().loadTransactions();
                      }
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.all(Spacing.base),
                      itemCount: rules.length,
                      itemBuilder: (context, index) {
                        final rule = rules[index];
                        final category = catProvider.getCategoryById(rule.categoryId);
                        final isExpense = rule.type == TransactionType.expense;
                        final amountColor = isExpense ? ColorTokens.expense : ColorTokens.income;

                        return Container(
                          margin: const EdgeInsets.only(bottom: Spacing.md),
                          padding: const EdgeInsets.all(Spacing.cardPadding),
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? ColorTokens.darkCardGradient
                                : ColorTokens.lightCardGradient,
                            borderRadius: BorderRadius.circular(Spacing.cardRadius),
                            border: Border.all(
                              color: isDark ? ColorTokens.darkBorder : ColorTokens.lightBorder,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isDark ? Colors.black : Colors.grey).withAlpha(
                                  isDark ? 20 : 10,
                                ),
                                blurRadius: 16,
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
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: (category?.color ?? Colors.grey).withAlpha(
                                        isDark ? 30 : 20,
                                      ),
                                      borderRadius: BorderRadius.circular(Spacing.chipRadius),
                                    ),
                                    child: Icon(
                                      category?.icon ?? Icons.category,
                                      color: category?.color ?? Colors.grey,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          category?.name ?? 'Unknown',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          rule.note.isNotEmpty
                                              ? rule.note
                                              : (rule.merchantName ?? rule.frequency.displayName),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDark
                                                ? AppTheme.textSecondary
                                                : AppTheme.textSecondaryLight,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${isExpense ? '-' : '+'}${currFmt.format(rule.amount)}',
                                        style: TextStyle(
                                          color: amountColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: rule.isActive
                                              ? AppTheme.accentTeal.withAlpha(25)
                                              : Colors.grey.withAlpha(30),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          rule.isActive ? rule.frequency.displayName : 'Paused',
                                          style: TextStyle(
                                            color: rule.isActive ? AppTheme.accentTeal : Colors.grey,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 14,
                                        color: AppTheme.textTertiary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Next: ${dateFmt.format(rule.nextOccurrenceDate)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? AppTheme.textSecondary
                                              : AppTheme.textSecondaryLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    onSelected: (action) => _handleAction(
                                      context,
                                      action,
                                      rule,
                                      recurringProvider,
                                    ),
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 18),
                                            SizedBox(width: 8),
                                            Text('Edit Rule'),
                                          ],
                                        ),
                                      ),
                                      if (rule.isActive) ...[
                                        const PopupMenuItem(
                                          value: 'skip',
                                          child: Row(
                                            children: [
                                              Icon(Icons.skip_next, size: 18),
                                              SizedBox(width: 8),
                                              Text('Skip Next Occurrence'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'pause',
                                          child: Row(
                                            children: [
                                              Icon(Icons.pause, size: 18),
                                              SizedBox(width: 8),
                                              Text('Pause Rule'),
                                            ],
                                          ),
                                        ),
                                      ] else ...[
                                        const PopupMenuItem(
                                          value: 'resume',
                                          child: Row(
                                            children: [
                                              Icon(Icons.play_arrow, size: 18),
                                              SizedBox(width: 8),
                                              Text('Resume Rule'),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, size: 18, color: AppTheme.expenseRed),
                                            SizedBox(width: 8),
                                            Text('Delete Rule', style: TextStyle(color: AppTheme.expenseRed)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  void _handleAction(
    BuildContext context,
    String action,
    RecurringRule rule,
    RecurringTransactionProvider provider,
  ) async {
    switch (action) {
      case 'edit':
        _showEditRuleDialog(context, rule, provider);
        break;
      case 'skip':
        await provider.skipOccurrence(
          ruleId: rule.id,
          scheduledDate: rule.nextOccurrenceDate,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Next occurrence skipped')),
          );
        }
        break;
      case 'pause':
        await provider.stopRule(rule.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rule paused')),
          );
        }
        break;
      case 'resume':
        await provider.updateRule(rule.copyWith(isActive: true));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rule resumed')),
          );
        }
        break;
      case 'delete':
        final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Recurring Rule'),
            content: const Text(
              'Do you want to delete this recurring rule? Existing transactions already logged will be kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expenseRed),
                child: const Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (shouldDelete == true) {
          await provider.stopRule(rule.id);
          // Soft delete / stop or delete
          await provider.deleteRuleAndAllOccurrences(rule.id);
          if (context.mounted) {
            context.read<TransactionProvider>().loadTransactions();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recurring rule deleted')),
            );
          }
        }
        break;
    }
  }

  void _showEditRuleDialog(
    BuildContext context,
    RecurringRule rule,
    RecurringTransactionProvider provider,
  ) {
    final amountController = TextEditingController(text: rule.amount.toStringAsFixed(0));
    final noteController = TextEditingController(text: rule.note);
    RecurringFrequency selectedFreq = rule.frequency;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit Recurring Rule',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Frequency',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: RecurringFrequency.values.map((freq) {
                    final isSel = selectedFreq == freq;
                    return ChoiceChip(
                      label: Text(freq.displayName),
                      selected: isSel,
                      onSelected: (_) {
                        setSheetState(() => selectedFreq = freq);
                      },
                      selectedColor: AppTheme.accentTeal.withAlpha(50),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final parsedAmount = double.tryParse(amountController.text);
                      if (parsedAmount == null || parsedAmount <= 0) return;

                      Navigator.pop(ctx);
                      await provider.updateRule(
                        rule.copyWith(
                          amount: parsedAmount,
                          note: noteController.text,
                          frequency: selectedFreq,
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Recurring rule updated')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentTeal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
