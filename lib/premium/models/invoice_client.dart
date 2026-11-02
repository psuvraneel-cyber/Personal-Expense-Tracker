import 'package:flutter/foundation.dart';
import 'package:pet/premium/models/invoice.dart';

/// Someone the user sends invoices to.
@immutable
class InvoiceClient {
  const InvoiceClient({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.gstin = '',
    this.stateCode = '',
    this.upiId = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String address;
  final String phone;
  final String email;
  final String gstin;
  final String stateCode;

  /// The UPI ID they usually pay from: lets P.E.T recognise their payment.
  final String upiId;
  final DateTime createdAt;
  final DateTime updatedAt;

  BillTo toBillTo() => BillTo(
        name: name,
        address: address,
        phone: phone,
        email: email,
        gstin: gstin,
        stateCode: stateCode,
      );

  InvoiceClient copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? gstin,
    String? stateCode,
    String? upiId,
    DateTime? updatedAt,
  }) =>
      InvoiceClient(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        gstin: gstin ?? this.gstin,
        stateCode: stateCode ?? this.stateCode,
        upiId: upiId ?? this.upiId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        'gstin': gstin,
        'stateCode': stateCode,
        'upiId': upiId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory InvoiceClient.fromMap(Map<String, dynamic> m) => InvoiceClient(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        address: m['address'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        gstin: m['gstin'] as String? ?? '',
        stateCode: m['stateCode'] as String? ?? '',
        upiId: m['upiId'] as String? ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
}

/// The user's business details printed on every invoice.
@immutable
class InvoiceProfile {
  const InvoiceProfile({
    this.businessName = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.upiId = '',
    this.gstEnabled = false,
    this.gstin = '',
    this.stateCode = '',
    this.prefix = 'INV',
    this.dueDays = 15,
    this.defaultGstRate = 18,
    this.terms = '',
    this.updatedAt,
  });

  final String businessName;
  final String address;
  final String phone;
  final String email;

  /// Where clients pay: printed as a QR code with the exact amount.
  final String upiId;
  final bool gstEnabled;
  final String gstin;

  /// State code of the business (decides CGST+SGST vs IGST).
  final String stateCode;
  final String prefix;
  final int dueDays;
  final double defaultGstRate;
  final String terms;
  final DateTime? updatedAt;

  bool get isSetUp => businessName.trim().isNotEmpty;

  InvoiceProfile copyWith({
    String? businessName,
    String? address,
    String? phone,
    String? email,
    String? upiId,
    bool? gstEnabled,
    String? gstin,
    String? stateCode,
    String? prefix,
    int? dueDays,
    double? defaultGstRate,
    String? terms,
    DateTime? updatedAt,
  }) =>
      InvoiceProfile(
        businessName: businessName ?? this.businessName,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        upiId: upiId ?? this.upiId,
        gstEnabled: gstEnabled ?? this.gstEnabled,
        gstin: gstin ?? this.gstin,
        stateCode: stateCode ?? this.stateCode,
        prefix: prefix ?? this.prefix,
        dueDays: dueDays ?? this.dueDays,
        defaultGstRate: defaultGstRate ?? this.defaultGstRate,
        terms: terms ?? this.terms,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'businessName': businessName,
        'address': address,
        'phone': phone,
        'email': email,
        'upiId': upiId,
        'gstEnabled': gstEnabled,
        'gstin': gstin,
        'stateCode': stateCode,
        'prefix': prefix,
        'dueDays': dueDays,
        'defaultGstRate': defaultGstRate,
        'terms': terms,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory InvoiceProfile.fromMap(Map<String, dynamic> m) => InvoiceProfile(
        businessName: m['businessName'] as String? ?? '',
        address: m['address'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        upiId: m['upiId'] as String? ?? '',
        gstEnabled: m['gstEnabled'] == true || m['gstEnabled'] == 1,
        gstin: m['gstin'] as String? ?? '',
        stateCode: m['stateCode'] as String? ?? '',
        prefix: m['prefix'] as String? ?? 'INV',
        dueDays: (m['dueDays'] as num?)?.toInt() ?? 15,
        defaultGstRate: (m['defaultGstRate'] as num?)?.toDouble() ?? 18,
        terms: m['terms'] as String? ?? '',
        updatedAt: m['updatedAt'] == null
            ? null
            : DateTime.parse(m['updatedAt'] as String),
      );
}
