import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pet/premium/services/invoice_calculator.dart';

/// One line of an invoice.
@immutable
class InvoiceItem {
  const InvoiceItem({
    required this.description,
    this.quantity = 1,
    this.unit = '',
    required this.rate,
    this.hsnSac = '',
    this.gstRate = 0,
  });

  final String description;
  final double quantity;
  final String unit;
  final double rate;

  /// HSN (goods) or SAC (services) code, needed on GST invoices.
  final String hsnSac;
  final double gstRate;

  double get amount => InvoiceCalculator.round2(quantity * rate);

  Map<String, dynamic> toMap() => {
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'rate': rate,
        'hsnSac': hsnSac,
        'gstRate': gstRate,
      };

  factory InvoiceItem.fromMap(Map<String, dynamic> m) => InvoiceItem(
        description: m['description'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        unit: m['unit'] as String? ?? '',
        rate: (m['rate'] as num?)?.toDouble() ?? 0,
        hsnSac: m['hsnSac'] as String? ?? '',
        gstRate: (m['gstRate'] as num?)?.toDouble() ?? 0,
      );
}

/// Money received against an invoice.
@immutable
class InvoicePayment {
  const InvoicePayment({
    required this.id,
    required this.amount,
    required this.date,
    this.method = 'UPI',
    this.transactionId,
    this.note = '',
  });

  final String id;
  final double amount;
  final DateTime date;
  final String method;

  /// The ledger transaction this payment was matched to, if any.
  final String? transactionId;
  final String note;

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'date': date.toIso8601String(),
        'method': method,
        'transactionId': transactionId,
        'note': note,
      };

  factory InvoicePayment.fromMap(Map<String, dynamic> m) => InvoicePayment(
        id: m['id'] as String,
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.parse(m['date'] as String),
        method: m['method'] as String? ?? 'UPI',
        transactionId: m['transactionId'] as String?,
        note: m['note'] as String? ?? '',
      );
}

/// Who an invoice is addressed to, copied when it is issued so later edits
/// to the client don't change invoices already sent.
@immutable
class BillTo {
  const BillTo({
    required this.name,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.gstin = '',
    this.stateCode = '',
  });

  final String name;
  final String address;
  final String phone;
  final String email;
  final String gstin;
  final String stateCode;

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        'gstin': gstin,
        'stateCode': stateCode,
      };

  factory BillTo.fromMap(Map<String, dynamic> m) => BillTo(
        name: m['name'] as String? ?? '',
        address: m['address'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        gstin: m['gstin'] as String? ?? '',
        stateCode: m['stateCode'] as String? ?? '',
      );
}

/// Stored workflow state. Paid, partly paid and overdue are worked out from
/// payments and the due date (see [Invoice.displayStatus]).
enum InvoiceStatus { draft, sent, cancelled }

/// What the user sees.
enum InvoiceDisplayStatus {
  draft('Draft'),
  sent('Sent'),
  overdue('Overdue'),
  partiallyPaid('Partly paid'),
  paid('Paid'),
  cancelled('Cancelled');

  const InvoiceDisplayStatus(this.label);
  final String label;
}

