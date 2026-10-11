import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/category_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';

/// A group of up to [Household.maxMembers] people sharing monthly budgets.
class Household {
  const Household({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.memberUids,
    required this.memberNames,
  });

  static const maxMembers = 6;

  final String id;
  final String name;
  final String ownerUid;
  final List<String> memberUids;
  final Map<String, String> memberNames;

  String nameOf(String uid) => memberNames[uid] ?? 'Member';

  factory Household.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Household(
      id: doc.id,
      name: d['name'] as String? ?? 'Household',
      ownerUid: d['ownerUid'] as String? ?? '',
      memberUids: List<String>.from(d['memberUids'] as List? ?? const []),
      memberNames: Map<String, String>.from(
          (d['memberNames'] as Map?)?.cast<String, String>() ?? const {}),
    );
  }
}

/// A shared monthly limit for one category.
class SharedBudget {
  const SharedBudget({
    required this.categoryId,
    required this.categoryName,
    required this.amount,
  });

  final String categoryId;
  final String categoryName;
  final double amount;
}

/// One member's spending per category for one month.
class MemberSpending {
  const MemberSpending({
    required this.uid,
    required this.byCategory,
    required this.names,
  });

  final String uid;
  final Map<String, double> byCategory;
  final Map<String, String> names;
}

/// Firestore access for shared household budgets (see firestore.rules).
///
/// Members share category budgets and see each other's monthly totals per
/// category — never individual transactions, merchants or notes.
class HouseholdService {
  HouseholdService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const inviteLength = 8;
  static const inviteValidity = Duration(days: 7);

  CollectionReference<Map<String, dynamic>> get _households =>
      _db.collection('households');

