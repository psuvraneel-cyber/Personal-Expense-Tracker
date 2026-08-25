import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/widgets/expense_card.dart';
import 'package:pet/core/widgets/gradient_background.dart';
import 'package:pet/screens/transactions/add_edit_transaction_screen.dart';
import 'package:pet/screens/transactions/recurring_transactions_screen.dart';
import 'package:pet/widgets/empty_state_widget.dart';
import 'package:intl/intl.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateGroupFmt = DateFormat('dd MMM yyyy');

    return Consumer2<TransactionProvider, CategoryProvider>(
      builder: (context, txnProvider, catProvider, child) {
        final transactions = txnProvider.transactions;

        // Group by date — build keys and lists in one pass
        final Map<String, List<dynamic>> grouped = {};
        final List<String> dateKeys = [];
        for (final txn in transactions) {
          final key = dateGroupFmt.format(txn.date);
          if (!grouped.containsKey(key)) {
            grouped[key] = [];
            dateKeys.add(key);
          }
          grouped[key]!.add(txn);
        }

        return GradientBackground(
          animate: false,
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.base,
                  Spacing.sm,
                  Spacing.base,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          txnProvider.setSearchQuery(value);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search transactions...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    txnProvider.setSearchQuery('');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildRecurringButton(context, isDark),
                    const SizedBox(width: 8),
                    _buildFilterButton(context, txnProvider, isDark),
                    const SizedBox(width: 8),
                    _buildSortButton(context, txnProvider, isDark),
                  ],
                ),
              ),
              // Active filters indicator
              if (_hasActiveFilters(txnProvider))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentPurple.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.filter_alt,
                              size: 14,
                              color: AppTheme.accentPurple,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Filters active',
                              style: TextStyle(
                                color: AppTheme.accentPurple,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => txnProvider.clearFilters(),
                        child: const Text(
                          'Clear all',
                          style: TextStyle(
                            color: AppTheme.expenseRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              // Transaction list
              Expanded(
                child: transactions.isEmpty
                    ? _buildEmptyState(context, isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: 100,
                        ),
                        itemCount: dateKeys.length,
                        itemBuilder: (context, index) {
                          final dateKey = dateKeys[index];
                          final dayTransactions = grouped[dateKey]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  dateKey,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              ...dayTransactions.map((txn) {
                                final cat = catProvider.getCategoryById(
                                  txn.categoryId,
                                );
                                return Dismissible(
                                  key: Key(txn.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.expenseRed,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white,
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    return await showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete Transaction'),
                                        content: const Text(
                                          'Are you sure you want to delete this transaction?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            child: const Text(
                                              'Delete',
                                              style: TextStyle(
                                                color: AppTheme.expenseRed,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  onDismissed: (direction) {
                                    txnProvider.deleteTransaction(txn.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          'Transaction deleted',
                                        ),
                                        backgroundColor: AppTheme.expenseRed,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  child: ExpenseCard(
                                    transaction: txn,
                                    category: cat,
                                    onTap: () => _editTransaction(context, txn),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _hasActiveFilters(TransactionProvider txnProvider) {
    return txnProvider.searchQuery.isNotEmpty;
  }

  Widget _buildFilterButton(
    BuildContext context,
    TransactionProvider txnProvider,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () => _showFilterSheet(context, txnProvider),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(15)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: const Icon(Icons.filter_list, size: 20),
      ),
    );
  }

  Widget _buildSortButton(
    BuildContext context,
    TransactionProvider txnProvider,
    bool isDark,
  ) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        txnProvider.setSortBy(value);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'date',
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: txnProvider.sortBy == 'date'
                    ? AppTheme.accentPurple
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Sort by Date',
                style: TextStyle(
                  color: txnProvider.sortBy == 'date'
                      ? AppTheme.accentPurple
                      : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'amount',
          child: Row(
            children: [
              Icon(
                Icons.currency_rupee,
                size: 16,
                color: txnProvider.sortBy == 'amount'
                    ? AppTheme.accentPurple
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Sort by Amount',
                style: TextStyle(
                  color: txnProvider.sortBy == 'amount'
                      ? AppTheme.accentPurple
                      : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'category',
          child: Row(
            children: [
              Icon(
                Icons.category,
                size: 16,
                color: txnProvider.sortBy == 'category'
                    ? AppTheme.accentPurple
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Sort by Category',
                style: TextStyle(
                  color: txnProvider.sortBy == 'category'
                      ? AppTheme.accentPurple
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(15)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: const Icon(Icons.sort, size: 20),
      ),
    );
  }

  Widget _buildRecurringButton(BuildContext context, bool isDark) {
    return Tooltip(
      message: 'Recurring Rules',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RecurringTransactionsScreen(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(15)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: const Icon(Icons.repeat, size: 20, color: AppTheme.accentTeal),
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, TransactionProvider txnProvider) {
    String? selectedCategory;
    String? selectedType;
    String? selectedPayment;
    DateTime? startDate;
    DateTime? endDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.cardDark
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Type filter
                  Text('Type', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: selectedType == null,
                        onSelected: (_) {
                          setSheetState(() => selectedType = null);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Income'),
                        selected: selectedType == 'income',
                        onSelected: (_) {
                          setSheetState(() => selectedType = 'income');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Expense'),
                        selected: selectedType == 'expense',
                        onSelected: (_) {
                          setSheetState(() => selectedType = 'expense');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Payment method filter
                  Text(
                    'Payment Method',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        [
                              'UPI',
                              'Credit Card',
                              'Debit Card',
                              'Cash',
                              'Bank Transfer',
                              'Net Banking',
                              'PayPal',
                            ]
                            .map(
                              (method) => ChoiceChip(
                                label: Text(method),
                                selected: selectedPayment == method,
                                onSelected: (_) {
                                  setSheetState(() {
                                    selectedPayment = selectedPayment == method
                                        ? null
                                        : method;
                                  });
                                },
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 16),

                  // Date range
                  Text(
                    'Date Range',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setSheetState(() => startDate = date);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: Text(
                            startDate != null
                                ? DateFormat('dd/MM/yy').format(startDate!)
                                : 'From',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setSheetState(() => endDate = date);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: Text(
                            endDate != null
                                ? DateFormat('dd/MM/yy').format(endDate!)
                                : 'To',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Apply button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        txnProvider.setFilters(
                          categoryId: selectedCategory,
                          type: selectedType,
                          paymentMethod: selectedPayment,
                          startDate: startDate,
                          endDate: endDate,
                        );
                        Navigator.pop(context);
                      },
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _editTransaction(BuildContext context, dynamic transaction) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddEditTransactionScreen(transaction: transaction),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return const EmptyStateWidget(
      icon: Icons.receipt_long_outlined,
      title: 'No transactions yet',
      subtitle: 'Start tracking your spending by\ntapping the + button below.',
      ctaLabel: 'Add Transaction',
    );
  }
}
