import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:pet/premium/providers/linked_account_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

class LinkedAccountsScreen extends StatelessWidget {
  const LinkedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Linked Accounts')),
      body: PremiumGate(
        title: 'Linked accounts',
        subtitle: 'Connect bank and wallet feeds.',
        child: Consumer<LinkedAccountProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Provider: ${provider.providerName}'),
                const SizedBox(height: 12),
                ...provider.accounts.map((account) {
                  return ListTile(
                    title: Text(account.accountName),
                    subtitle: Text(account.accountType),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off_rounded),
                      onPressed: () => provider.disconnectAccount(account.id),
                    ),
                  );
                }),
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: provider.connectMockAccount,
                    child: const Text('Connect mock account'),
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