  static String monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);

  @visibleForTesting
  static String spendingDocId(String uid, DateTime month) =>
      '${uid}_${DateFormat('yyyyMM').format(month)}';

  static String newInviteCode([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(inviteLength,
        (_) => inviteAlphabet[r.nextInt(inviteAlphabet.length)]).join();
  }

  /// Normalises what someone typed; null if it can't be a code.
  static String? normaliseInviteCode(String raw) {
    final code = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return code.length == inviteLength ? code : null;
  }

  /// The household [uid] belongs to (at most one), live.
  Stream<Household?> watchMine(String uid) => _households
      .where('memberUids', arrayContains: uid)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : Household.fromDoc(s.docs.first));

  Future<Household?> findMine(String uid) async {
    final s = await _households
        .where('memberUids', arrayContains: uid)
        .limit(1)
        .get();
    return s.docs.isEmpty ? null : Household.fromDoc(s.docs.first);
  }

  Future<String> create({
    required String uid,
    required String displayName,
    required String name,
  }) async {
    final ref = _households.doc();
    await ref.set({
      'name': name.trim(),
      'ownerUid': uid,
      'memberUids': [uid],
      'memberNames': {uid: _clip(displayName)},
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> rename(String householdId, String name) =>
      _households.doc(householdId).update({'name': _clip(name)});

  Future<String> createInvite({
    required String householdId,
    required String uid,
  }) async {
    final code = newInviteCode();
    await _db.collection('householdInvites').doc(code).set({
      'householdId': householdId,
      'createdBy': uid,
      'expiresAt': Timestamp.fromDate(DateTime.now().add(inviteValidity)),
    });
    return code;
  }

  /// Joins the household behind [code]. Throws [HouseholdException] with a
  /// user-facing message when that isn't possible.
  Future<void> join({
    required String code,
    required String uid,
    required String displayName,
  }) async {
    final normalised = normaliseInviteCode(code);
    if (normalised == null) {
      throw const HouseholdException("That invite code isn't valid.");
    }
    if (await findMine(uid) != null) {
      throw const HouseholdException(
          'Leave your current household before joining another.');
    }
    final invite =
        await _db.collection('householdInvites').doc(normalised).get();
    final data = invite.data();
    final expires = (data?['expiresAt'] as Timestamp?)?.toDate();
    if (data == null || expires == null || expires.isBefore(DateTime.now())) {
      throw const HouseholdException(
          'That invite code has expired or does not exist.');
    }
    try {
      await _households.doc(data['householdId'] as String).update({
        'memberUids': FieldValue.arrayUnion([uid]),
        'memberNames.$uid': _clip(displayName),
        'lastInviteCode': normalised,
      });
    } on FirebaseException {
      throw const HouseholdException(
          "Couldn't join — the household may be full (6 people).");
    }
  }

  Future<void> leave(Household h, String uid) async {
    await deleteMySpending(h.id, uid);
    await _households.doc(h.id).update({
      'memberUids': FieldValue.arrayRemove([uid]),
      'memberNames.$uid': FieldValue.delete(),
    });
  }

  /// Owner only: removes [uid] and the totals they shared.
  Future<void> removeMember(Household h, String uid) async {
    await deleteMySpending(h.id, uid);
    await _households.doc(h.id).update({
      'memberUids': FieldValue.arrayRemove([uid]),
      'memberNames.$uid': FieldValue.delete(),
    });
  }

  /// Owner only: deletes budgets, everyone's totals and the household.
  Future<void> deleteHousehold(Household h) async {
    final ref = _households.doc(h.id);
    for (final sub in ['budgets', 'spending']) {
      final docs = await ref.collection(sub).get();
      for (final d in docs.docs) {
        await d.reference.delete();
      }
    }
    await ref.delete();
  }

  Stream<List<SharedBudget>> watchBudgets(String householdId) => _households
      .doc(householdId)
      .collection('budgets')
      .snapshots()
      .map((s) => s.docs
          .map((d) => SharedBudget(
                categoryId: d.id,
                categoryName: d.data()['categoryName'] as String? ?? d.id,
                amount: (d.data()['amount'] as num?)?.toDouble() ?? 0,
              ))
          .toList()
        ..sort((a, b) => a.categoryName.compareTo(b.categoryName)));

  Future<void> setBudget({
    required String householdId,
    required String uid,
    required String categoryId,
    required String categoryName,
    required double amount,
  }) =>
      _households.doc(householdId).collection('budgets').doc(categoryId).set({
        'categoryId': categoryId,
        'categoryName': _clip(categoryName),
        'amount': amount,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteBudget(String householdId, String categoryId) =>
      _households
          .doc(householdId)
          .collection('budgets')
          .doc(categoryId)
          .delete();

  Stream<List<MemberSpending>> watchSpending(
          String householdId, DateTime month) =>
      _households
          .doc(householdId)
          .collection('spending')
          .where('month', isEqualTo: monthKey(month))
          .snapshots()
          .map((s) => s.docs.map((d) {
                final data = d.data();
                return MemberSpending(
                  uid: data['uid'] as String? ?? '',
                  byCategory: {
                    for (final e
                        in (data['byCategory'] as Map? ?? const {}).entries)
                      '${e.key}': (e.value as num).toDouble(),
                  },
                  names: Map<String, String>.from(
                      (data['names'] as Map?)?.cast<String, String>() ??
                          const {}),
                );
              }).toList());

  /// Publishes [uid]'s category totals for [month] (expenses only).
  Future<void> publishSpending({
    required String householdId,
    required String uid,
    required DateTime month,
    required Map<String, double> byCategory,
    required Map<String, String> names,
  }) =>
      _households
          .doc(householdId)
          .collection('spending')
          .doc(spendingDocId(uid, month))
          .set({
        'uid': uid,
        'month': monthKey(month),
        'byCategory': byCategory,
        'names': {for (final e in names.entries) e.key: _clip(e.value)},
        'total': byCategory.values.fold(0.0, (a, b) => a + b),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Deletes [uid]'s shared totals (their own, or any as the owner).
  Future<void> deleteMySpending(String householdId, String uid) async {
    final docs = await _households
        .doc(householdId)
        .collection('spending')
        .where('uid', isEqualTo: uid)
        .get();
    for (final d in docs.docs) {
      await d.reference.delete();
    }
  }

  /// Account deletion: leaves (or, as owner, deletes) every household and
  /// removes the user's invite codes.
  Future<void> removeUserEverywhere(String uid) async {
    final mine =
        await _households.where('memberUids', arrayContains: uid).get();
    for (final doc in mine.docs) {
      final h = Household.fromDoc(doc);
      if (h.ownerUid == uid) {
        await deleteHousehold(h);
      } else {
        await leave(h, uid);
      }
    }
    final invites = await _db
        .collection('householdInvites')
        .where('createdBy', isEqualTo: uid)
        .get();
    for (final d in invites.docs) {
      await d.reference.delete();
    }
  }

  static String _clip(String s) {
    final t = s.trim();
    return t.length <= 40 ? t : t.substring(0, 40);
  }
}

class HouseholdException implements Exception {
  const HouseholdException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keeps the signed-in user's monthly category totals published to their
/// household, if they're in one.
class HouseholdSync {
  HouseholdSync._();

  static String? _lastPublished;
  static String? _householdId;
  static DateTime? _householdCheckedAt;

  /// Expense totals per category id.
  @visibleForTesting
  static Map<String, double> categoryTotals(Iterable<TransactionRecord> txns) {
    final totals = <String, double>{};
    for (final t in txns) {
      if (t.type != TransactionType.expense) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? 0) + t.amount;
    }
    return totals;
  }

  static Future<void> publishMine() async {
    try {
      if (Firebase.apps.isEmpty) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return;
      final service = HouseholdService();

      // Re-check membership at most every 10 minutes.
      final now = DateTime.now();
      if (_householdCheckedAt == null ||
          now.difference(_householdCheckedAt!) > const Duration(minutes: 10)) {
        _householdId = (await service.findMine(user.uid))?.id;
        _householdCheckedAt = now;
      }
      final hid = _householdId;
      if (hid == null) return;

      final txns = await TransactionRepository()
          .getTransactionsByMonth(now.month, now.year);
      final totals = categoryTotals(txns);
      final names = {
        for (final c in await CategoryRepository().getAllCategories())
          if (totals.containsKey(c.id)) c.id: c.name,
      };
      final signature =
          '$hid|${HouseholdService.monthKey(now)}|${jsonEncode(totals)}';
      if (signature == _lastPublished) return;
      await service.publishSpending(
        householdId: hid,
        uid: user.uid,
        month: now,
        byCategory: totals,
        names: names,
      );
      _lastPublished = signature;
    } catch (e) {
      AppLogger.debug('[Household] publish failed: $e');
    }
  }

  /// Forget cached membership (after joining, leaving or signing out).
  static void reset() {
    _lastPublished = null;
    _householdId = null;
    _householdCheckedAt = null;
  }
}
