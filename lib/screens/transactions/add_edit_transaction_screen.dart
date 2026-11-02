import 'package:flutter/material.dart';
import 'package:pet/core/utils/amount_input.dart';
import 'package:provider/provider.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/recurring_transaction_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/motion.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/category_avatar.dart';
import 'package:pet/core/widgets/pet_section.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/widgets/gradient_background.dart';
import 'package:pet/core/widgets/category_chip.dart';
import 'package:intl/intl.dart';
import 'package:pet/premium/services/tax_category_service.dart';
import 'package:pet/premium/providers/spend_pause_provider.dart';
import 'package:pet/core/constants/categories.dart'
    show kFromPeopleCategoryId, kTransferCategoryId;
import 'package:pet/services/financial_ingestion_service.dart';

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
  bool _updateFutureRecurrences = false;
  String? _taxCategory;

  /// The income category to go back to when "Count as income" is turned
  /// back on after being turned off.
  String? _incomeCategoryBeforeFromPeople;

  bool get _isEditing => widget.transaction != null;
  bool get _isFromPeople => _selectedCategoryId == kFromPeopleCategoryId;

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
      _amountController.text = AmountInput.format(txn.amount);
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
      _amountController.text = AmountInput.format(widget.prefillAmount!);
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
    final categories = switch (_type) {
      TransactionType.expense => catProvider.expenseCategories,
      TransactionType.income => catProvider.incomeCategories,
      TransactionType.transfer => catProvider.transferCategories,
    };

    final muted = isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
    final accent = _colorFor(_type);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, Spacing.xl, 0, Spacing.sm),
          child: Text(
            text.toUpperCase(),
            style: AppTypography.overline(
              color:
                  isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit transaction' : 'New transaction'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete',
              onPressed: _deleteTransaction,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.expenseRed,
              ),
            ),
        ],
      ),
      // The save button stays in reach above the gesture bar, however long
      // the form gets.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.base,
            Spacing.sm,
            Spacing.base,
            Spacing.sm,
          ),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _saveTransaction,
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: Text(_isEditing ? 'Save changes' : 'Save transaction'),
            ),
          ),
        ),
      ),
      body: GradientBackground(
        animate: false,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.base,
              Spacing.sm,
              Spacing.base,
              Spacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTypeToggle(isDark),
                const SizedBox(height: Spacing.xl),

                // The amount is the point of this screen: large, centred,
                // in the colour of the kind of money it is.
                // The rupee sign sits right against the digits and the pair
                // stays centred as the number grows.
                Semantics(
                  label: 'Amount in rupees',
                  textField: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₹',
                        style: AppTypography.amount(
                          size: 30,
                          weight: FontWeight.w500,
                          color: accent.withAlpha(190),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: IntrinsicWidth(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 48),
                            child: TextFormField(
                              controller: _amountController,
                              autofocus: !_isEditing,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: AmountInput.formatters,
                              style:
                                  AppTypography.amount(size: 44, color: accent),
                              decoration: InputDecoration(
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                hintText: '0',
                                hintStyle: AppTypography.amount(
                                  size: 44,
                                  color: muted.withAlpha(110),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Enter an amount';
                                }
                                return AmountInput.validate(value);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),

                label('Category'),
                _buildCategoryGrid(categories, isDark),
                if (_type == TransactionType.income) ...[
                  const SizedBox(height: Spacing.sm),
                  _buildCountAsIncomeSwitch(),
                ],

                label('Paid with'),
                _buildPaymentMethodSelector(isDark),

                label('Details'),
                PetSection(
                  children: [
                    _buildDatePicker(context, isDark),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                      child: TextFormField(
                        controller: _noteController,
                        decoration: InputDecoration(
                          hintText: 'Add a note',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.notes_rounded,
                            size: 20,
                            color: muted,
                          ),
                        ),
                        maxLines: 2,
                        minLines: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                      child: DropdownButtonFormField<String>(
                        initialValue: TaxCategoryService.defaults.any(
                          (e) => e.id == _taxCategory,
                        )
                            ? _taxCategory
                            : null,
                        decoration: InputDecoration(
                          hintText: 'Tax category (optional)',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.receipt_long_outlined,
                            size: 20,
                            color: muted,
                          ),
                        ),
                        items: TaxCategoryService.defaults
                            .map(
                              (t) => DropdownMenuItem<String>(
                                value: t.id,
                                child: Text(t.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _taxCategory = value),
                      ),
                    ),
                  ],
                ),

                label('Repeat'),
                PetSection(
                  children: [
                    PetRow(
                      title: 'Recurring',
                      subtitle: _isRecurring
                          ? 'Added again ${_recurringFrequency.displayName.toLowerCase()}'
                          : 'Add this again automatically',
                      leading: const CategoryAvatar(
                        icon: Icons.event_repeat_rounded,
                        color: AppTheme.accentTeal,
                        size: 36,
                      ),
                      trailing: Switch(
                        value: _isRecurring,
                        onChanged: (value) =>
                            setState(() => _isRecurring = value),
                      ),
                    ),
                    if (_isRecurring)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: RecurringFrequency.values.map((freq) {
                            return ChoiceChip(
                              label: Text(freq.displayName),
                              selected: _recurringFrequency == freq,
                              onSelected: (_) =>
                                  setState(() => _recurringFrequency = freq),
                            );
                          }).toList(),
                        ),
                      ),
                    if (_isEditing &&
                        widget.transaction?.recurringRuleId != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Apply changes to',
                              style: AppTypography.bodySmall(color: muted),
                            ),
                            const SizedBox(height: Spacing.sm),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('This one only'),
                                  selected: !_updateFutureRecurrences,
                                  onSelected: (_) => setState(
                                    () => _updateFutureRecurrences = false,
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('All future ones'),
                                  selected: _updateFutureRecurrences,
                                  onSelected: (_) => setState(
                                    () => _updateFutureRecurrences = true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(Spacing.radiusMd),
      ),
      child: Row(
        children: [
          _buildTypeSegment(TransactionType.expense, isDark),
          _buildTypeSegment(TransactionType.income, isDark),
          _buildTypeSegment(TransactionType.transfer, isDark),
        ],
      ),
    );
  }

  /// Color for [type]: red spending, green income, neutral blue transfer.
  static Color _colorFor(TransactionType type) => switch (type) {
        TransactionType.expense => AppTheme.expenseRed,
        TransactionType.income => AppTheme.incomeGreen,
        TransactionType.transfer => ColorTokens.transfer,
      };

  Widget _buildTypeSegment(TransactionType type, bool isDark) {
    final selected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          // A transfer has one category; the others must be picked again.
          _selectedCategoryId =
              type == TransactionType.transfer ? kTransferCategoryId : null;
        }),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.quick),
          curve: Motion.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _colorFor(type) : Colors.transparent,
            borderRadius: BorderRadius.circular(Spacing.radiusMd - 4),
          ),
          child: Center(
            child: Text(
              type.displayName,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : (isDark
                        ? AppTheme.textSecondary
                        : AppTheme.textSecondaryLight),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One tap to move money between "income" and "From people" (money from
  /// friends or family, tracked but kept out of income totals).
  Widget _buildCountAsIncomeSwitch() {
    final merchant = widget.transaction?.merchantName;
    final hasPayee =
        merchant != null && merchant.isNotEmpty && merchant != 'Unknown';
    return SwitchListTile(
      key: const Key('count_as_income_switch'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Count as income'),
      subtitle: Text(
        _isFromPeople
            ? 'Shown as "From people" and left out of your income'
                '${hasPayee ? '. Future money from $merchant will be too.' : '.'}'
            : 'Turn off for money from friends or family',
      ),
      value: !_isFromPeople,
      onChanged: (countAsIncome) => setState(() {
        if (countAsIncome) {
          _selectedCategoryId =
              _incomeCategoryBeforeFromPeople ?? 'cat_other_income';
        } else {
          _incomeCategoryBeforeFromPeople = _selectedCategoryId;
          _selectedCategoryId = kFromPeopleCategoryId;
        }
      }),
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
            duration: Motion.of(context, Motion.quick),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accentPurple.withAlpha(isDark ? 45 : 25)
                  : (isDark ? AppTheme.cardDark : Colors.white),
              borderRadius: BorderRadius.circular(Spacing.radiusSm + 2),
              border: Border.all(
                color: isSelected
                    ? AppTheme.accentPurple.withAlpha(160)
                    : (isDark
                        ? Colors.white.withAlpha(15)
                        : const Color(0xFFE2E8F0)),
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
    return PetRow(
      title: DateFormat('EEE, d MMM yyyy').format(_selectedDate),
      subtitle: DateFormat('h:mm a').format(_selectedDate),
      leading: Icon(
        Icons.event_rounded,
        size: 20,
        color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
      ),
      showChevron: true,
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
    final recurringProvider = context.read<RecurringTransactionProvider>();
    final spendPauseProvider = context.read<SpendPauseProvider>();

    // Only check on new expense transactions, not edits (editing implies intent).
    if (!_isEditing && _type == TransactionType.expense) {
      if (spendPauseProvider.isActive &&
          _selectedCategoryId != null &&
          spendPauseProvider.isCategoryBlocked(_selectedCategoryId!)) {
        final catName = catProvider.categories
                .where((c) => c.id == _selectedCategoryId)
                .map((c) => c.name)
                .firstOrNull ??
            '';
        if (mounted) {
          final proceed = await _showFocusModeWarning(catName);
          if (!proceed) return; // user chose to stay in focus mode
          await spendPauseProvider.recordOverride(
            categoryId: _selectedCategoryId!,
            amount: AmountInput.parse(_amountController.text) ?? 0.0,
            categoryName: catName,
          );
        }
      }
    }
    // ─────────────────────────────────────────────────────────────────────

    final amount = AmountInput.parse(_amountController.text)!;

    try {
      if (_isEditing) {
        final existingTxn = widget.transaction!;
        if (_isRecurring && existingTxn.recurringRuleId != null) {
          await txnProvider.updateTransaction(
            existingTxn.copyWith(
              amount: amount,
              type: _type,
              categoryId: _selectedCategoryId,
              date: _selectedDate,
              note: _noteController.text,
              paymentMethod: _paymentMethod,
              isRecurring: _isRecurring,
              recurringFrequency: _recurringFrequency,
              taxCategory: _taxCategory,
            ),
          );
          if (_updateFutureRecurrences) {
            final rule = recurringProvider.allRules
                .where((r) => r.id == existingTxn.recurringRuleId)
                .firstOrNull;
            if (rule != null) {
              await recurringProvider.updateRule(
                rule.copyWith(
                  amount: amount,
                  type: _type,
                  categoryId: _selectedCategoryId,
                  frequency: _recurringFrequency,
                  note: _noteController.text,
                  paymentMethod: _paymentMethod,
                  taxCategory: _taxCategory,
                ),
              );
            }
          }
        } else if (_isRecurring && existingTxn.recurringRuleId == null) {
          final result = await recurringProvider.createRule(
            amount: amount,
            type: _type,
            categoryId: _selectedCategoryId!,
            frequency: _recurringFrequency,
            startDate: _selectedDate,
            note: _noteController.text,
            paymentMethod: _paymentMethod,
            taxCategory: _taxCategory,
            generateFirstOccurrenceImmediately: false,
          );
          await txnProvider.updateTransaction(
            existingTxn.copyWith(
              amount: amount,
              type: _type,
              categoryId: _selectedCategoryId,
              date: _selectedDate,
              note: _noteController.text,
              paymentMethod: _paymentMethod,
              isRecurring: true,
              recurringFrequency: _recurringFrequency,
              taxCategory: _taxCategory,
              recurringRuleId: result.rule.id,
              occurrenceDate: _selectedDate,
            ),
          );
        } else if (!_isRecurring && existingTxn.recurringRuleId != null) {
          await recurringProvider.stopRule(existingTxn.recurringRuleId!);
          await txnProvider.updateTransaction(
            existingTxn.copyWith(
              amount: amount,
              type: _type,
              categoryId: _selectedCategoryId,
              date: _selectedDate,
              note: _noteController.text,
              paymentMethod: _paymentMethod,
              isRecurring: false,
              recurringFrequency: null,
              taxCategory: _taxCategory,
            ),
          );
        } else {
          await txnProvider.updateTransaction(
            existingTxn.copyWith(
              amount: amount,
              type: _type,
              categoryId: _selectedCategoryId,
              date: _selectedDate,
              note: _noteController.text,
              paymentMethod: _paymentMethod,
              isRecurring: false,
              recurringFrequency: null,
              taxCategory: _taxCategory,
            ),
          );
        }
        // "Count as income" changed: remember it for this payee.
        if (_type == TransactionType.income &&
            existingTxn.isFromPeople != _isFromPeople) {
          try {
            await FinancialIngestionService().rememberIncomeChoice(
              existingTxn.copyWith(
                  type: _type, categoryId: _selectedCategoryId),
            );
          } catch (_) {
            // The edit itself is saved; only the payee rule failed.
          }
        }
      } else {
        if (_isRecurring) {
          await recurringProvider.createRule(
            amount: amount,
            type: _type,
            categoryId: _selectedCategoryId!,
            frequency: _recurringFrequency,
            startDate: _selectedDate,
            note: _noteController.text,
            paymentMethod: _paymentMethod,
            taxCategory: _taxCategory,
            generateFirstOccurrenceImmediately: true,
          );
          await txnProvider.loadTransactions();
        } else {
          await txnProvider.addTransaction(
            amount: amount,
            type: _type,
            categoryId: _selectedCategoryId!,
            date: _selectedDate,
            note: _noteController.text,
            paymentMethod: _paymentMethod,
            isRecurring: false,
            recurringFrequency: null,
            taxCategory: _taxCategory,
          );
        }
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
      useSafeArea: true,
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
