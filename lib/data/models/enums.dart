/// Domain enums for type-safe transaction modeling.
///
/// These replace stringly-typed values ('income', 'expense', 'UPI', etc.)
/// throughout the codebase, providing compile-time safety against typos.
library;

/// Transaction type — income received or expense paid.
enum TransactionType {
  income,
  expense;

  /// Serialize to string for SQLite/Firestore storage.
  String toJson() => name;

  /// User-facing display name.
  String get displayName => switch (this) {
    TransactionType.income => 'Income',
    TransactionType.expense => 'Expense',
  };

  /// Deserialize from string, defaulting to [expense].
  static TransactionType fromJson(String? value) {
    if (value == 'income') return TransactionType.income;
    return TransactionType.expense;
  }
}

/// Payment method for a transaction.
enum PaymentMethod {
  upi('UPI'),
  creditCard('Credit Card'),
  debitCard('Debit Card'),
  cash('Cash'),
  bankTransfer('Bank Transfer'),
  netBanking('Net Banking'),
  paypal('PayPal'),
  wallet('Wallet');

  /// Human-readable display name (matches legacy string values in the DB).
  final String displayName;
  const PaymentMethod(this.displayName);

  /// Serialize to the display name for backward-compatible storage.
  String toJson() => displayName;

  /// Deserialize from the stored display name, defaulting to [upi].
  static PaymentMethod fromJson(String? value) {
    if (value == null || value.isEmpty) return PaymentMethod.upi;
    return PaymentMethod.values.firstWhere(
      (e) => e.displayName == value,
      orElse: () => PaymentMethod.upi,
    );
  }

  /// All values as their display names — used for UI dropdowns.
  static List<String> get displayNames =>
      values.map((e) => e.displayName).toList();
}

/// Source that created a transaction entry.
enum TransactionSource {
  manual,
  sms,
  notification;

  /// Serialize to string.
  String toJson() => name;

  /// User-facing display name.
  String get displayName => switch (this) {
    TransactionSource.manual => 'Manual',
    TransactionSource.sms => 'SMS',
    TransactionSource.notification => 'Notification',
  };

  /// Deserialize from string, defaulting to [manual].
  static TransactionSource fromJson(String? value) {
    if (value == 'sms') return TransactionSource.sms;
    if (value == 'notification') return TransactionSource.notification;
    return TransactionSource.manual;
  }
}

/// Recurring frequency for scheduled/repeating transactions and bills.
enum RecurringFrequency {
  daily,
  weekly,
  monthly,
  quarterly,
  semiannual,
  yearly;

  /// Serialize to string.
  String toJson() => name;

  /// User-facing display name.
  String get displayName => switch (this) {
    RecurringFrequency.daily => 'Daily',
    RecurringFrequency.weekly => 'Weekly',
    RecurringFrequency.monthly => 'Monthly',
    RecurringFrequency.quarterly => 'Every 3 months',
    RecurringFrequency.semiannual => 'Every 6 months',
    RecurringFrequency.yearly => 'Yearly',
  };

  /// Deserialize from string, returning null if input is null.
  static RecurringFrequency? fromJson(String? value) {
    if (value == null) return null;
    final normalized = value.toLowerCase().trim();
    if (normalized == 'every 3 months' || normalized == '3months') return RecurringFrequency.quarterly;
    if (normalized == 'every 6 months' || normalized == '6months') return RecurringFrequency.semiannual;
    return RecurringFrequency.values.firstWhere(
      (e) => e.name == normalized,
      orElse: () => RecurringFrequency.monthly,
    );
  }
}

/// Lifecycle status for recurring financial commitments / bills.
enum RecurringStatus {
  detected,
  confirmed,
  cancelled;

  /// Serialize to string.
  String toJson() => name;

  /// User-facing display name.
  String get displayName => switch (this) {
    RecurringStatus.detected => 'Detected',
    RecurringStatus.confirmed => 'Confirmed',
    RecurringStatus.cancelled => 'Cancelled',
  };

  /// Deserialize from string, defaulting to [confirmed].
  static RecurringStatus fromJson(String? value) {
    if (value == 'detected') return RecurringStatus.detected;
    if (value == 'cancelled') return RecurringStatus.cancelled;
    return RecurringStatus.confirmed;
  }
}

