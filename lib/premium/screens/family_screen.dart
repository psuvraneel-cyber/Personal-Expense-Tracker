import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/providers/family_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Household Members'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          IconButton(
            onPressed: () => _showAddMember(context),
            icon: const Icon(Icons.person_add_rounded),
            tooltip: 'Add Member',
          ),
        ],
      ),
      body: PremiumGate(
        title: 'Household Members',
        subtitle: 'Track spending for household members on this device.',
        child: Consumer<FamilyProvider>(
          builder: (context, provider, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                // Local tracking transparency banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accentTeal.withAlpha(isDark ? 25 : 15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.accentTeal.withAlpha(isDark ? 50 : 30),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📱 ', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Local Device Tracking: Member profiles and limits are saved on this device. '
                          'Cross-device sync and family invitation features are planned for an upcoming release.',
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
                const SizedBox(height: 16),
                if (provider.members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 56,
                            color: AppTheme.textTertiary.withAlpha(120),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No household members yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap + to add people you share expenses with.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...provider.members.map((member) {
                    final hasLimit = member.monthlyLimit != null && member.monthlyLimit! > 0;
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
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.accentPurple.withAlpha(35),
                          child: Text(
                            member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentPurple,
                            ),
                          ),
                        ),
                        title: Text(
                          member.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          hasLimit
                              ? 'Monthly limit: ${fmt.format(member.monthlyLimit)}'
                              : 'Household member',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasLimit ? AppTheme.accentTeal : AppTheme.textTertiary,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.expenseRed),
                          onPressed: () => provider.removeMember(member.id),
                          tooltip: 'Remove',
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddMember(BuildContext context) async {
    final nameController = TextEditingController();
    final limitController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Household Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Spouse, Roommate',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly Spending Limit (₹, optional)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final limit = double.tryParse(limitController.text.trim());
                context.read<FamilyProvider>().addMember(
                  name: name,
                  monthlyLimit: (limit != null && limit > 0) ? limit : null,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}
