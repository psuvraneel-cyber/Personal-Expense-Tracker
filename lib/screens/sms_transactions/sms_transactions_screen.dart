import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/screens/sms_transactions/pending_review_screen.dart';
import 'package:pet/screens/sms_transactions/sms_permission_screen.dart';
import 'package:pet/services/sms_parser/intent_detector.dart';
import 'package:pet/services/sms_parser/negative_filter.dart';

/// Google Pay-style screen displaying UPI transaction history —
/// both payments sent and payments received.
class SmsTransactionsScreen extends StatefulWidget {
  const SmsTransactionsScreen({super.key});

  @override
  State<SmsTransactionsScreen> createState() => _SmsTransactionsScreenState();
}

class _SmsTransactionsScreenState extends State<SmsTransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _newestFirst = true;
  String _filterType = 'all';
  final _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<SmsTransactionProvider>(
        context,
        listen: false,
      );
      // Only trigger a load if initialize() has not already done so
      // (i.e., not currently loading AND list is empty).
      if (!provider.isLoading && provider.transactions.isEmpty) {
        provider.loadTransactions();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        title: const Text('Transaction History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Pending Review badge
          Consumer<SmsTransactionProvider>(
            builder: (_, provider, _) {
              final count = provider.uncertainTransactions.length;
              return IconButton(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count', style: const TextStyle(fontSize: 10)),
                  backgroundColor: Colors.amber,
                  child: const Icon(Icons.rate_review_outlined),
                ),
                tooltip: 'Pending Review',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PendingReviewScreen(),
                    ),
                  );
                },
              );
            },
          ),
          Consumer<SmsTransactionProvider>(
            builder: (_, provider, _) {
              return IconButton(
                icon: provider.isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                tooltip: 'Re-scan SMS',
                onPressed: provider.isScanning
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final count = await provider.scanInbox(
                          lookbackDays: 90,
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              count > 0
                                  ? 'Found $count new transactions!'
                                  : 'No new transactions found.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            backgroundColor: count > 0
                                ? AppTheme.incomeGreen
                                : AppTheme.textTertiary,
                          ),
                        );
                      },
              );
            },
          ),
        ],
      ),
      body: Consumer<SmsTransactionProvider>(
        builder: (context, provider, _) {
          // Feature not enabled — prompt to set it up
          if (!provider.smsFeatureEnabled) {
            return _buildSetupPrompt(isDark);
          }

          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.isScanning && provider.transactions.isEmpty) {
            return _buildScanningState(isDark);
          }

          if (provider.transactions.isEmpty) {
            return _buildEmptyState(isDark);
          }

          return _buildGPayLayout(provider, isDark);
        },
      ),
    );
  }

  /// Shown when SMS feature is not yet enabled.
  Widget _buildSetupPrompt(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentPurple.withAlpha(60),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.sms_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'UPI Auto-Tracking Not Set Up',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.textPrimary
                    : AppTheme.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Enable automatic UPI transaction detection '
              'by granting SMS read access. '
              'Your data stays on-device.',
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
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SmsPermissionScreen(),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.sms_rounded, size: 20),
                label: const Text(
                  'Set Up UPI Tracking',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.accentPurple),
          const SizedBox(height: 24),
          Text(
            'Scanning your SMS...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Looking for bank transaction messages',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppTheme.textSecondary
                  : AppTheme.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sms_failed_outlined,
              size: 64,
              color: isDark
                  ? AppTheme.textTertiary
                  : AppTheme.textSecondaryLight,
            ),
            const SizedBox(height: 20),
            Text(
              'No Transactions Found',
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
              'No bank transaction SMS found in your inbox. '
              'Try scanning with a longer lookback period or '
              'check if SMS permissions are granted.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final provider = Provider.of<SmsTransactionProvider>(
                  context,
                  listen: false,
                );
                final count = await provider.scanInbox(lookbackDays: 180);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      count > 0
                          ? 'Found $count transactions!'
                          : 'No transactions found. Check SMS permissions.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: count > 0
                        ? AppTheme.incomeGreen
                        : AppTheme.expenseRed,
                  ),
                );
              },
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Scan Last 6 Months'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                final provider = Provider.of<SmsTransactionProvider>(
                  context,
                  listen: false,
                );
                // Reset reconciliation watermark to force full rescan
                await provider.resetReconciliationWatermark();
                final count = await provider.scanInbox(lookbackDays: 365);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      count > 0
                          ? 'Found $count transactions!'
                          : 'No transactions found after full scan.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: count > 0
                        ? AppTheme.incomeGreen
                        : AppTheme.expenseRed,
                  ),
                );
              },
              icon: Icon(
                Icons.refresh_rounded,
                size: 18,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
              ),
              label: Text(
                'Force Full Rescan (1 Year)',
                style: TextStyle(
                  color: isDark
                      ? AppTheme.textSecondary
                      : AppTheme.textSecondaryLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGPayLayout(SmsTransactionProvider provider, bool isDark) {
    return _buildTransactionsList(provider, isDark);
  }

  Widget _buildTransactionsList(SmsTransactionProvider provider, bool isDark) {
    // Filter transactions
    List<SmsTransaction> filtered;
    switch (_filterType) {
      case 'debit':
        filtered = List.of(provider.debitTransactions);
        break;
      case 'credit':
        filtered = List.of(provider.creditTransactions);
        break;
      default:
        filtered = List.of(provider.transactions);
    }

    // Sort by timestamp
    filtered.sort(
      (a, b) => _newestFirst
          ? b.timestamp.compareTo(a.timestamp)
          : a.timestamp.compareTo(b.timestamp),
    );

    // Group transactions by date
    final grouped = _groupByDate(filtered);

    return Column(
      children: [
        // Summary bar
        _buildSummaryBar(provider, isDark),

        // Last synced indicator
        _buildLastSyncedIndicator(provider, isDark),

        // Filter chips
        _buildFilterChips(isDark),

        // Transaction count & sort toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Text(
                '${filtered.length} transactions',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppTheme.textSecondary
                      : AppTheme.textSecondaryLight,
                ),
              ),
              const Spacer(),
              if (provider.isScanning)
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Scanning...',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              // Sort order toggle
              GestureDetector(
                onTap: () => setState(() => _newestFirst = !_newestFirst),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withAlpha(8)
                        : Colors.black.withAlpha(6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withAlpha(12)
                          : Colors.black.withAlpha(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _newestFirst
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        size: 14,
                        color: AppTheme.accentPurple,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _newestFirst ? 'Newest' : 'Oldest',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppTheme.textSecondary
                              : AppTheme.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Date-grouped transaction list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final entry = grouped.entries.elementAt(index);
              return _buildDateSection(entry.key, entry.value, isDark);
            },
          ),
        ),
      ],
    );
  }

  /// Group transactions by date label (Today, Yesterday, or formatted date).
  Map<String, List<SmsTransaction>> _groupByDate(List<SmsTransaction> txns) {
    final Map<String, List<SmsTransaction>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final txn in txns) {
      final txnDate = DateTime(
        txn.timestamp.year,
        txn.timestamp.month,
        txn.timestamp.day,
      );

      String label;
      if (txnDate == today) {
        label = 'Today';
      } else if (txnDate == yesterday) {
        label = 'Yesterday';
      } else if (txnDate.isAfter(today.subtract(const Duration(days: 7)))) {
        label = DateFormat('EEEE').format(txnDate); // e.g. "Monday"
      } else if (txnDate.year == now.year) {
        label = DateFormat('d MMMM').format(txnDate); // e.g. "5 February"
      } else {
        label = DateFormat('d MMMM yyyy').format(txnDate); // e.g. "25 Dec 2025"
      }

      grouped.putIfAbsent(label, () => []).add(txn);
    }
    return grouped;
  }

  /// Build a date section with header and its transactions.
  Widget _buildDateSection(
    String dateLabel,
    List<SmsTransaction> transactions,
    bool isDark,
  ) {
    // Calculate daily total for this group
    final dailyDebit = transactions
        .where((t) => t.transactionType == 'debit')
        .fold(0.0, (sum, t) => sum + t.amount);
    final dailyCredit = transactions
        .where((t) => t.transactionType == 'credit')
        .fold(0.0, (sum, t) => sum + t.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple.withAlpha(isDark ? 22 : 16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentPurple,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mini summary for this day
              if (dailyDebit > 0)
                Text(
                  '-${_currencyFormat.format(dailyDebit)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.expenseRed,
                  ),
                ),
              if (dailyDebit > 0 && dailyCredit > 0)
                Text(
                  '  ',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? AppTheme.textTertiary
                        : AppTheme.textSecondaryLight,
                  ),
                ),
              if (dailyCredit > 0)
                Text(
                  '+${_currencyFormat.format(dailyCredit)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.incomeGreen,
                  ),
                ),
              const Spacer(),
              Text(
                '${transactions.length} txn${transactions.length > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppTheme.textTertiary
                      : AppTheme.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
        // Timeline-style transactions
        ...transactions.asMap().entries.map((entry) {
          final index = entry.key;
          final txn = entry.value;
          final isLast = index == transactions.length - 1;
          return _buildTimelineTile(txn, isDark, isLast);
        }),
        if (transactions.isNotEmpty) const SizedBox(height: 4),
      ],
    );
  }

  /// Build a single transaction tile with a timeline connector.
  Widget _buildTimelineTile(SmsTransaction txn, bool isDark, bool isLast) {
    final isDebit = txn.transactionType == 'debit';
    final amountColor = isDebit ? AppTheme.expenseRed : AppTheme.incomeGreen;
    final amountPrefix = isDebit ? '- ' : '+ ';
    final timeStr = txn.timestampIsApproximate
        ? '--:--'
        : DateFormat('hh:mm a').format(txn.timestamp);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: amountColor.withAlpha(isDark ? 50 : 40),
                    shape: BoxShape.circle,
                    border: Border.all(color: amountColor, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isDark
                          ? Colors.white.withAlpha(10)
                          : Colors.black.withAlpha(8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Transaction content
          Expanded(
            child: _buildTransactionTileContent(
              txn,
              isDark,
              amountColor,
              amountPrefix,
              timeStr,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(SmsTransactionProvider provider, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentPurple.withAlpha(40),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryColumn(
              label: 'Total Debits',
              amount: _currencyFormat.format(provider.totalDebits),
              icon: Icons.arrow_upward_rounded,
              color: AppTheme.expenseRed,
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white.withAlpha(30)),
          Expanded(
            child: _SummaryColumn(
              label: 'Total Credits',
              amount: _currencyFormat.format(provider.totalCredits),
              icon: Icons.arrow_downward_rounded,
              color: AppTheme.incomeGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastSyncedIndicator(SmsTransactionProvider provider, bool isDark) {
    final timestamp = provider.lastSyncTimestamp;
    String label;
    if (timestamp == null) {
      label = 'Last synced: Never';
    } else {
      final diff = DateTime.now().difference(timestamp);
      if (diff.inSeconds < 60) {
        label = 'Last synced just now';
      } else if (diff.inMinutes < 60) {
        label = 'Last synced ${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        label = 'Last synced ${diff.inHours}h ago';
      } else {
        label = 'Last synced ${diff.inDays}d ago';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 13,
            color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            isSelected: _filterType == 'all',
            onTap: () => setState(() => _filterType = 'all'),
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Debits',
            isSelected: _filterType == 'debit',
            onTap: () => setState(() => _filterType = 'debit'),
            isDark: isDark,
            color: AppTheme.expenseRed,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Credits',
            isSelected: _filterType == 'credit',
            onTap: () => setState(() => _filterType = 'credit'),
            isDark: isDark,
            color: AppTheme.incomeGreen,
          ),
        ],
      ),
    );
  }

  /// Build the content of a transaction tile (used inside the timeline).
  Widget _buildTransactionTileContent(
    SmsTransaction txn,
    bool isDark,
    Color amountColor,
    String amountPrefix,
    String timeStr,
  ) {
    return Dismissible(
      key: Key(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.expenseRed.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: AppTheme.expenseRed),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Transaction'),
            content: const Text(
              'Remove this auto-detected transaction? '
              'It won\'t be detected again from the same SMS.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.expenseRed,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        Provider.of<SmsTransactionProvider>(
          context,
          listen: false,
        ).deleteTransaction(txn.id);
      },
      child: GestureDetector(
        onTap: () => _showTransactionDetail(txn, isDark),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(6)
                  : Colors.black.withAlpha(6),
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: amountColor.withAlpha(isDark ? 25 : 18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  txn.transactionType == 'debit'
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: amountColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // Details
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
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          txn.bankName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppTheme.textTertiary
                                : AppTheme.textSecondaryLight,
                          ),
                        ),
                        Text(
                          '  •  ',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? AppTheme.textTertiary
                                : AppTheme.textSecondaryLight,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            txn.category,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.accentPurple.withAlpha(180),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (txn.source != 'sms') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentPurple.withAlpha(
                                isDark ? 20 : 14,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              txn.source == 'notification'
                                  ? '🔔 notif'
                                  : txn.source,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentPurple,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Amount & time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$amountPrefix${_currencyFormat.format(txn.amount)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? AppTheme.textTertiary
                          : AppTheme.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDetail(SmsTransaction txn, bool isDark) {
    final dateStr = txn.timestampIsApproximate
        ? DateFormat('dd MMM yyyy').format(txn.timestamp)
        : DateFormat('dd MMM yyyy, hh:mm a').format(txn.timestamp);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
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
                      // Header
                      Row(
                        children: [
                          Text(
                            'Transaction Details',
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
                              color: txn.transactionType == 'debit'
                                  ? AppTheme.expenseRed.withAlpha(25)
                                  : AppTheme.incomeGreen.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              txn.transactionType.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: txn.transactionType == 'debit'
                                    ? AppTheme.expenseRed
                                    : AppTheme.incomeGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _DetailRow(
                        label: 'Amount',
                        value: _currencyFormat.format(txn.amount),
                        isDark: isDark,
                      ),
                      _DetailRow(
                        label: 'Merchant',
                        value: txn.merchantName,
                        isDark: isDark,
                      ),
                      _DetailRow(
                        label: 'Bank',
                        value: txn.bankName,
                        isDark: isDark,
                      ),
                      _DetailRow(label: 'Date', value: dateStr, isDark: isDark),
                      _DetailRow(
                        label: 'Category',
                        value: txn.category,
                        isDark: isDark,
                      ),
                      _DetailRow(
                        label: 'Sender',
                        value: txn.smsSender,
                        isDark: isDark,
                      ),

                      const SizedBox(height: 16),
                      Text(
                        'Original SMS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.textSecondary
                              : AppTheme.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withAlpha(6)
                              : Colors.black.withAlpha(6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withAlpha(8)
                                : Colors.black.withAlpha(8),
                          ),
                        ),
                        child: Text(
                          txn.rawSmsBody,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.textSecondary
                                : AppTheme.textSecondaryLight,
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Expandable classification reasons
                      _ClassificationReasonsSection(
                        body: txn.rawSmsBody,
                        sender: txn.smsSender,
                        isDark: isDark,
                      ),

                      const SizedBox(height: 20),

                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showCategoryPicker(txn);
                              },
                              icon: const Icon(Icons.edit_rounded, size: 16),
                              label: const Text('Re-categorize'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.accentPurple,
                                side: BorderSide(
                                  color: AppTheme.accentPurple.withAlpha(60),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Provider.of<SmsTransactionProvider>(
                                  context,
                                  listen: false,
                                ).deleteTransaction(txn.id);
                              },
                              icon: const Icon(Icons.delete_rounded, size: 16),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.expenseRed,
                                side: BorderSide(
                                  color: AppTheme.expenseRed.withAlpha(60),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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

  void _showCategoryPicker(SmsTransaction txn) {
    final categories = [
      'Food & Dining',
      'Transport',
      'Shopping',
      'Bills & Utilities',
      'Recharge & DTH',
      'Health',
      'Entertainment',
      'Groceries',
      'Education',
      'EMI & Loans',
      'Rent',
      'Salary',
      'Freelance',
      'Investment Returns',
      'Refund',
      'Other Expense',
      'Other Income',
      'Uncategorized',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.surfaceDark
          : AppTheme.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Category',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: categories.length,
                itemBuilder: (_, index) {
                  final cat = categories[index];
                  final isSelected = cat == txn.category;
                  return ListTile(
                    title: Text(
                      cat,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isSelected ? AppTheme.accentPurple : null,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppTheme.accentPurple,
                          )
                        : null,
                    onTap: () {
                      Provider.of<SmsTransactionProvider>(
                        context,
                        listen: false,
                      ).updateCategory(txn.id, cat);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  const _SummaryColumn({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white.withAlpha(180)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withAlpha(180),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          amount,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppTheme.textTertiary
                    : AppTheme.textSecondaryLight,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.textPrimary
                    : AppTheme.textPrimaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? AppTheme.accentPurple)
              : (isDark
                    ? Colors.white.withAlpha(8)
                    : Colors.black.withAlpha(8)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (color ?? AppTheme.accentPurple)
                : (isDark
                      ? Colors.white.withAlpha(12)
                      : Colors.black.withAlpha(12)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight),
          ),
        ),
      ),
    );
  }
}

/// Expandable section showing classification reasons for a transaction.
/// Re-runs intent detection on the stored SMS body to get the reason list.
class _ClassificationReasonsSection extends StatefulWidget {
  final String body;
  final String sender;
  final bool isDark;

  const _ClassificationReasonsSection({
    required this.body,
    required this.sender,
    required this.isDark,
  });

  @override
  State<_ClassificationReasonsSection> createState() =>
      _ClassificationReasonsSectionState();
}

class _ClassificationReasonsSectionState
    extends State<_ClassificationReasonsSection> {
  bool _expanded = false;

  List<String> _computeReasons() {
    final reasons = <String>[];

    // Run negative filter
    final filterResult = NegativeFilter.apply(widget.body, widget.sender);
    if (filterResult.rejected) {
      reasons.add('Negative filter: ${filterResult.reason}');
      return reasons;
    }
    reasons.add('Sender trust: ${filterResult.senderTrust.name}');

    // Run intent detection
    final intent = IntentDetector.detect(widget.body);
    reasons.addAll(intent.reasons);

    return reasons;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
                color: widget.isDark
                    ? AppTheme.textTertiary
                    : AppTheme.textSecondaryLight,
              ),
              const SizedBox(width: 4),
              Text(
                'Classification Reasons',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.isDark
                      ? AppTheme.textSecondary
                      : AppTheme.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withAlpha(6)
                  : Colors.black.withAlpha(6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isDark
                    ? Colors.white.withAlpha(8)
                    : Colors.black.withAlpha(8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _computeReasons()
                  .map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.isDark
                                  ? AppTheme.textTertiary
                                  : AppTheme.textSecondaryLight,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              r,
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.isDark
                                    ? AppTheme.textSecondary
                                    : AppTheme.textSecondaryLight,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}
