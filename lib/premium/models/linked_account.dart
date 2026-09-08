class LinkedAccount {
  final String id;
  final String provider; // sms, notification, mock
  final String accountName;
  final String accountType; // bank, wallet, card
  final DateTime? lastSyncedAt;
  final String status; // active, paused
  final String? bankName;
  final String? accountTail;
  final double? lastObservedBalance;
  final DateTime? lastObservedAt;

  LinkedAccount({
    required this.id,
    required this.provider,
    required this.accountName,
    required this.accountType,
    this.lastSyncedAt,
    this.status = 'active',
    this.bankName,
    this.accountTail,
    this.lastObservedBalance,
    this.lastObservedAt,
  });

  LinkedAccount copyWith({
    String? id,
    String? provider,
    String? accountName,
    String? accountType,
    DateTime? lastSyncedAt,
    String? status,
    String? bankName,
    String? accountTail,
    double? lastObservedBalance,
    DateTime? lastObservedAt,
  }) {
    return LinkedAccount(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      accountName: accountName ?? this.accountName,
      accountType: accountType ?? this.accountType,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      status: status ?? this.status,
      bankName: bankName ?? this.bankName,
      accountTail: accountTail ?? this.accountTail,
      lastObservedBalance: lastObservedBalance ?? this.lastObservedBalance,
      lastObservedAt: lastObservedAt ?? this.lastObservedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'provider': provider,
      'accountName': accountName,
      'accountType': accountType,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'status': status,
      'bankName': bankName,
      'accountTail': accountTail,
      'lastObservedBalance': lastObservedBalance,
      'lastObservedAt': lastObservedAt?.toIso8601String(),
    };
  }

  factory LinkedAccount.fromMap(Map<String, dynamic> map) {
    return LinkedAccount(
      id: map['id'] as String,
      provider: map['provider'] as String,
      accountName: map['accountName'] as String,
      accountType: map['accountType'] as String,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.parse(map['lastSyncedAt'] as String)
          : null,
      status: map['status'] as String? ?? 'active',
      bankName: map['bankName'] as String?,
      accountTail: map['accountTail'] as String?,
      lastObservedBalance: (map['lastObservedBalance'] as num?)?.toDouble(),
      lastObservedAt: map['lastObservedAt'] != null
          ? DateTime.parse(map['lastObservedAt'] as String)
          : null,
    );
  }
}
