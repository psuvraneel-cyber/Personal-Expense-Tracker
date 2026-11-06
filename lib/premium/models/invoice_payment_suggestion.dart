import 'package:flutter/foundation.dart';

/// A received payment that might belong to an invoice, waiting for the user
/// to say yes or no. Worked out on this device from imported transactions,
/// so it stays here and is never synced.
@immutable
class InvoicePaymentSuggestion {
  const InvoicePaymentSuggestion({
    required this.id,
    required this.invoiceId,
    required this.transactionId,
    required this.amount,
    required this.date,
    this.payer = '',
  });

  final String id;
  final String invoiceId;

  /// The ledger transaction the money arrived in.
  final String transactionId;
  final double amount;
  final DateTime date;

  /// Who the bank says paid; empty when it didn't say.
  final String payer;

  Map<String, dynamic> toRow() => {
        'id': id,
        'invoiceId': invoiceId,
        'transactionId': transactionId,
        'amount': amount,
        'date': date.toIso8601String(),
        'payer': payer,
      };

  factory InvoicePaymentSuggestion.fromRow(Map<String, dynamic> m) =>
      InvoicePaymentSuggestion(
        id: m['id'] as String,
        invoiceId: m['invoiceId'] as String,
        transactionId: m['transactionId'] as String,
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.parse(m['date'] as String),
        payer: m['payer'] as String? ?? '',
      );
}
