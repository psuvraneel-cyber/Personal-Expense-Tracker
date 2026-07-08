import 'dart:async';
import 'package:pet/core/utils/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/data/database/database_helper.dart';

enum DeletionStep {
  clearingLocalData,
  deletingCloudTransactions,
  deletingCloudBudgets,
  deletingCloudCategories,
  deletingCloudPremiumData,
  deletingUserProfile,
  deletingAuthAccount,
  clearingPreferences,
  complete,
}

class AccountDeletionService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DatabaseHelper _dbHelper;

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
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No authenticated user');

    final uid = user.uid;

    try {
      // ── Step 1: Clear local SQLite data
      _progressController.add(DeletionStep.clearingLocalData);
      await _clearLocalDatabase();

      // ── Step 2: Delete Firestore transactions
      _progressController.add(DeletionStep.deletingCloudTransactions);
      await _deleteFirestoreCollection(uid, 'transactions');

      // ── Step 3: Delete Firestore budgets
      _progressController.add(DeletionStep.deletingCloudBudgets);
      await _deleteFirestoreCollection(uid, 'budgets');

      // ── Step 4: Delete Firestore categories
      _progressController.add(DeletionStep.deletingCloudCategories);
      await _deleteFirestoreCollection(uid, 'categories');

      // ── Step 5: Delete premium data collections
      _progressController.add(DeletionStep.deletingCloudPremiumData);
      for (final collection in [
        'saving_goals',
        'recurring_payments',
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

      // ── Step 8: Clear SharedPreferences
      _progressController.add(DeletionStep.clearingPreferences);
      await _clearPreferences();

      _progressController.add(DeletionStep.complete);
    } catch (e, stack) {
      if (!_progressController.isClosed) {
        _progressController.addError(e, stack);
      }
      AppLogger.debug('[AccountDeletion] FAILED: $e\n$stack');
      rethrow;
    }
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
  Future<void> _clearLocalDatabase() async {
    final db = await _dbHelper.database;

    // Tables to wipe — ordered to respect foreign key constraints
    const tablesToClear = [
      'user_feedback',
      'unknown_format_logs',
      'classification_rules',
      'sms_transactions',
      'tax_categories',
      'linked_accounts',
      'family_members',
      'alerts',
      'recurring_payments',
      'saving_goals',
      'transactions',
      'budgets',
      'categories',
      'ce', // event log table
    ];

    await db.transaction((txn) async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  void dispose() {
    if (!_progressController.isClosed) {
      _progressController.close();
    }
  }
}
