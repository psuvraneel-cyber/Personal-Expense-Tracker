import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/services/secure_storage_service.dart';

/// A bank balance the user entered, and when.
class BalanceAnchor {
  const BalanceAnchor({required this.amount, required this.asOf});

  /// Total across the user's accounts at [asOf], in rupees.
  final double amount;
  final DateTime asOf;
}

/// The starting point for cash-flow forecasts.
///
/// The app only knows the income and spending it has tracked, not what is
/// in the user's bank, so forecasts (and the cash-flow alerts and AI
/// answers built on them) need a balance the user entered. Without one,
/// they say the balance is unknown instead of guessing.
///
/// Stored in encrypted secure storage and removed on sign-out.
class BalanceAnchorService {
  BalanceAnchorService._();

  static const kAmountKey = 'cashflowBalanceAmount';
  static const kAsOfKey = 'cashflowBalanceAsOf';

  /// The entered balance, or null if none (listen to rebuild screens).
  static final ValueNotifier<BalanceAnchor?> current =
      ValueNotifier<BalanceAnchor?>(null);
  static bool _loaded = false;

  static Future<BalanceAnchor?> load() async {
    try {
      final amount = double.tryParse(
          await SecureStorageService.instance.read(kAmountKey) ?? '');
      final asOf = DateTime.tryParse(
          await SecureStorageService.instance.read(kAsOfKey) ?? '');
      current.value = amount == null || asOf == null || !amount.isFinite
          ? null
          : BalanceAnchor(amount: amount, asOf: asOf);
    } catch (e) {
      AppLogger.debug('[BalanceAnchor] load failed: $e');
    }
    _loaded = true;
    return current.value;
  }

  static Future<void> save(double amount, {DateTime? asOf}) async {
    final anchor = BalanceAnchor(amount: amount, asOf: asOf ?? DateTime.now());
    current.value = anchor;
    _loaded = true;
    await SecureStorageService.instance.write(kAmountKey, '$amount');
    await SecureStorageService.instance
        .write(kAsOfKey, anchor.asOf.toIso8601String());
  }

  static Future<void> clear() async {
    current.value = null;
    _loaded = true;
    try {
      await SecureStorageService.instance.delete(kAmountKey);
      await SecureStorageService.instance.delete(kAsOfKey);
    } catch (_) {}
  }

  /// Balance at [now]: the entered balance plus tracked income and minus
  /// tracked spending dated after it was entered (and not in the future).
  static double openingBalance(
    BalanceAnchor anchor,
    Iterable<TransactionRecord> transactions,
    DateTime now,
  ) {
    var balance = anchor.amount;
    for (final t in transactions) {
      if (!t.date.isAfter(anchor.asOf) || t.date.isAfter(now)) continue;
      if (t.type == TransactionType.income) {
        balance += t.amount;
      } else if (t.type == TransactionType.expense) {
        balance -= t.amount;
      }
    }
    return balance;
  }

  /// [openingBalance] for the stored balance, or null if none was entered.
  static Future<double?> openingBalanceFor(
    Iterable<TransactionRecord> transactions, {
    DateTime? now,
  }) async {
    final anchor = _loaded ? current.value : await load();
    if (anchor == null) return null;
    return openingBalance(anchor, transactions, now ?? DateTime.now());
  }

  @visibleForTesting
  static void debugSet(BalanceAnchor? anchor) {
    current.value = anchor;
    _loaded = true;
  }

  @visibleForTesting
  static void debugReset() {
    current.value = null;
    _loaded = false;
  }
}
