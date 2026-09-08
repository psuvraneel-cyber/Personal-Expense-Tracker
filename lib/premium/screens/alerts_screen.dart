import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/screens/cashflow_screen.dart';
import 'package:pet/premium/screens/goals_screen.dart';
import 'package:pet/premium/screens/recurring_bills_screen.dart';
import 'package:pet/premium/widgets/premium_gate.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/screens/budget/budget_screen.dart';
import 'package:pet/screens/transactions/transactions_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<AlertProvider>();
      if (!provider.isLoaded && !provider.isLoading) {
        provider.load();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<AlertProvider>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.expenseRed.withAlpha(isDark ? 40 : 28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: AppTheme.expenseRed,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Alerts Centre'),
          ],
        ),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          Consumer<AlertProvider>(
            builder: (_, provider, _) {
              if (provider.unreadCount == 0 && provider.alerts.isEmpty) {
                return const SizedBox.shrink();
              }
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'mark_all_read') {
                    provider.markAllRead();
                  } else if (value == 'dismiss_all_read') {
                    provider.dismissAllRead();
                  }
                },
                itemBuilder: (ctx) => [
                  if (provider.unreadCount > 0)
                    const PopupMenuItem(
                      value: 'mark_all_read',
                      child: Row(
                        children: [
                          Icon(Icons.done_all_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Mark all read'),
                        ],
                      ),
                    ),
                  if (provider.alerts.any((a) => a.isRead))
                    const PopupMenuItem(
                      value: 'dismiss_all_read',
                      child: Row(
                        children: [
                          Icon(Icons.cleaning_services_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Dismiss all read'),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumGate(
        title: 'Alerts Centre',
        subtitle: 'Budget, anomaly, and bill alerts in one place.',
        child: Consumer<AlertProvider>(
          builder: (context, provider, _) {
            return RefreshIndicator(
              onRefresh: () => provider.load(),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryBanner(provider, isDark),
                          const SizedBox(height: 14),
                          _buildFilterChips(provider, isDark),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  if (provider.isLoading && provider.alerts.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (provider.alerts.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmpty(isDark, provider),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index == provider.alerts.length) {
                              if (provider.hasMore) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }
                            final alert = provider.alerts[index];
                            return _buildDismissibleAlertCard(
                              alert,
                              isDark,
                              provider,
                            );
                          },
                          childCount: provider.alerts.length +
                              (provider.hasMore ? 1 : 0),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryBanner(AlertProvider provider, bool isDark) {
    final unread = provider.unreadCount;
    final hasCritical = provider.alerts.any(
      (a) => !a.isRead && a.severity == AlertSeverity.critical,
    );

    if (unread == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.incomeGreen.withAlpha(isDark ? 25 : 15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.incomeGreen.withAlpha(isDark ? 55 : 35),
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: AppTheme.incomeGreen,
              size: 24,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All caught up!',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.incomeGreen,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'No active anomalies or budget overruns detected.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final bannerColor = hasCritical ? AppTheme.expenseRed : AppTheme.warningYellow;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            bannerColor.withAlpha(isDark ? 50 : 35),
            bannerColor.withAlpha(isDark ? 25 : 15),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bannerColor.withAlpha(isDark ? 70 : 50),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bannerColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasCritical
                  ? Icons.warning_rounded
                  : Icons.notifications_active_rounded,
              color: bannerColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$unread unread alert${unread > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: bannerColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasCritical
                      ? 'Critical financial thresholds breached'
                      : 'Review recent budget pacing & anomalies',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => provider.markAllRead(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text('Read all', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(AlertProvider provider, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: provider.filterType == null && !provider.filterUnreadOnly,
            onSelected: (_) => provider.clearFilters(),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unread'),
                if (provider.unreadCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.expenseRed,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${provider.unreadCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            selected: provider.filterUnreadOnly,
            onSelected: (val) => provider.setFilterUnreadOnly(val),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Budgets'),
            selected: provider.filterType == AppAlertType.budget,
            onSelected: (val) =>
                provider.setFilterType(val ? AppAlertType.budget : null),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Anomalies'),
            selected: provider.filterType == AppAlertType.anomaly,
            onSelected: (val) =>
                provider.setFilterType(val ? AppAlertType.anomaly : null),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Bills'),
            selected: provider.filterType == AppAlertType.bill,
            onSelected: (val) =>
                provider.setFilterType(val ? AppAlertType.bill : null),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Cashflow'),
            selected: provider.filterType == AppAlertType.cashflow,
            onSelected: (val) =>
                provider.setFilterType(val ? AppAlertType.cashflow : null),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Goals'),
            selected: provider.filterType == AppAlertType.goal,
            onSelected: (val) =>
                provider.setFilterType(val ? AppAlertType.goal : null),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissibleAlertCard(
    AppAlert alert,
    bool isDark,
    AlertProvider provider,
  ) {
    return Dismissible(
      key: ValueKey('${alert.id}_${alert.updatedAt?.millisecondsSinceEpoch ?? alert.createdAt.millisecondsSinceEpoch}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.expenseRed.withAlpha(200),
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_outlined, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Dismiss',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) {
        provider.dismiss(alert.id);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Alert dismissed'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => provider.undoDismiss(alert),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      },
      child: _buildAlertCard(alert, isDark, provider),
    );
  }

  Widget _buildAlertCard(
    AppAlert alert,
    bool isDark,
    AlertProvider provider,
  ) {
    final typeConfig = _alertTypeConfig(alert.type);
    final categoryProvider = context.watch<CategoryProvider>();
    final category = alert.categoryId != null
        ? categoryProvider.getCategoryById(alert.categoryId!)
        : null;

    final cardColor = alert.severity == AlertSeverity.critical
        ? AppTheme.expenseRed
        : alert.severity == AlertSeverity.warning
            ? AppTheme.warningYellow
            : typeConfig.color;

    final timeFmt = DateFormat('d MMM, h:mm a');

    return AnimatedOpacity(
      opacity: alert.isRead ? 0.65 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: alert.isRead
                ? (isDark
                    ? Colors.white.withAlpha(8)
                    : Colors.black.withAlpha(8))
                : cardColor.withAlpha(isDark ? 70 : 45),
            width: alert.isRead ? 1.0 : 1.5,
          ),
          boxShadow: alert.isRead
              ? []
              : [
                  BoxShadow(
                    color: cardColor.withAlpha(isDark ? 25 : 15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: alert.isRead ? null : () => provider.markRead(alert.id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (category?.color ?? cardColor)
                            .withAlpha(isDark ? 35 : 22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        category?.icon ?? typeConfig.icon,
                        color: category?.color ?? cardColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  alert.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: alert.isRead
                                        ? AppTheme.textTertiary
                                        : null,
                                  ),
                                ),
                              ),
                              if (!alert.isRead) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              _buildSeverityBadge(alert.severity, isDark),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alert.message,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      height: 1.4,
                                      color: alert.isRead
                                          ? AppTheme.textTertiary
                                          : null,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Financial Progress Indicator if budget
                if (alert.type == AppAlertType.budget && alert.ratio != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: alert.ratio!.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        alert.ratio! >= 1.0
                            ? AppTheme.expenseRed
                            : alert.ratio! >= 0.9
                                ? AppTheme.warningYellow
                                : AppTheme.incomeGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(alert.ratio! * 100).toStringAsFixed(0)}% used',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cardColor,
                        ),
                      ),
                      if (alert.amount != null && alert.targetAmount != null)
                        Text(
                          '₹${alert.amount!.toStringAsFixed(0)} of ₹${alert.targetAmount!.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Bottom bar: Category/Type tag, timestamp, and contextual actions
                Row(
                  children: [
                    if (category != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: category.color.withAlpha(isDark ? 25 : 15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category.name,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: category.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      timeFmt.format(alert.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    _buildContextualActionButton(alert),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeverityBadge(AlertSeverity severity, bool isDark) {
    final (color, label) = switch (severity) {
      AlertSeverity.critical => (AppTheme.expenseRed, 'CRITICAL'),
      AlertSeverity.warning => (AppTheme.warningYellow, 'WARNING'),
      AlertSeverity.info => (AppTheme.accentPurple, 'INFO'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildContextualActionButton(AppAlert alert) {
    switch (alert.type) {
      case AppAlertType.budget:
        return TextButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BudgetScreen()),
            );
          },
          icon: const Icon(Icons.tune_rounded, size: 14),
          label: const Text('Adjust', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case AppAlertType.anomaly:
      case AppAlertType.largeTransaction:
      case AppAlertType.duplicateTransaction:
        return TextButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TransactionsScreen()),
            );
          },
          icon: const Icon(Icons.receipt_long_rounded, size: 14),
          label: const Text('Transactions', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case AppAlertType.bill:
        return TextButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringBillsScreen()),
            );
          },
          icon: const Icon(Icons.payment_rounded, size: 14),
          label: const Text('View Bill', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case AppAlertType.cashflow:
        return TextButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CashflowScreen()),
            );
          },
          icon: const Icon(Icons.insights_rounded, size: 14),
          label: const Text('Forecast', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case AppAlertType.goal:
        return TextButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GoalsScreen()),
            );
          },
          icon: const Icon(Icons.flag_rounded, size: 14),
          label: const Text('Goals', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEmpty(bool isDark, AlertProvider provider) {
    final hasFilters =
        provider.filterType != null || provider.filterUnreadOnly;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.incomeGreen.withAlpha(isDark ? 35 : 20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_rounded,
                size: 34,
                color: AppTheme.incomeGreen,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFilters ? 'No Matching Alerts' : 'No Alerts',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'No alerts match your current filter settings.'
                  : 'All clear! Alerts appear here when budgets are breached, spending spikes detected, or upcoming bills require attention.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => provider.clearFilters(),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text('Reset Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

({IconData icon, Color color, String label}) _alertTypeConfig(AppAlertType type) {
  return switch (type) {
    AppAlertType.budget => (
      icon: Icons.account_balance_wallet_rounded,
      color: AppTheme.expenseRed,
      label: 'Budget',
    ),
    AppAlertType.anomaly => (
      icon: Icons.trending_up_rounded,
      color: AppTheme.warningYellow,
      label: 'Anomaly',
    ),
    AppAlertType.largeTransaction => (
      icon: Icons.priority_high_rounded,
      color: AppTheme.warningYellow,
      label: 'Large Txn',
    ),
    AppAlertType.duplicateTransaction => (
      icon: Icons.copy_rounded,
      color: AppTheme.expenseRed,
      label: 'Duplicate',
    ),
    AppAlertType.bill => (
      icon: Icons.receipt_long_rounded,
      color: AppTheme.accentTeal,
      label: 'Bill',
    ),
    AppAlertType.cashflow => (
      icon: Icons.waterfall_chart_rounded,
      color: AppTheme.accentPurple,
      label: 'Cashflow',
    ),
    AppAlertType.goal => (
      icon: Icons.emoji_events_rounded,
      color: AppTheme.incomeGreen,
      label: 'Goal',
    ),
    AppAlertType.system => (
      icon: Icons.info_rounded,
      color: AppTheme.accentPurple,
      label: 'System',
    ),
  };
}
