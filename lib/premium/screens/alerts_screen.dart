import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/budget_alert.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertProvider>().load();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Budget'),
            Tab(text: 'Anomaly'),
          ],
          indicatorColor: AppTheme.accentPurple,
          labelColor: AppTheme.accentPurple,
          unselectedLabelColor: AppTheme.textTertiary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
        ),
        actions: [
          Consumer<AlertProvider>(
            builder: (_, provider, _) {
              final unread = provider.alerts.where((a) => !a.isRead).length;
              if (unread == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => provider.markAllRead(),
                child: Text(
                  'Mark all read',
                  style: TextStyle(
                    color: AppTheme.accentPurple,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final all = provider.alerts;
            final budget = all.where((a) => a.type == 'budget').toList();
            final anomaly = all.where((a) => a.type == 'anomaly').toList();

            return TabBarView(
              controller: _tabCtrl,
              children: [
                _buildAlertList(all, isDark, provider),
                _buildAlertList(budget, isDark, provider),
                _buildAlertList(anomaly, isDark, provider),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAlertList(
    List<BudgetAlert> alerts,
    bool isDark,
    AlertProvider provider,
  ) {
    if (alerts.isEmpty) {
      return _buildEmpty(isDark);
    }

    final unread = alerts.where((a) => !a.isRead).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        if (unread > 0)
          _buildUnreadBanner(unread, isDark)
        else
          _buildAllClearBanner(isDark),
        const SizedBox(height: 14),
        ...alerts.map((alert) => _buildAlertCard(alert, isDark, provider)),
      ],
    );
  }

  Widget _buildUnreadBanner(int unread, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.expenseRed.withAlpha(isDark ? 50 : 35),
            AppTheme.warningYellow.withAlpha(isDark ? 35 : 22),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.expenseRed.withAlpha(isDark ? 60 : 40),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.expenseRed.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.expenseRed,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$unread unread alert${unread > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.expenseRed,
                ),
              ),
              Text(
                'Tap an alert to mark it as read',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.expenseRed.withAlpha(180),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllClearBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.incomeGreen.withAlpha(isDark ? 25 : 15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.incomeGreen.withAlpha(isDark ? 55 : 35),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.incomeGreen.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.incomeGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'All caught up! No unread alerts.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppTheme.incomeGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(
    BudgetAlert alert,
    bool isDark,
    AlertProvider provider,
  ) {
    final typeConfig = _alertTypeConfig(alert.type);
    final timeFmt = DateFormat('d MMM, h:mm a');

    return AnimatedOpacity(
      opacity: alert.isRead ? 0.55 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: alert.isRead ? null : () => provider.markRead(alert.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: alert.isRead
                  ? (isDark
                        ? Colors.white.withAlpha(8)
                        : Colors.black.withAlpha(5))
                  : typeConfig.color.withAlpha(isDark ? 60 : 40),
            ),
            boxShadow: alert.isRead
                ? []
                : [
                    BoxShadow(
                      color: typeConfig.color.withAlpha(isDark ? 20 : 12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: typeConfig.color.withAlpha(isDark ? 30 : 20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(typeConfig.icon, color: typeConfig.color, size: 20),
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
                        if (!alert.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: typeConfig.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: alert.isRead ? AppTheme.textTertiary : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: typeConfig.color.withAlpha(isDark ? 25 : 15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeConfig.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: typeConfig.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeFmt.format(alert.createdAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        if (!alert.isRead) ...const [
                          Spacer(),
                          Text(
                            'Tap to dismiss',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                color: AppTheme.incomeGreen.withAlpha(isDark ? 35 : 22),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_rounded,
                size: 38,
                color: AppTheme.incomeGreen,
              ),
            ),
            const SizedBox(height: 20),
            Text('No Alerts', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'All clear! Alerts appear here when budgets\nare breached or spending spikes detected.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

({IconData icon, Color color, String label}) _alertTypeConfig(String type) {
  return switch (type) {
    'budget' => (
      icon: Icons.account_balance_wallet_rounded,
      color: AppTheme.expenseRed,
      label: 'Budget',
    ),
    'anomaly' => (
      icon: Icons.trending_up_rounded,
      color: AppTheme.warningYellow,
      label: 'Anomaly',
    ),
    'bill' => (
      icon: Icons.receipt_long_rounded,
      color: AppTheme.accentTeal,
      label: 'Bill',
    ),
    _ => (
      icon: Icons.info_rounded,
      color: AppTheme.accentPurple,
      label: 'Info',
    ),
  };
}

// Extension to support markAllRead
extension on AlertProvider {
  void markAllRead() {
    for (final a in alerts.where((a) => !a.isRead)) {
      markRead(a.id);
    }
  }
}