/// An invoice the user sends to a client.
@immutable
class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    this.clientId,
    required this.billTo,
    required this.issueDate,
    required this.dueDate,
    this.status = InvoiceStatus.draft,
    this.gstEnabled = false,
    this.placeOfSupply = '',
    this.items = const [],
    this.discount = 0,
    this.notes = '',
    this.payments = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String number;
  final String? clientId;
  final BillTo billTo;
  final DateTime issueDate;
  final DateTime dueDate;
  final InvoiceStatus status;
  final bool gstEnabled;

  /// State code of the place of supply (the client's state).
  final String placeOfSupply;
  final List<InvoiceItem> items;
  final double discount;
  final String notes;
  final List<InvoicePayment> payments;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const int maxItems = 100;

  /// IGST applies when the client's state differs from [businessState].
  bool isInterState(String businessState) =>
      placeOfSupply.isNotEmpty &&
      businessState.isNotEmpty &&
      placeOfSupply != businessState;

  InvoiceTotals totals(String businessState) => InvoiceCalculator.compute(
        items: items,
        discount: discount,
        gstEnabled: gstEnabled,
        interState: isInterState(businessState),
      );

  double get amountPaid =>
      InvoiceCalculator.round2(payments.fold(0.0, (s, p) => s + p.amount));

  double balanceDue(String businessState) => InvoiceCalculator.round2(
      (totals(businessState).total - amountPaid).clamp(0, double.infinity));

  InvoiceDisplayStatus displayStatus(String businessState, DateTime now) {
    if (status == InvoiceStatus.cancelled) {
      return InvoiceDisplayStatus.cancelled;
    }
    if (status == InvoiceStatus.draft) return InvoiceDisplayStatus.draft;
    final total = totals(businessState).total;
    if (total > 0 && amountPaid >= total - 0.005) {
      return InvoiceDisplayStatus.paid;
    }
    final today = DateTime(now.year, now.month, now.day);
    if (dueDate.isBefore(today)) return InvoiceDisplayStatus.overdue;
    if (amountPaid > 0) return InvoiceDisplayStatus.partiallyPaid;
    return InvoiceDisplayStatus.sent;
  }

  Invoice copyWith({
    String? number,
    String? clientId,
    BillTo? billTo,
    DateTime? issueDate,
    DateTime? dueDate,
    InvoiceStatus? status,
    bool? gstEnabled,
    String? placeOfSupply,
    List<InvoiceItem>? items,
    double? discount,
    String? notes,
    List<InvoicePayment>? payments,
    DateTime? updatedAt,
  }) =>
      Invoice(
        id: id,
        number: number ?? this.number,
        clientId: clientId ?? this.clientId,
        billTo: billTo ?? this.billTo,
        issueDate: issueDate ?? this.issueDate,
        dueDate: dueDate ?? this.dueDate,
        status: status ?? this.status,
        gstEnabled: gstEnabled ?? this.gstEnabled,
        placeOfSupply: placeOfSupply ?? this.placeOfSupply,
        items: items ?? this.items,
        discount: discount ?? this.discount,
        notes: notes ?? this.notes,
        payments: payments ?? this.payments,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Firestore document (lists stay lists).
  Map<String, dynamic> toMap() => {
        'id': id,
        'number': number,
        'clientId': clientId,
        'billTo': billTo.toMap(),
        'issueDate': issueDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'status': status.name,
        'gstEnabled': gstEnabled,
        'placeOfSupply': placeOfSupply,
        'items': [for (final i in items) i.toMap()],
        'discount': discount,
        'notes': notes,
        'payments': [for (final p in payments) p.toMap()],
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Invoice.fromMap(Map<String, dynamic> m) => Invoice(
        id: m['id'] as String,
        number: m['number'] as String,
        clientId: m['clientId'] as String?,
        billTo: BillTo.fromMap(Map<String, dynamic>.from(m['billTo'] as Map)),
        issueDate: DateTime.parse(m['issueDate'] as String),
        dueDate: DateTime.parse(m['dueDate'] as String),
        status: InvoiceStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => InvoiceStatus.draft,
        ),
        gstEnabled: m['gstEnabled'] as bool? ?? false,
        placeOfSupply: m['placeOfSupply'] as String? ?? '',
        items: [
          for (final i in (m['items'] as List? ?? const []))
            InvoiceItem.fromMap(Map<String, dynamic>.from(i as Map)),
        ],
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String? ?? '',
        payments: [
          for (final p in (m['payments'] as List? ?? const []))
            InvoicePayment.fromMap(Map<String, dynamic>.from(p as Map)),
        ],
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );

  /// SQLite row: nested values stored as JSON text.
  Map<String, dynamic> toRow() {
    final m = toMap();
    return {
      ...m,
      'billTo': jsonEncode(m['billTo']),
      'items': jsonEncode(m['items']),
      'payments': jsonEncode(m['payments']),
      'gstEnabled': gstEnabled ? 1 : 0,
    };
  }

  factory Invoice.fromRow(Map<String, dynamic> row) => Invoice.fromMap({
        ...row,
        'billTo': jsonDecode(row['billTo'] as String),
        'items': jsonDecode(row['items'] as String),
        'payments': jsonDecode(row['payments'] as String),
        'gstEnabled': row['gstEnabled'] == 1,
      });
}
