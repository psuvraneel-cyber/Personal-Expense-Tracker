import 'dart:async';
import 'package:pet/core/utils/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/services/premium_entitlement_service.dart';

enum DeletionStep {
  deletingCloudTransactions,
  deletingCloudBudgets,
  deletingCloudCategories,
  deletingCloudTombstones,
  deletingCloudPremiumData,
  deletingUserProfile,
  deletingAuthAccount,
  clearingLocalData,
  clearingPreferences,
  complete,
}

class AccountDeletionService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DatabaseHelper _dbHelper;

  static bool isDeletionInProgress = false;
  bool isTesting = false;

  AccountDeletionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required DatabaseHelper dbHelper,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _dbHelper = dbHelper;

  /// Stream of deletion progress for UI display
  final _progressController = StreamController<DeletionStep>.broadcast();
  Stream<DeletionStep> get progress => _progressController.stream;

  /// Re-authenticate the user before deletion (security requirement)
  Future<bool> reAuthenticate(AuthCredential credential) async {
    try {
      await _auth.currentUser?.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      AppLogger.debug('[AccountDeletion] Re-auth failed: ${e.code}');
      return false;
    }
  }

  /// Execute the full account deletion sequence.
  /// Must be called AFTER successful re-authentication.
  Future<void> deleteAccount({required String targetUid}) async {
    final user = _auth.currentUser;

    // Resumable deletion: if user is already deleted from Firebase Auth,
    // skip directly to local cleanup.
    if (user == null) {
      if (isDeletionInProgress) {
        AppLogger.debug('[AccountDeletion] User is null but deletion is in progress — running local cleanup');
        await _runLocalCleanup(targetUid);
        return;
      } else {
        throw StateError('No authenticated user');
      }
    }

    final uid = user.uid;
    if (uid != targetUid) {
      throw StateError('UID mismatch: expected $targetUid but got $uid');
    }

    // Set deletion progress state
    isDeletionInProgress = true;
    if (!isTesting) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('deletion_in_progress', true);
    }

    try {
      // ── Step 1: Delete Firestore transactions
      _progressController.add(DeletionStep.deletingCloudTransactions);
      await _deleteFirestoreCollection(uid, 'transactions');

      // ── Step 2: Delete Firestore budgets
      _progressController.add(DeletionStep.deletingCloudBudgets);
      await _deleteFirestoreCollection(uid, 'budgets');

      // ── Step 3: Delete Firestore categories
      _progressController.add(DeletionStep.deletingCloudCategories);
      await _deleteFirestoreCollection(uid, 'categories');

      // ── Step 4: Delete Firestore tombstones
      _progressController.add(DeletionStep.deletingCloudTombstones);
      await _deleteFirestoreCollection(uid, 'tombstones');

      // ── Step 5: Delete premium and recurring data collections
      _progressController.add(DeletionStep.deletingCloudPremiumData);
      for (final collection in [
        'saving_goals',
        'recurring_payments',
        'recurring_rules',
        'recurring_occurrences',
        'alerts',
        'family_members',
        'linked_accounts',
        'tax_categories',
      ]) {
        await _deleteFirestoreCollection(uid, collection);
      }

      // ── Step 6: Delete user profile document
      _progressController.add(DeletionStep.deletingUserProfile);
      await _firestore.collection('users').doc(uid).delete();

      // ── Step 7: Delete Firebase Auth account
      // This MUST come after all Firestore operations, because after deletion
      // the user will no longer be authenticated and cannot access Firestore.
      _progressController.add(DeletionStep.deletingAuthAccount);
      await user.delete();

      // ── Run Local Cleanup Steps
      await _runLocalCleanup(uid);
    } catch (e, stack) {
      if (!_progressController.isClosed) {
        _progressController.addError(e, stack);
      }
      AppLogger.debug('[AccountDeletion] FAILED: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _runLocalCleanup(String uid) async {
    // ── Step 8: Clear local SQLite data (scoped queue actions)
    _progressController.add(DeletionStep.clearingLocalData);
    try {
      await _clearLocalDatabase(uid);
    } catch (e) {
      AppLogger.debug('[AccountDeletion] Local SQLite cleanup failed: $e');
    }

    // ── Step 9: Clear SharedPreferences
    _progressController.add(DeletionStep.clearingPreferences);
    AppLogger.debug('[AccountDeletion] calling _clearPreferences');
    try {
      await _clearPreferences();
      AppLogger.debug('[AccountDeletion] _clearPreferences returned');
    } catch (e) {
      AppLogger.debug('[AccountDeletion] Local SharedPreferences cleanup failed: $e');
    }

    // ── Step 10: RevenueCat logout
    AppLogger.debug('[AccountDeletion] Step 10: isTesting = $isTesting');
    if (!isTesting) {
      try {
        await PremiumEntitlementService.logOut();
      } catch (e) {
        AppLogger.debug('[AccountDeletion] RevenueCat logout failed: $e');
      }
    }

    // Set deletion-in-progress to false
    isDeletionInProgress = false;
    AppLogger.debug('[AccountDeletion] Resetting progress state: isTesting = $isTesting');
    if (!isTesting) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('deletion_in_progress', false);
      } catch (e) {
        AppLogger.debug('[AccountDeletion] Resetting deletion_in_progress failed: $e');
      }
    }

    AppLogger.debug('[AccountDeletion] Step complete!');
    _progressController.add(DeletionStep.complete);
  }

  /// Delete all documents in a Firestore subcollection in batches of 500
  Future<void> _deleteFirestoreCollection(String uid, String collection) async {
    const batchSize = 500;
    final ref = _firestore.collection('users').doc(uid).collection(collection);

    QuerySnapshot snapshot;
    do {
      snapshot = await ref.limit(batchSize).get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      AppLogger.debug(
        '[AccountDeletion] Deleted ${snapshot.docs.length} docs from $collection',
      );
    } while (snapshot.docs.length == batchSize);
  }

  /// Wipe all user data from every SQLite table
  Future<void> _clearLocalDatabase(String uid) async {
    final db = await _dbHelper.database;

    // Tables to wipe — ordered to respect foreign key constraints
    const tablesToClear = [
      'user_feedback',
      'unknown_format_logs',
      'classification_rules',
      'sms_transactions',
      'sms_processing_state',
      'tax_categories',
      'linked_accounts',
      'family_members',
      'alerts',
      'recurring_payments',
      'recurring_occurrences',
      'recurring_rules',
      'saving_goals',
      'transactions',
      'budgets',
      'categories',
      'ce', // event log table
    ];

    await db.transaction((txn) async {
      // Scoped deletion: only clear queue entries belonging to this UID
      try {
        await txn.delete('transaction_sync_queue', where: 'userId = ?', whereArgs: [uid]);
        AppLogger.debug('[AccountDeletion] Scoped transaction_sync_queue cleared for $uid');
      } catch (e) {
        AppLogger.debug('[AccountDeletion] Could not clear sync queue: $e');
      }

      for (final table in tablesToClear) {
        try {
          await txn.delete(table);
          AppLogger.debug('[AccountDeletion] Cleared table: $table');
        } catch (e) {
          // Table may not exist in older schema versions — continue
          AppLogger.debug('[AccountDeletion] Could not clear $table: $e');
        }
      }
    });
  }

  /// Clear all SharedPreferences
  Future<void> _clearPreferences() async {
    AppLogger.debug('[AccountDeletion] _clearPreferences entered, isTesting=$isTesting');
    if (isTesting) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  void dispose() {
    if (!_progressController.isClosed) {
      _progressController.close();
    }
  }
}
