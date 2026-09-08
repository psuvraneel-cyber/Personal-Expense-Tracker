import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';
import 'package:pet/providers/category_provider.dart';

// ── Icon & Color Helpers ──────────────────────────────────────────────────────

IconData _billIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('netflix') ||
      n.contains('prime') ||
      n.contains('hotstar') ||
      n.contains('zee') ||
      n.contains('sony') ||
      n.contains('youtube')) {
    return Icons.movie_rounded;
  } else if (n.contains('spotify') ||
      n.contains('gaana') ||
      n.contains('music') ||
      n.contains('apple music') ||
      n.contains('jiosaavn')) {
    return Icons.music_note_rounded;
  } else if (n.contains('gym') || n.contains('fitness') || n.contains('cult')) {
    return Icons.fitness_center_rounded;
  } else if (n.contains('electricity') ||
      n.contains('bescom') ||
      n.contains('power') ||
      n.contains('tneb')) {
    return Icons.electrical_services_rounded;
  } else if (n.contains('rent') ||
      n.contains('house') ||
      n.contains('maintenance')) {
    return Icons.home_rounded;
  } else if (n.contains('insurance') ||
      n.contains('lic') ||
      n.contains('hdfc ergo') ||
      n.contains('max life')) {
    return Icons.health_and_safety_rounded;
  } else if (n.contains('internet') ||
      n.contains('broadband') ||
      n.contains('wifi') ||
      n.contains('act ') ||
      n.contains('airtel xstream') ||
      n.contains('jio fiber')) {
    return Icons.wifi_rounded;
  } else if (n.contains('mobile') ||
      n.contains('phone') ||
      n.contains('airtel') ||
      n.contains('vodafone') ||
      n.contains('vi ') ||
      n.contains('bsnl')) {
    return Icons.phone_android_rounded;
  } else if (n.contains('emi') ||
      n.contains('loan') ||
      n.contains('bank') ||
      n.contains('credit')) {
    return Icons.account_balance_rounded;
  } else if (n.contains('gas') ||
      n.contains('lpg') ||
      n.contains('indane') ||
      n.contains('hp gas')) {
    return Icons.local_fire_department_rounded;
  } else if (n.contains('water')) {
    return Icons.water_drop_rounded;
  } else if (n.contains('cloud') ||
      n.contains('drive') ||
      n.contains('icloud') ||
      n.contains('dropbox')) {
    return Icons.cloud_rounded;
  }
  return Icons.receipt_long_rounded;
}

Color _billColor(String name) {
  final n = name.toLowerCase();
  if (n.contains('netflix')) return const Color(0xFFE50914);
  if (n.contains('spotify')) return const Color(0xFF1DB954);
  if (n.contains('prime')) return const Color(0xFF00A8E1);
  if (n.contains('hotstar') || n.contains('disney')) return const Color(0xFF1C6EDC);
  if (n.contains('gym') || n.contains('fitness') || n.contains('cult')) return const Color(0xFFF59E0B);
  if (n.contains('electricity') || n.contains('power')) return const Color(0xFFF59E0B);
  if (n.contains('insurance') || n.contains('lic')) return const Color(0xFF10B981);
  if (n.contains('rent')) return const Color(0xFF8B5CF6);
  return AppTheme.accentTeal;
}

class RecurringBillsScreen extends StatefulWidget {
  const RecurringBillsScreen({super.key});

  @override
  State<RecurringBillsScreen> createState() => _RecurringBillsScreenState();
}

class _RecurringBillsScreenState extends State<RecurringBillsScreen> {
  final _currFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _shortDateFmt = DateFormat('dd MMM');

