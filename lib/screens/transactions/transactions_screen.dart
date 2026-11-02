import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/amount_text.dart';
import 'package:pet/core/widgets/pet_section.dart';
import 'package:pet/core/widgets/transaction_row.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
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

    return Consumer2<TransactionProvider, CategoryProvider>(
      builder: (context, txnProvider, catProvider, child) {
        final transactions = txnProvider.transactions;

        // Group by calendar day, keeping the provider's sort order.
        final Map<DateTime, List<TransactionRecord>> grouped = {};
        final List<DateTime> days = [];
        for (final txn in transactions) {
          final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
          (grouped[day] ??= () {
            days.add(day);
            return <TransactionRecord>[];
          }())
              .add(txn);
        }

        return GradientBackground(
          animate: false,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(context, txnProvider, isDark),
                Expanded(
                  child: transactions.isEmpty
                      ? _buildEmptyState(context, isDark)
                      : CustomScrollView(
                          slivers: [
                            for (final day in days)
                              SliverMainAxisGroup(
                                slivers: [
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _DayHeader(
                                      label: _dayLabel(day),
                                      net: _net(grouped[day]!),
                                      background: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      Spacing.base,
                                      0,
                                      Spacing.base,
                                      Spacing.base,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: PetSection(
                                        children: [
                                          for (final txn in grouped[day]!)
                                            _dismissible(
                                              context,
                                              txnProvider,
                                              txn,
                                              TransactionRow(
                                                transaction: txn,
                                                category:
                                                    catProvider.getCategoryById(
                                                  txn.categoryId,
                                                ),
                                                onTap: () => _editTransaction(
                                                    context, txn),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: Spacing.tabBottom(context),
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

  static final DateFormat _weekdayDate = DateFormat('EEE, d MMM');
  static final DateFormat _fullDate = DateFormat('EEE, d MMM yyyy');

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return (day.year == now.year ? _weekdayDate : _fullDate).format(day);
  }

  /// Money in minus money out for the day; transfers don't count.
  double _net(List<TransactionRecord> txns) {
    var net = 0.0;
    for (final t in txns) {
      if (t.type == TransactionType.income) net += t.amount;
      if (t.type == TransactionType.expense) net -= t.amount;
    }
    return net;
  }

  Widget _buildHeader(
    BuildContext context,
    TransactionProvider txnProvider,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.screenH,
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'History',
                  style: AppTypography.displaySmall(
                    color: isDark
                        ? AppTheme.textPrimary
                        : AppTheme.textPrimaryLight,
                  ),
                ),
              ),
              _buildRecurringButton(context, isDark),
              _buildFilterButton(context, txnProvider, isDark),
              _buildSortButton(context, txnProvider, isDark),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: Spacing.xs),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                txnProvider.setSearchQuery(value);
                setState(() {});
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search merchant, note or amount',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          txnProvider.setSearchQuery('');
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
          ),
          if (_hasActiveFilters(txnProvider))
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Row(
                children: [
                  Text(
                    '${txnProvider.transactions.length} matching',
                    style: AppTypography.bodySmall(
                      color: isDark
                          ? AppTheme.textSecondary
                          : AppTheme.textSecondaryLight,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      txnProvider.clearFilters();
                      setState(() {});
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dismissible(
    BuildContext context,
    TransactionProvider txnProvider,
    TransactionRecord txn,
    Widget child,
  ) {
    return Dismissible(
      key: Key(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.expenseRed,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete transaction?'),
            content: const Text(
              'It will be removed from your history and totals.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.expenseRed,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        txnProvider.deleteTransaction(txn.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction deleted')),
        );
      },
      child: child,
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
    return IconButton(
      tooltip: 'Filter',
      onPressed: () => _showFilterSheet(context, txnProvider),
      icon: const Icon(Icons.tune_rounded, size: 22),
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
                color:
                    txnProvider.sortBy == 'date' ? AppTheme.accentPurple : null,
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
      tooltip: 'Sort',
      icon: const Icon(Icons.swap_vert_rounded, size: 22),
    );
  }

  Widget _buildRecurringButton(BuildContext context, bool isDark) {
    return IconButton(
      tooltip: 'Recurring rules',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const RecurringTransactionsScreen(),
        ),
      ),
      icon: const Icon(Icons.event_repeat_rounded, size: 22),
    );
  }

  void _showFilterSheet(BuildContext context, TransactionProvider txnProvider) {
    String? selectedCategory;
    String? selectedType;
    String? selectedPayment;
    DateTime? startDate;
    DateTime? endDate;

    showModalBottomSheet(
      useSafeArea: true,
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
                        tooltip: 'Close',
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
                    children: [
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
                                selectedPayment =
                                    selectedPayment == method ? null : method;
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

/// A day's label and net amount, pinned while its transactions scroll.
class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader(
      {required this.label, required this.net, required this.background});

  final String label;
  final double net;
  final Color background;

  static const double _height = 40;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(
        Spacing.screenH,
        0,
        Spacing.screenH,
        0,
      ),
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelLarge(color: muted),
              ),
            ),
            if (net != 0)
              AmountText(
                net,
                size: 13,
                weight: FontWeight.w500,
                color: muted,
                tone: net > 0 ? AmountTone.income : AmountTone.expense,
                showSign: true,
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeader old) =>
      old.label != label || old.net != net || old.background != background;
}
