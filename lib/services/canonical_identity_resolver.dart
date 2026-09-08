import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Strategy and engine for resolving stable, cross-source financial event identity.
///
/// Designed to link and deduplicate:
/// - Bank SMS
/// - UPI push notification (PhonePe, GPay, Paytm)
/// - Periodic inbox reconciliation scans
/// into a single canonical transaction identity.
///
/// Evidence hierarchy (strictly conservative to prevent false merges):
/// 1. Strong reference/transaction ID (UPI Ref, IMPS Ref, RRN, Txn ID) + amount + calendar day
/// 2. Account tail (last 3–6 digits) + amount + 15-minute time window
/// 3. UPI identifier (e.g. name@okhdfcbank) + amount + 15-minute time window
/// 4. Normalized merchant + amount + 15-minute time window
class CanonicalIdentityResolver {
  CanonicalIdentityResolver._();

  /// Time window duration for clustering notifications and SMS (15 minutes).
  /// Bank SMS delivery can lag push notifications by several minutes.
  static const Duration windowDuration = Duration(minutes: 15);

  /// Compute the 15-minute bucket index for a timestamp.
  static int computeTimeBucket(DateTime time) {
    final ms = time.millisecondsSinceEpoch;
    return ms ~/ windowDuration.inMilliseconds;
  }

  /// Generate a canonical event identity key string based on available evidence.
  static String generateIdentityKey({
    String? referenceId,
    String? accountTail,
    String? upiId,
    String? merchantName,
    required double amount,
    required DateTime timestamp,
  }) {
    final formattedAmount = amount.toStringAsFixed(2);

    // 1. Strong reference ID (Highest confidence)
    if (referenceId != null && referenceId.trim().isNotEmpty) {
      var cleanRef = referenceId.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      // Strip common reference prefixes like 'upi', 'imps', 'rrn', 'ref', 'txn' when followed by digits
      final prefixPattern = RegExp(r'^(?:upi|imps|rrn|ref|txn|neft|rtgs)(\d{6,})$');
      final match = prefixPattern.firstMatch(cleanRef);
      if (match != null) {
        cleanRef = match.group(1)!;
      }
      if (cleanRef.length >= 6) {
        final dateKey = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
        return 'ref:$cleanRef:$formattedAmount:$dateKey';
      }
    }

    final bucket = computeTimeBucket(timestamp);

    // 2. Account tail + amount + 15m window
    if (accountTail != null && accountTail.trim().isNotEmpty) {
      final cleanTail = accountTail.trim().replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanTail.length >= 3) {
        return 'acct:$cleanTail:$formattedAmount:$bucket';
      }
    }

    // 3. UPI ID + amount + 15m window
    if (upiId != null && upiId.trim().isNotEmpty) {
      final cleanUpi = upiId.trim().toLowerCase();
      if (cleanUpi.contains('@')) {
        return 'upi:$cleanUpi:$formattedAmount:$bucket';
      }
    }

    // 4. Normalized merchant + amount + 15m window
    final cleanMerchant = (merchantName ?? 'unknown')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return 'm:$cleanMerchant:$formattedAmount:$bucket';
  }

  /// Generates a deterministic SHA-256 fingerprint from the identity key.
  static String generateFingerprint({
    String? referenceId,
    String? accountTail,
    String? upiId,
    String? merchantName,
    required double amount,
    required DateTime timestamp,
  }) {
    final key = generateIdentityKey(
      referenceId: referenceId,
      accountTail: accountTail,
      upiId: upiId,
      merchantName: merchantName,
      amount: amount,
      timestamp: timestamp,
    );
    return sha256.convert(utf8.encode(key)).toString();
  }

  /// Determines whether two financial events represent the exact same real-world transaction.
  static bool areSameEvent({
    required double amount1,
    required DateTime time1,
    String? ref1,
    String? tail1,
    String? upi1,
    String? merchant1,
    required double amount2,
    required DateTime time2,
    String? ref2,
    String? tail2,
    String? upi2,
    String? merchant2,
  }) {
    // 1. Amounts must match within 0.01 tolerance
    if ((amount1 - amount2).abs() > 0.01) return false;

    // 2. If both have reference IDs, compare directly
    if (ref1 != null && ref2 != null && ref1.trim().isNotEmpty && ref2.trim().isNotEmpty) {
      var c1 = ref1.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      var c2 = ref2.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final prefixPattern = RegExp(r'^(?:upi|imps|rrn|ref|txn|neft|rtgs)(\d{6,})$');
      final m1 = prefixPattern.firstMatch(c1);
      if (m1 != null) c1 = m1.group(1)!;
      final m2 = prefixPattern.firstMatch(c2);
      if (m2 != null) c2 = m2.group(1)!;
      if (c1.length >= 6 && c2.length >= 6) {
        return c1 == c2;
      }
    }

    // 3. Time difference check (within 15 minutes)
    final diff = time1.difference(time2).abs();
    if (diff > windowDuration) return false;

    // 4. Account tail match
    if (tail1 != null && tail2 != null && tail1.trim().isNotEmpty && tail2.trim().isNotEmpty) {
      final t1 = tail1.trim().replaceAll(RegExp(r'[^0-9]'), '');
      final t2 = tail2.trim().replaceAll(RegExp(r'[^0-9]'), '');
      if (t1 == t2 && t1.length >= 3) return true;
    }

    // 5. UPI ID match
    if (upi1 != null && upi2 != null && upi1.trim().isNotEmpty && upi2.trim().isNotEmpty) {
      if (upi1.trim().toLowerCase() == upi2.trim().toLowerCase()) return true;
    }

    // 6. Merchant match with close timestamp (within 5 minutes)
    if (diff <= const Duration(minutes: 5)) {
      final m1 = (merchant1 ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final m2 = (merchant2 ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (m1.isNotEmpty && m2.isNotEmpty && m1 == m2 && m1 != 'unknown') {
        return true;
      }
    }

    return false;
  }
}
