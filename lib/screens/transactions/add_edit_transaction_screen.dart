import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/widgets/gradient_background.dart';
import 'package:pet/core/widgets/category_chip.dart';
import 'package:intl/intl.dart';
import 'package:pet/premium/services/tax_category_service.dart';
import 'package:pet/premium/services/spend_pause_service.dart';

class AddEditTransactionScreen extends StatefulWidget {
  final TransactionRecord? transaction;
  final double? prefillAmount;
  final String? prefillType;

  const AddEditTransactionScreen({
    super.key,
    this.transaction,
    this.prefillAmount,
    this.prefillType,
  });

  @override
  State<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState extends State<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  String? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  PaymentMethod _paymentMethod = PaymentMethod.upi;
  bool _isRecurring = false;
  RecurringFrequency _recurringFrequency = RecurringFrequency.monthly;
  String? _taxCategory;

  bool get _isEditing => widget.transaction != null;

  final List<Map<String, dynamic>> _paymentIcons = [
    {'method': 'UPI', 'icon': Icons.phone_android},
    {'method': 'Credit Card', 'icon': Icons.credit_card},
    {'method': 'Debit Card', 'icon': Icons.credit_card_outlined},
    {'method': 'Cash', 'icon': Icons.payments_outlined},
    {'method': 'Bank Transfer', 'icon': Icons.account_balance},
    {'method': 'Net Banking', 'icon': Icons.language},
    {'method': 'PayPal', 'icon': Icons.paypal_outlined},
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final txn = widget.transaction!;
      _amountController.text = txn.amount.toStringAsFixed(0);
      _noteController.text = txn.note;
      _type = txn.type;
      _selectedCategoryId = txn.categoryId;
      _selectedDate = txn.date;
      _paymentMethod = txn.paymentMethod;
      _isRecurring = txn.isRecurring;
      _recurringFrequency =
          txn.recurringFrequency ?? RecurringFrequency.monthly;
      _taxCategory = txn.taxCategory;
    } else if (widget.prefillAmount != null) {
      _amountController.text = widget.prefillAmount!.toStringAsFixed(0);
      if (widget.prefillType != null) {
        _type = TransactionType.fromJson(widget.prefillType);
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catProvider = context.watch<CategoryProvider>();
    final categories = _type == TransactionType.expense
        ? catProvider.expenseCategories
        : catProvider.incomeCategories;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction'),
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _deleteTransaction,
              icon: const Icon(
                Icons.delete_outline,
                color: AppTheme.expenseRed,
              ),
            ),
        ],
      ),
      body: GradientBackground(
        animate: false,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Income/Expense toggle
                _buildTypeToggle(isDark),
                const SizedBox(height: 24),

                // Amount
                Text(
                  'Amount (₹)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: _type == TransactionType.expense
                        ? AppTheme.expenseRed
                        : AppTheme.incomeGreen,
                  ),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: TextStyle(
                      color: _type == TransactionType.expense
                          ? AppTheme.expenseRed
                          : AppTheme.incomeGreen,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    hintText: '0',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Enter amount';
                    final num = double.tryParse(value);
                    if (num == null || num <= 0) return 'Enter a valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Category
                Text(
                  'Category',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _buildCategoryGrid(categories, isDark),
                const SizedBox(height: 24),

                // Payment method
                Text(
                  'Payment Method',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _buildPaymentMethodSelector(isDark),
                const SizedBox(height: 24),

                // Date
                Text('Date', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildDatePicker(context, isDark),
                const SizedBox(height: 24),

                // Note
                Text(
                  'Note (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(hintText: 'Add a note...'),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Tax category
                Text(
                  'Tax Category (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: TaxCategoryService.defaults.any((e) => e.id == _taxCategory) 
                      ? _taxCategory 
                      : null,
                  decoration: const InputDecoration(
                    hintText: 'Select tax category',
                  ),
                  items: TaxCategoryService.defaults
                      .map(
                        (t) => DropdownMenuItem<String>(
                          value: t.id,
                          child: Text(t.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _taxCategory = value),
                ),
                const SizedBox(height: 24),

                // Recurring
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.cardDark : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withAlpha(15)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.repeat,
                                color: AppTheme.accentTeal,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Recurring Transaction',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          Switch(
                            value: _isRecurring,
                            onChanged: (value) {
                              setState(() => _isRecurring = value);
                            },
                            activeThumbColor: AppTheme.accentTeal,
                          ),
                        ],
                      ),
                      if (_isRecurring) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: RecurringFrequency.values.map((freq) {
                            final isSelected = _recurringFrequency == freq;
                            return ChoiceChip(
                              label: Text(freq.displayName),
                              selected: isSelected,
                              onSelected: (_) {
                                setState(() => _recurringFrequency = freq);
                              },
                              selectedColor: AppTheme.accentTeal.withAlpha(50),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _type == TransactionType.expense
                          ? ColorTokens.expenseGradient
                          : ColorTokens.incomeGradient,
                      borderRadius: BorderRadius.circular(Spacing.chipRadius),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (_type == TransactionType.expense
                                      ? ColorTokens.expense
                                      : ColorTokens.income)
                                  .withAlpha(60),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _saveTransaction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      child: Text(
                        _isEditing ? 'Update Transaction' : 'Save Transaction',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _type = TransactionType.expense;
                _selectedCategoryId = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _type == TransactionType.expense
                      ? AppTheme.expenseRed
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    'Expense',
                    style: TextStyle(
                      color: _type == TransactionType.expense
                          ? Colors.white
                          : (isDark
                                ? AppTheme.textSecondary
                                : AppTheme.textSecondaryLight),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _type = TransactionType.income;
                _selectedCategoryId = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _type == TransactionType.income
                      ? AppTheme.incomeGreen
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    'Income',
                    style: TextStyle(
                      color: _type == TransactionType.income
                          ? Colors.white
                          : (isDark
                                ? AppTheme.textSecondary
                                : AppTheme.textSecondaryLight),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(List<dynamic> categories, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        final isSelected = _selectedCategoryId == cat.id;
        return CategoryChip(
          label: cat.name,
          icon: cat.icon,
          color: cat.color,
          isSelected: isSelected,
          useGradient: true,
          onTap: () => setState(() => _selectedCategoryId = cat.id),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethodSelector(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _paymentIcons.map((item) {
        final isSelected = _paymentMethod.displayName == item['method'];
        return GestureDetector(
          onTap: () => setState(
            () => _paymentMethod = PaymentMethod.fromJson(
              item['method'] as String,
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accentPurple.withAlpha(30)
                  : (isDark ? AppTheme.cardDark : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppTheme.accentPurple
                    : (isDark
                          ? Colors.white.withAlpha(15)
                          : const Color(0xFFE2E8F0)),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item['icon'] as IconData,
                  color: isSelected
                      ? AppTheme.accentPurple
                      : (isDark
                            ? AppTheme.textSecondary
                            : AppTheme.textSecondaryLight),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  item['method'] as String,
                  style: TextStyle(
                    color: isSelected
                        ? AppTheme.accentPurple
                        : (isDark
                              ? AppTheme.textSecondary
                              : AppTheme.textSecondaryLight),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDatePicker(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate.isAfter(DateTime.now())
              ? DateTime.now()
              : _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(), // No future dates allowed
        );
        if (date != null && context.mounted) {
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(_selectedDate),
          );
          setState(() {
            _selectedDate = DateTime(
              date.year,
              date.month,
              date.day,
              time?.hour ?? _selectedDate.hour,
              time?.minute ?? _selectedDate.minute,
            );
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(15)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18),
            const SizedBox(width: 12),
            Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(_selectedDate),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a category'),
          backgroundColor: AppTheme.warningYellow,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    // ── Focus Mode check ──────────────────────────────────────────────────
    // Capture all context-dependent references BEFORE any await.
    final txnProvider = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final catProvider = context.read<CategoryProvider>();

    // Only check on new expense transactions, not edits (editing implies intent).
    if (!_isEditing && _type == TransactionType.expense) {
      final pause = await SpendPauseService.getState();
      if (pause.isActive && pause.blockedCategories.isNotEmpty) {
        final catName =
            catProvider.categories
                .where((c) => c.id == _selectedCategoryId)
                .map((c) => c.name)
                .firstOrNull ??
            '';
        // Case-insensitive partial match: blocked list entry inside category name, or vice-versa.
        final isBlocked = pause.blockedCategories.any(
          (blocked) =>
              catName.toLowerCase().contains(blocked.toLowerCase()) ||
              blocked.toLowerCase().contains(catName.toLowerCase()),
        );
        if (isBlocked && mounted) {
          final proceed = await _showFocusModeWarning(catName);
          if (!proceed) return; // user chose to stay in focus mode
        }
      }
    }
    // ─────────────────────────────────────────────────────────────────────

    final amount = double.parse(_amountController.text);

    try {
      if (_isEditing) {
        await txnProvider.updateTransaction(
          widget.transaction!.copyWith(
            amount: amount,
            type: _type,
            categoryId: _selectedCategoryId,
            date: _selectedDate,
            note: _noteController.text,
            paymentMethod: _paymentMethod,
            isRecurring: _isRecurring,
            recurringFrequency: _isRecurring ? _recurringFrequency : null,
            taxCategory: _taxCategory,
          ),
        );
      } else {
        await txnProvider.addTransaction(
          amount: amount,
          type: _type,
          categoryId: _selectedCategoryId!,
          date: _selectedDate,
          note: _noteController.text,
          paymentMethod: _paymentMethod,
          isRecurring: _isRecurring,
          recurringFrequency: _isRecurring ? _recurringFrequency : null,
          taxCategory: _taxCategory,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Transaction updated!' : 'Transaction added!',
          ),
          backgroundColor: AppTheme.incomeGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to save transaction: $e'),
          backgroundColor: AppTheme.expenseRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Shows a bottom sheet warning that Focus Mode is active for this category.
  /// Returns true if the user wants to log the transaction anyway.
  Future<bool> _showFocusModeWarning(String categoryName) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFf59e0b).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('🧘', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Focus Mode is Active',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'You paused spending on $categoryName.',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Are you sure you want to log this expense?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            // Log anyway
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.expenseRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Log Anyway'),
              ),
            ),
            const SizedBox(height: 10),
            // Stay in focus mode
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentPurple,
                  side: const BorderSide(color: AppTheme.accentPurple),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Stay in Focus Mode'),
              ),
            ),
          ],
        ),
      ),
    );
    return result ?? false; // sheet dismissed = cancel
  }

  void _deleteTransaction() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text(
          'Are you sure you want to delete this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<TransactionProvider>().deleteTransaction(
                widget.transaction!.id,
              );
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Transaction deleted'),
                  backgroundColor: AppTheme.expenseRed,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.expenseRed),
            ),
          ),
        ],
      ),
    );
  }
}
