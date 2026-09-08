import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/providers/linked_account_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

class LinkedAccountsScreen extends StatelessWidget {
  const LinkedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Linked Accounts'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      ),
      body: PremiumGate(
        title: 'Linked Accounts (Preview)',
        subtitle: 'Direct bank and UPI integrations in active development.',
        child: Consumer<LinkedAccountProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Coming soon info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withAlpha(isDark ? 30 : 18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withAlpha(isDark ? 60 : 40),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🏦 ', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Coming Soon: Direct Bank Sync',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Automated bank feeds via RBI Account Aggregator framework are currently being integrated. '
                              'In the meantime, your transactions are parsed seamlessly from local SMS notifications.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.textSecondary
                                    : AppTheme.textSecondaryLight,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (provider.accounts.isNotEmpty) ...[
                  Text(
                    'Active Connections',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ...provider.accounts.map((account) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.cardDark : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withAlpha(10)
                              : Colors.black.withAlpha(7),
                        ),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.account_balance_rounded, color: AppTheme.accentTeal),
                        title: Text(account.accountName),
                        subtitle: Text(account.accountType),
                        trailing: IconButton(
                          icon: const Icon(Icons.link_off_rounded, color: AppTheme.expenseRed),
                          onPressed: () => provider.disconnectAccount(account.id),
                        ),
                      ),
                    );
                  }),
                ],
                if (kDebugMode && provider.isTesting) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: provider.connectMockAccount,
                    icon: const Icon(Icons.developer_mode_rounded),
                    label: const Text('Connect Mock Account (Debug Only)'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