  int _selectedTab = 0; // 0 = Active Commitments, 1 = Cancelled

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final prov = context.read<RecurringProvider>();
        if (!prov.isInitialized && !prov.isLoading) {
          prov.load();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Bills & Subscriptions'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          IconButton(
            onPressed: () => _showAddOrEditBillSheet(context),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.accentTeal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PremiumGate(
        title: 'Bills & Subscriptions',
        subtitle: 'Track upcoming payments and recurring commitments.',
        child: Consumer<RecurringProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final confirmed = provider.confirmedBills;
            final detected = provider.detectedBills;
            final cancelled = provider.cancelledBills;

            if (confirmed.isEmpty && detected.isEmpty && cancelled.isEmpty) {
              return _buildEmpty(isDark);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              children: [
                const SizedBox(height: 8),
                _buildSummaryBanner(
                  context,
                  provider.totalMonthlyEquivalent,
                  provider.weekAheadTotal,
                  provider.totalAnnualCommitment,
                  isDark,
                ),
                if (detected.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildDetectedSection(context, detected, provider, isDark),
                ],
                if (confirmed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildWeekStrip(confirmed, isDark),
                ],
                const SizedBox(height: 16),
                _buildTabSelector(confirmed.length, cancelled.length, isDark),
                const SizedBox(height: 12),
                if (_selectedTab == 0) ...[
                  if (confirmed.isEmpty)
                    _buildEmptyTabMessage('No active recurring commitments.', isDark)
                  else
                    ...confirmed.map((r) => _buildBillCard(context, r, provider, isDark)),
                ] else ...[
                  if (cancelled.isEmpty)
                    _buildEmptyTabMessage('No cancelled commitments.', isDark)
                  else
                    ...cancelled.map((r) => _buildBillCard(context, r, provider, isDark)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Summary Banner ──────────────────────────────────────────────────────────

  Widget _buildSummaryBanner(
    BuildContext context,
    double monthlyTotal,
    double weekTotal,
    double annualTotal,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly Recurring',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currFmt.format(monthlyTotal),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentTeal,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.white.withAlpha(25),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Due next 7 days',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      weekTotal == 0
                          ? 'None due'
                          : _currFmt.format(weekTotal),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: weekTotal == 0
                            ? AppTheme.incomeGreen
                            : AppTheme.warningYellow,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  'Annual commitment: ${_currFmt.format(annualTotal)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Detected Section ────────────────────────────────────────────────────────

  Widget _buildDetectedSection(
    BuildContext context,
    List<RecurringPayment> detected,
    RecurringProvider provider,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warningYellow.withAlpha(isDark ? 20 : 15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.warningYellow.withAlpha(isDark ? 60 : 45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.warningYellow,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Possible Recurring Payments (${detected.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.warningYellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'P.E.T. identified repeating payments from your history. Confirm to start tracking reminders.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
          ),
          const SizedBox(height: 12),
          ...detected.map((item) => _buildDetectedCard(context, item, provider, isDark)),
        ],
      ),
    );
  }

  Widget _buildDetectedCard(
    BuildContext context,
    RecurringPayment item,
    RecurringProvider provider,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _billColor(item.merchantName).withAlpha(isDark ? 35 : 22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _billIcon(item.merchantName),
                  color: _billColor(item.merchantName),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.merchantName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '${item.frequencyEnum.displayName} • Last paid ${_shortDateFmt.format(item.lastPaidAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                _currFmt.format(item.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.expenseRed,
                ),
              ),
            ],
          ),
          if (item.isPriceChanged) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accentPurple.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Price change detected: ${_currFmt.format(item.previousAmount)} → ${_currFmt.format(item.amount)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentPurple,
                ),
              ),
            ),
          ],
          if (item.detectionReason != null) ...[
            const SizedBox(height: 4),
            Text(
              item.detectionReason!,
              style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => provider.dismissDetected(item.id),
                child: const Text('Dismiss', style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _showAddOrEditBillSheet(context, existingBill: item, isConfirmingDetection: true),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Edit', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => provider.confirmDetected(item.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentTeal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Confirm', style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Week Strip ──────────────────────────────────────────────────────────────

  Widget _buildWeekStrip(List<RecurringPayment> bills, bool isDark) {
    final now = DateTime.now();
    final days = List.generate(7, (i) => now.add(Duration(days: i)));
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Next 7 Days',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: days.map((day) {
            final dayBills = bills
                .where(
                  (b) =>
                      b.nextDueAt.year == day.year &&
                      b.nextDueAt.month == day.month &&
                      b.nextDueAt.day == day.day,
                )
                .toList();
            final hasBill = dayBills.isNotEmpty;
            final isToday = day.day == now.day && day.month == now.month && day.year == now.year;

            return Expanded(
              child: Column(
                children: [
                  Text(
                    dayLabels[day.weekday - 1],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isToday ? AppTheme.accentPurple : AppTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: hasBill
                          ? AppTheme.warningYellow.withAlpha(isDark ? 40 : 28)
                          : (isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5)),
                      shape: BoxShape.circle,
                      border: hasBill ? Border.all(color: AppTheme.warningYellow, width: 2) : null,
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: hasBill ? FontWeight.w700 : FontWeight.w500,
                          color: hasBill
                              ? AppTheme.warningYellow
                              : (isToday ? AppTheme.accentPurple : AppTheme.textTertiary),
                        ),
                      ),
                    ),
                  ),
                  if (hasBill) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppTheme.warningYellow,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Tab Selector ────────────────────────────────────────────────────────────

  Widget _buildTabSelector(int activeCount, int cancelledCount, bool isDark) {
    return Row(
      children: [
        ChoiceChip(
          label: Text('Active ($activeCount)'),
          selected: _selectedTab == 0,
          onSelected: (_) => setState(() => _selectedTab = 0),
          selectedColor: AppTheme.accentTeal.withAlpha(isDark ? 50 : 35),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text('Cancelled ($cancelledCount)'),
          selected: _selectedTab == 1,
          onSelected: (_) => setState(() => _selectedTab = 1),
          selectedColor: AppTheme.expenseRed.withAlpha(isDark ? 40 : 25),
        ),
      ],
    );
  }

  Widget _buildEmptyTabMessage(String msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          msg,
          style: const TextStyle(color: AppTheme.textTertiary),
        ),
      ),
    );
  }

  // ── Bill Card ───────────────────────────────────────────────────────────────

  Widget _buildBillCard(
    BuildContext context,
    RecurringPayment bill,
    RecurringProvider provider,
    bool isDark,
  ) {
    final now = DateTime.now();
    final isCancelled = bill.status == RecurringStatus.cancelled;
    final isDueToday = bill.nextDueAt.year == now.year &&
        bill.nextDueAt.month == now.month &&
        bill.nextDueAt.day == now.day;
    final daysUntil = bill.nextDueAt.difference(now).inDays;
    final isOverdue = !isCancelled && bill.nextDueAt.isBefore(now) && !isDueToday;
    final isDueSoon = !isCancelled && !isOverdue && daysUntil <= 3;

    final statusColor = isCancelled
        ? AppTheme.textTertiary
        : isOverdue
            ? AppTheme.expenseRed
            : isDueToday || isDueSoon
                ? AppTheme.warningYellow
                : AppTheme.incomeGreen;

    final statusText = isCancelled
        ? 'Cancelled'
        : isOverdue
            ? 'Overdue'
            : isDueToday
                ? 'Due today'
                : isDueSoon
                    ? '$daysUntil day${daysUntil == 1 ? '' : 's'}'
                    : 'In $daysUntil days';

    return Dismissible(
      key: Key(bill.id),
      direction: isCancelled ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.accentTeal.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.snooze_rounded, color: AppTheme.accentTeal),
            Text(
              'Snooze 1 Cycle',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.accentTeal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await provider.snoozeBill(bill.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${bill.merchantName} snoozed by one cycle'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return false;
      },
      child: InkWell(
        onTap: () => _showBillDetailSheet(context, bill, provider),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOverdue
                  ? AppTheme.expenseRed.withAlpha(60)
                  : (isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(7)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _billColor(bill.merchantName).withAlpha(isDark ? 35 : 22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _billIcon(bill.merchantName),
                  color: _billColor(bill.merchantName),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            bill.merchantName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                                ),
                          ),
                        ),
                        if (bill.isAutopay) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.accentPurple.withAlpha(isDark ? 35 : 20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'AUTOPAY',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accentPurple,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentTeal.withAlpha(isDark ? 25 : 18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            bill.frequencyEnum.displayName,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentTeal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isCancelled ? 'Cancelled' : 'Due ${_shortDateFmt.format(bill.nextDueAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currFmt.format(bill.amount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isCancelled ? AppTheme.textTertiary : AppTheme.expenseRed,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
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

  // ── Bill Detail Bottom Sheet ────────────────────────────────────────────────

  Future<void> _showBillDetailSheet(
    BuildContext context,
    RecurringPayment bill,
    RecurringProvider provider,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCancelled = bill.status == RecurringStatus.cancelled;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _billColor(bill.merchantName).withAlpha(isDark ? 40 : 25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _billIcon(bill.merchantName),
                      color: _billColor(bill.merchantName),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bill.merchantName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_currFmt.format(bill.amount)} / ${bill.frequencyEnum.displayName.toLowerCase()}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.accentTeal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit Bill',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddOrEditBillSheet(context, existingBill: bill);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (bill.isPriceChanged) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPurple.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentPurple.withAlpha(40)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up_rounded, color: AppTheme.accentPurple, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Price changed: ${_currFmt.format(bill.previousAmount)} → ${_currFmt.format(bill.amount)} (${bill.priceDifference >= 0 ? '+' : ''}${_currFmt.format(bill.priceDifference)}/cycle)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withAlpha(30) : Colors.grey.withAlpha(15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _buildDetailRow('Next Payment', _dateFmt.format(bill.nextDueAt)),
                    const Divider(height: 16),
                    _buildDetailRow('Last Paid', _dateFmt.format(bill.lastPaidAt)),
                    const Divider(height: 16),
                    _buildDetailRow('Payment Mode', bill.isAutopay ? 'Autopay' : 'Manual Payment'),
                    const Divider(height: 16),
                    _buildDetailRow('Annual Spend', _currFmt.format(bill.annualAmount)),
                    if (bill.notes != null && bill.notes!.isNotEmpty) ...[
                      const Divider(height: 16),
                      _buildDetailRow('Notes', bill.notes!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!isCancelled) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _promptMarkAsPaid(context, bill, provider);
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                        label: const Text('Mark as Paid', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.incomeGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await provider.snoozeBill(bill.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${bill.merchantName} snoozed 1 cycle'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.snooze_rounded),
                      label: const Text('Snooze'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showPaymentHistorySheet(context, bill, provider);
                      },
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('Payment History'),
                    ),
                  ),
                  if (!isCancelled)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await provider.cancelBill(bill.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${bill.merchantName} cancelled. History preserved.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: AppTheme.warningYellow),
                      label: const Text('Cancel Plan', style: TextStyle(color: AppTheme.warningYellow)),
                    )
                  else
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await provider.reopenBill(bill.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${bill.merchantName} reactivated.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.accentTeal),
                      label: const Text('Reactivate', style: TextStyle(color: AppTheme.accentTeal)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.expenseRed),
                    tooltip: 'Delete Permanently',
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Delete Commitment?'),
                          content: Text('Permanently delete ${bill.merchantName} and its payment history? This cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Keep')),
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Delete', style: TextStyle(color: AppTheme.expenseRed)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await provider.deleteBill(bill.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${bill.merchantName} deleted permanently'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  // ── Prompt Mark as Paid Dialog ──────────────────────────────────────────────

  Future<void> _promptMarkAsPaid(
    BuildContext context,
    RecurringPayment bill,
    RecurringProvider provider,
  ) async {
    DateTime paidDate = DateTime.now();
    final amountCtrl = TextEditingController(text: bill.amount.toStringAsFixed(0));
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Record Payment for ${bill.merchantName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount Paid (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Payment Date', style: TextStyle(fontSize: 13)),
                subtitle: Text(_dateFmt.format(paidDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.calendar_today_rounded, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: paidDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setS(() => paidDate = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Optional note / ref ID',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? bill.amount;
                await provider.markAsPaid(
                  bill.id,
                  paidAt: paidDate,
                  amount: amount,
                  note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment of ${_currFmt.format(amount)} recorded for ${bill.merchantName}. Schedule updated.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.incomeGreen),
              child: const Text('Confirm Paid', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Payment History Sheet ───────────────────────────────────────────────────

  Future<void> _showPaymentHistorySheet(
    BuildContext context,
    RecurringPayment bill,
    RecurringProvider provider,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = await provider.getHistory(bill.id);

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.cardDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Payment History: ${bill.merchantName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Audit log of recorded payments for this commitment.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No payments recorded yet.\nMark occurrences as paid to build history.',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppTheme.textTertiary),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final h = history[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.incomeGreen,
                        child: Icon(Icons.check, size: 16, color: Colors.white),
                      ),
                      title: Text(_dateFmt.format(h.paidAt), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                        '${h.source.toUpperCase()}${h.notes != null ? " • ${h.notes}" : ""}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                      ),
                      trailing: Text(
                        _currFmt.format(h.amount),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.incomeGreen),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Add or Edit Bill Sheet ──────────────────────────────────────────────────

  Future<void> _showAddOrEditBillSheet(
    BuildContext context, {
    RecurringPayment? existingBill,
    bool isConfirmingDetection = false,
  }) async {
    final provider = context.read<RecurringProvider>();
    final catProvider = context.read<CategoryProvider>();

    final isEdit = existingBill != null && !isConfirmingDetection;
    final merchantCtrl = TextEditingController(text: existingBill?.merchantName ?? '');
    final amountCtrl = TextEditingController(text: existingBill != null ? existingBill.amount.toStringAsFixed(0) : '');
    final noteCtrl = TextEditingController(text: existingBill?.notes ?? '');

    String frequency = existingBill?.frequency ?? 'monthly';
    DateTime nextDue = existingBill?.nextDueAt ?? DateTime.now().add(const Duration(days: 30));
    String categoryId = existingBill?.categoryId ?? 'other';
    bool isAutopay = existingBill?.isAutopay ?? false;

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit
                      ? 'Edit Recurring Commitment'
                      : isConfirmingDetection
                          ? 'Confirm Detected Commitment'
                          : 'Add Recurring Bill',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: merchantCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Merchant / Subscription name',
                    prefixIcon: Icon(Icons.store_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: frequency,
                  decoration: const InputDecoration(
                    labelText: 'Billing frequency',
                    prefixIcon: Icon(Icons.repeat_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'quarterly', child: Text('Every 3 months')),
                    DropdownMenuItem(value: 'semiannual', child: Text('Every 6 months')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (v) => setS(() => frequency = v ?? 'monthly'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withAlpha(80)),
                  ),
                  leading: const Icon(Icons.calendar_today_rounded, color: AppTheme.accentTeal),
                  title: const Text('Next Payment Date', style: TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
                  subtitle: Text(_dateFmt.format(nextDue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  trailing: const Text('Change', style: TextStyle(color: AppTheme.accentTeal, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: nextDue,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (picked != null) {
                      setS(() => nextDue = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: catProvider.categories.any((c) => c.id == categoryId)
                      ? categoryId
                      : 'other',
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'other', child: Text('General / Other')),
                    ...catProvider.categories
                        .where((c) => c.id != 'other')
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setS(() => categoryId = v ?? 'other'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic Payment (Autopay)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Remind to check balance rather than manual bill payment.', style: TextStyle(fontSize: 11)),
                  value: isAutopay,
                  activeThumbColor: AppTheme.accentTeal,
                  onChanged: (v) => setS(() => isAutopay = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Account number (Optional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = merchantCtrl.text.trim();
                      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a merchant or subscription name.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      if (amount <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a valid amount greater than \u20B90.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      final notes = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

                      if (isEdit) {
                        provider.editBill(
                          existingBill.id,
                          merchantName: name,
                          amount: amount,
                          frequency: frequency,
                          nextDueAt: nextDue,
                          categoryId: categoryId,
                          isAutopay: isAutopay,
                          notes: notes,
                        );
                      } else if (isConfirmingDetection && existingBill != null) {
                        provider.confirmDetected(
                          existingBill.id,
                          merchantName: name,
                          amount: amount,
                          frequency: frequency,
                          nextDueAt: nextDue,
                          categoryId: categoryId,
                          isAutopay: isAutopay,
                          notes: notes,
                        );
                      } else {
                        provider.addManual(
                          merchantName: name,
                          amount: amount,
                          frequency: frequency,
                          nextDueAt: nextDue,
                          categoryId: categoryId,
                          isAutopay: isAutopay,
                          notes: notes,
                        );
                      }
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentTeal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      isEdit ? 'Save Changes' : isConfirmingDetection ? 'Confirm Commitment' : 'Add Bill',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────────────────────

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.accentTeal.withAlpha(isDark ? 40 : 28),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.repeat_rounded,
                size: 40,
                color: AppTheme.accentTeal,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Bills Tracked',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add subscriptions manually to track upcoming dues, or\nlet P.E.T. detect repeating patterns from your transactions.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddOrEditBillSheet(context),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add Bill', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentTeal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
