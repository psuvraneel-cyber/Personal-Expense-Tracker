import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/screens/transactions/add_edit_transaction_screen.dart';

/// Opens the edit screen for a transaction auto-imported from an SMS or
/// notification (deep link target of the "Edit" notification action).
class TransactionEditLoader extends StatefulWidget {
  final String observationId;
  const TransactionEditLoader({super.key, required this.observationId});

  @override
  State<TransactionEditLoader> createState() => _TransactionEditLoaderState();
}

class _TransactionEditLoaderState extends State<TransactionEditLoader> {
  late final Future<TransactionRecord?> _lookup = _find();

  Future<TransactionRecord?> _find() async {
    final provider = context.read<TransactionProvider>();
    TransactionRecord? match() => provider.allTransactions
        .where((t) => t.sourceObservationId == widget.observationId)
        .firstOrNull;
    // The app may have been opened straight from the notification, before
    // the ledger finished loading.
    final found = match();
    if (found != null) return found;
    await provider.reloadFromLocal();
    return match();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TransactionRecord?>(
      future: _lookup,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final txn = snap.data;
        if (txn == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Transaction')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This transaction no longer exists. It may have been '
                  'deleted or ignored.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return AddEditTransactionScreen(transaction: txn);
      },
    );
  }
}
