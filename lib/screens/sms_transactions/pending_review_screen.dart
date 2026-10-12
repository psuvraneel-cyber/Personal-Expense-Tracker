import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/screens/sms_transactions/sms_detail_widgets.dart';

import 'package:pet/providers/category_provider.dart';

/// Screen showing uncertain/low-confidence transactions for user review.
/// Users can accept (as debit or credit), edit, or reject each transaction.
class PendingReviewScreen extends StatefulWidget {
  final String? initialObservationId;

  const PendingReviewScreen({super.key, this.initialObservationId});

  @override
  State<PendingReviewScreen> createState() => _PendingReviewScreenState();
}

class _PendingReviewScreenState extends State<PendingReviewScreen> {
  bool _checkedInitial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Opened from a "possible transaction" notification: make sure the
      // newest queued items are loaded before looking up the target.
      await context.read<SmsTransactionProvider>().loadTransactions();
      if (mounted) _checkInitialObservation();
    });
  }

  void _checkInitialObservation() {
    if (_checkedInitial || widget.initialObservationId == null || !mounted) {
      return;
    }
    final provider = context.read<SmsTransactionProvider>();
    if (provider.isLoading) return;

    _checkedInitial = true;
    final target =
        provider.uncertainTransactions.cast<SmsTransaction?>().firstWhere(
              (t) => t?.id == widget.initialObservationId,
              orElse: () => null,
            );

    if (target != null) {
      _showEditDialog(context, target, provider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'This transaction has already been reviewed.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    );

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        title: const Text('Pending Review'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<SmsTransactionProvider>(
        builder: (context, provider, _) {
          if (!provider.isLoading &&
              !_checkedInitial &&
              widget.initialObservationId != null) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _checkInitialObservation());
          }

          final uncertain = provider.uncertainTransactions;

          if (uncertain.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 64,
                      color: AppTheme.incomeGreen.withAlpha(150),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'All Clear!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.textPrimary
                            : AppTheme.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No uncertain transactions to review.\n'
                      'Transactions with low confidence will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppTheme.textSecondary
                            : AppTheme.textSecondaryLight,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(isDark ? 25 : 18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.amber.withAlpha(isDark ? 40 : 30),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${uncertain.length} possible transaction${uncertain.length > 1 ? 's' : ''} '
                        'need your review. Tap one to see the original SMS, swipe right '
                        'to accept or left to reject.',
                        style: TextStyle(
                          fontSize: 12,
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

              // Transaction list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: uncertain.length,
                  itemBuilder: (context, index) {
                    final txn = uncertain[index];
                    return _UncertainTransactionCard(
                      txn: txn,
                      isDark: isDark,
                      currencyFormat: currencyFormat,
                      onEdit: () => _showEditDialog(context, txn, provider),
                      onTap: () => _showReviewDetail(
                        context,
                        txn,
                        provider,
                        currencyFormat,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _showEditDialog(
  BuildContext context,
  SmsTransaction txn,
  SmsTransactionProvider provider,
) async {
  final amountController = TextEditingController(
    text: txn.amount > 0 ? txn.amount.toStringAsFixed(2) : '',
  );
  final merchantController = TextEditingController(text: txn.merchantName);
  String selectedType = txn.transactionType == 'credit' ? 'credit' : 'debit';
  String selectedCategory = txn.category;

  final categories = context.read<CategoryProvider>().categories;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Transaction Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: merchantController,
                    decoration: const InputDecoration(
                      labelText: 'Merchant / Description',
                      prefixIcon: Icon(Icons.store_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      prefixIcon: Icon(Icons.currency_rupee_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Transaction Type',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Debit'),
                        selected: selectedType == 'debit',
                        selectedColor: AppTheme.expenseRed.withAlpha(50),
                        onSelected: (val) {
                          if (val) setDialogState(() => selectedType = 'debit');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Credit'),
                        selected: selectedType == 'credit',
                        selectedColor: AppTheme.incomeGreen.withAlpha(50),
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() => selectedType = 'credit');
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (categories.isNotEmpty) ...[
                    const Text('Category',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue:
                          categories.any((c) => c.name == selectedCategory)
                              ? selectedCategory
                              : (categories.isNotEmpty
                                  ? categories.first.name
                                  : null),
                      items: categories.map((c) {
                        return DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedCategory = val);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('Confirm & Save'),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed == true) {
    final double? parsedAmount = double.tryParse(amountController.text.trim());
    final String merchant = merchantController.text.trim().isNotEmpty
        ? merchantController.text.trim()
        : txn.merchantName;

    await provider.acceptUncertainTransaction(
      txn.id,
      overrideType: selectedType,
      overrideAmount: parsedAmount,
      overrideMerchant: merchant,
      overrideCategoryId: selectedCategory,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved and accepted as $selectedType'),
          backgroundColor: AppTheme.incomeGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Everything the parser saw, including the original SMS, so the user can
/// decide before accepting or rejecting.
Future<void> _showReviewDetail(
  BuildContext context,
  SmsTransaction txn,
  SmsTransactionProvider provider,
  NumberFormat currencyFormat,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final isDebit = txn.transactionType == 'debit';
  final dateStr = txn.timestampIsApproximate
      ? DateFormat('dd MMM yyyy').format(txn.timestamp)
      : DateFormat('dd MMM yyyy, hh:mm a').format(txn.timestamp);
  final messenger = ScaffoldMessenger.of(context);

  Future<void> accept(BuildContext sheetCtx, String type) async {
    Navigator.pop(sheetCtx);
    await provider.acceptUncertainTransaction(txn.id, overrideType: type);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Accepted as $type'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.incomeGreen,
      ),
    );
  }

  return showModalBottomSheet<void>(
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(30)
                    : Colors.black.withAlpha(30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Review Transaction',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppTheme.textPrimary
                                : AppTheme.textPrimaryLight,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(isDark ? 25 : 18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${(txn.confidence * 100).toStringAsFixed(0)}% sure',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SmsDetailRow(
                      label: 'Amount',
                      value: currencyFormat.format(txn.amount),
                      isDark: isDark,
                    ),
                    SmsDetailRow(
                      label: 'Looks like',
                      value:
                          isDebit ? 'Debit (money out)' : 'Credit (money in)',
                      isDark: isDark,
                    ),
                    SmsDetailRow(
                      label: 'Merchant',
                      value: txn.merchantName,
                      isDark: isDark,
                    ),
                    SmsDetailRow(
                      label: 'Bank',
                      value: txn.bankName,
                      isDark: isDark,
                    ),
                    SmsDetailRow(label: 'Date', value: dateStr, isDark: isDark),
                    SmsDetailRow(
                      label: 'Category',
                      value: txn.category,
                      isDark: isDark,
                    ),
                    SmsDetailRow(
                      label: 'Sender',
                      value: txn.smsSender,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    OriginalSmsBox(body: txn.rawSmsBody, isDark: isDark),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => accept(sheetCtx, 'debit'),
                            icon: const Icon(Icons.arrow_upward_rounded,
                                size: 16),
                            label: const Text('Accept as debit'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.expenseRed,
                              side: BorderSide(
                                color: AppTheme.expenseRed.withAlpha(60),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => accept(sheetCtx, 'credit'),
                            icon: const Icon(Icons.arrow_downward_rounded,
                                size: 16),
                            label: const Text('Accept as credit'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.incomeGreen,
                              side: BorderSide(
                                color: AppTheme.incomeGreen.withAlpha(60),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              _showEditDialog(context, txn, provider);
                            },
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            label: const Text('Edit details'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              await provider.rejectUncertainTransaction(txn.id);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Marked as not a transaction'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('Not a transaction'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _UncertainTransactionCard extends StatelessWidget {
  final SmsTransaction txn;
  final bool isDark;
  final NumberFormat currencyFormat;
  final VoidCallback onEdit;
  final VoidCallback onTap;

  const _UncertainTransactionCard({
    required this.txn,
    required this.isDark,
    required this.currencyFormat,
    required this.onEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDebit = txn.transactionType == 'debit';
    final amountColor = isDebit ? AppTheme.expenseRed : AppTheme.incomeGreen;
    final dateStr = txn.timestampIsApproximate
        ? DateFormat('dd MMM yyyy').format(txn.timestamp)
        : DateFormat('dd MMM, hh:mm a').format(txn.timestamp);
    final confidencePercent = (txn.confidence * 100).toStringAsFixed(0);

    return Dismissible(
      key: Key('uncertain_${txn.id}'),
      // Swipe right to accept
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.incomeGreen.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_rounded, color: AppTheme.incomeGreen),
            SizedBox(width: 6),
            Text(
              'Accept',
              style: TextStyle(
                color: AppTheme.incomeGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      // Swipe left to reject
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.expenseRed.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Reject',
              style: TextStyle(
                color: AppTheme.expenseRed,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.close_rounded, color: AppTheme.expenseRed),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        final provider = Provider.of<SmsTransactionProvider>(
          context,
          listen: false,
        );
        if (direction == DismissDirection.startToEnd) {
          // Accept — ask user to confirm type
          final type = await _showTypeConfirmDialog(context);
          if (type == null) return false;
          await provider.acceptUncertainTransaction(txn.id, overrideType: type);
          if (!context.mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Accepted as $type'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.incomeGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          return false; // Already handled
        } else {
          // Reject
          await provider.rejectUncertainTransaction(txn.id);
          if (!context.mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Marked as not a transaction'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.textTertiary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          return false; // Already handled
        }
      },
      child: Semantics(
        button: true,
        hint: 'Shows the original SMS',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: _buildCard(dateStr, amountColor, confidencePercent, context),
        ),
      ),
    );
  }

  Widget _buildCard(
    String dateStr,
    Color amountColor,
    String confidencePercent,
    BuildContext context,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withAlpha(isDark ? 30 : 20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: merchant + amount
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(isDark ? 25 : 18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.merchantName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.textPrimary
                            : AppTheme.textPrimaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${txn.bankName}  •  $dateStr',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.textTertiary
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
                    currencyFormat.format(txn.amount),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(isDark ? 20 : 14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$confidencePercent% sure',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Debit',
                  icon: Icons.arrow_upward_rounded,
                  color: AppTheme.expenseRed,
                  isDark: isDark,
                  onTap: () {
                    Provider.of<SmsTransactionProvider>(
                      context,
                      listen: false,
                    ).acceptUncertainTransaction(
                      txn.id,
                      overrideType: 'debit',
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ActionButton(
                  label: 'Credit',
                  icon: Icons.arrow_downward_rounded,
                  color: AppTheme.incomeGreen,
                  isDark: isDark,
                  onTap: () {
                    Provider.of<SmsTransactionProvider>(
                      context,
                      listen: false,
                    ).acceptUncertainTransaction(
                      txn.id,
                      overrideType: 'credit',
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ActionButton(
                  label: 'Edit',
                  icon: Icons.edit_rounded,
                  color: Colors.amber,
                  isDark: isDark,
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: 4),
              _ActionButton(
                label: 'Reject',
                icon: Icons.close_rounded,
                color: AppTheme.textTertiary,
                isDark: isDark,
                onTap: () {
                  Provider.of<SmsTransactionProvider>(
                    context,
                    listen: false,
                  ).rejectUncertainTransaction(txn.id);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<String?> _showTypeConfirmDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transaction Type'),
        content: const Text(
          'Is this a debit (money out) or credit (money in)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'debit'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.expenseRed),
            child: const Text('Debit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'credit'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.incomeGreen),
            child: const Text('Credit'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 18 : 12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(isDark ? 30 : 20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
