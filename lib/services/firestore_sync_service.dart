import 'dart:async';
import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/models/category.dart' as cat_model;
import 'package:pet/data/models/budget.dart';
import 'package:pet/data/models/recurring_occurrence.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/recurring_payment_history.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/models/weekly_limit.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/models/account_session.dart';
import 'package:pet/services/firebase_auth_service.dart';

/// Firestore sync service for transactions, categories, and budgets.
///
/// Follows an offline-first approach:
///   1. Writes go to SQLite immediately (handled by the provider).
///   2. This service mirrors those writes to Firestore.
///   3. A real-time listener propagates remote changes back to the provider.
///
/// Firestore path:  users/{uid}/transactions/{transactionId}
///                  users/{uid}/categories/{categoryId}
///                  users/{uid}/budgets/{budgetId}
class FirestoreSyncService {
  static final FirestoreSyncService _instance =
      FirestoreSyncService._internal();

  FirebaseFirestore? _customDb;
  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;

  @visibleForTesting
  set firestore(FirebaseFirestore db) => _customDb = db;

  final FirebaseAuthService _auth = FirebaseAuthService();

  factory FirestoreSyncService() => _instance;

  FirestoreSyncService._internal() {
    // Enable Firestore offline persistence (enabled by default on Android/iOS;
    // must be explicitly set for Web). Using the new Settings API (replaces
    // deprecated enablePersistence() removed after v3.32.0).
    if (kIsWeb) {
      try {
        _db.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (_) {}
    }
  }

  // ── Auth Check & Session Isolation ──────────────────────────────────

  int _sessionGeneration = 0;
  String? _activeSessionUid;

  /// Current authentication session generation counter.
  /// Increments on logout or user switch to invalidate in-flight async sync callbacks.
  int get sessionGeneration => _sessionGeneration;

  /// Active session UID currently tracked by this sync service.
  String? get activeSessionUid {
    if (_activeSessionUid != null) return _activeSessionUid;
    try {
      return _auth.currentUserId;
    } catch (_) {
      return null;
    }
  }

  /// Current immutable account session token.
  AccountSession get currentSession => AccountSession(
    uid: activeSessionUid,
    generation: _sessionGeneration,
  );

  /// Safe accessor for current user ID, returning null instead of throwing StateError if logged out.
  String? get currentUserIdOrNull {
    try {
      final uid = _auth.currentUserId;
      if (uid == null || uid.isEmpty || uid == 'guest_user') return null;
      return uid;
    } catch (_) {
      return null;
    }
  }

  /// Invalidate all ongoing listeners and asynchronous operations from a prior user session.
  void onSessionChanged(String? newUid) {
    _sessionGeneration++;
    _activeSessionUid = newUid;
    CashflowForecastService.clearCache();
    AppLogger.info(
      'FirestoreSync session generation bumped to $_sessionGeneration for uid: $newUid',
      label: 'FirestoreSync',
    );
  }

  /// Whether the current user is authenticated.
  /// Callers should check this before attempting Firestore operations.
  bool get isAuthenticated {
    try {
      if (_auth.isLocalGuest || _auth.currentUser?.isAnonymous == true) return false;
      final uid = _auth.currentUserId;
      return uid != null && uid.isNotEmpty && uid != 'guest_user';
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  String get _uid {
    final uid = _auth.currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('FirestoreSyncService: user not authenticated');
    }
    return uid;
  }

  String get currentUserId => _uid;

  CollectionReference<Map<String, dynamic>> get _txnCollection =>
      _db.collection('users').doc(_uid).collection('transactions');

  CollectionReference<Map<String, dynamic>> get _catCollection =>
      _db.collection('users').doc(_uid).collection('categories');

  CollectionReference<Map<String, dynamic>> get _budgetCollection =>
      _db.collection('users').doc(_uid).collection('budgets');

  CollectionReference<Map<String, dynamic>> get _recurringRulesCollection =>
      _db.collection('users').doc(_uid).collection('recurring_rules');

  CollectionReference<Map<String, dynamic>> get _recurringOccurrencesCollection =>
      _db.collection('users').doc(_uid).collection('recurring_occurrences');

  CollectionReference<Map<String, dynamic>> get _savingGoalsCollection =>
      _db.collection('users').doc(_uid).collection('saving_goals');

  CollectionReference<Map<String, dynamic>> get _recurringPaymentsCollection =>
      _db.collection('users').doc(_uid).collection('recurring_payments');

  CollectionReference<Map<String, dynamic>> get _recurringPaymentHistoryCollection =>
      _db.collection('users').doc(_uid).collection('recurring_payment_history');

  CollectionReference<Map<String, dynamic>> get _alertsCollection =>
      _db.collection('users').doc(_uid).collection('alerts');

  CollectionReference<Map<String, dynamic>> get _weeklyLimitsCollection =>
      _db.collection('users').doc(_uid).collection('weekly_limits');

  // ── Transaction Write Operations ─────────────────────────────────────

  /// Create or update a transaction in Firestore.
  Future<void> upsertTransaction(TransactionRecord transaction) async {
    try {
      await _txnCollection
          .doc(transaction.id)
          .set(transaction.toFirestore(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertTransaction error: ${e.message}');
      rethrow;
    }
  }

  /// Delete a transaction from Firestore.
  Future<void> deleteTransaction(String transactionId) async {
    try {
      await _txnCollection.doc(transactionId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteTransaction error: ${e.message}');
      rethrow;
    }
  }

  /// Batch-upload a list of transactions (used for initial data migration).
  Future<void> batchUpsert(List<TransactionRecord> transactions) async {
    const chunkSize = 400; // Firestore batch limit is 500
    for (int i = 0; i < transactions.length; i += chunkSize) {
      final chunk = transactions.skip(i).take(chunkSize);
      final batch = _db.batch();
      for (final txn in chunk) {
        batch.set(
          _txnCollection.doc(txn.id),
          txn.toFirestore(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  // ── Transaction Read / Stream Operations ─────────────────────────────

  /// Real-time stream of transactions for the current user.
  ///
  /// For real-time UI streaming, [limit] controls the maximum doc snapshot limit
  /// (defaults to 1000). Pass null or a higher value for uncapped stream length.
  Stream<List<TransactionRecord>> transactionsStream({int? limit = 1000}) {
    if (_auth.currentUserId == null) return Stream.value([]);

    var query = _txnCollection.orderBy('date', descending: true);
    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }

    return query.snapshots().map(_docsToTransactions).handleError((Object e) {
      AppLogger.debug('[Firestore] transactionsStream error: $e');
      return <TransactionRecord>[];
    });
  }

  /// One-time fetch of ALL transactions for the current user using cursor-based pagination.
  ///
  /// Uses Firestore `startAfterDocument()` pagination in pages of [batchSize] (default 1000)
  /// until all records are retrieved, eliminating silent truncation for users with >1,000 records.
  Future<List<TransactionRecord>> fetchAllTransactions({
    int batchSize = 1000,
  }) async {
    if (_auth.currentUserId == null) {
      AppLogger.debug(
        '[Firestore] fetchAllTransactions: user not authenticated',
      );
      return [];
    }
    final allTxns = <TransactionRecord>[];
    DocumentSnapshot? lastDoc;

    try {
      while (true) {
        var query = _txnCollection
            .orderBy('date', descending: true)
            .limit(batchSize);

        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snap = await query.get();
        if (snap.docs.isEmpty) break;

        allTxns.addAll(_docsToTransactions(snap));
        AppLogger.debug(
          '[Firestore] fetchAllTransactions page: got ${snap.docs.length} docs (total: ${allTxns.length})',
        );

        if (snap.docs.length < batchSize) break; // Reached last page
        lastDoc = snap.docs.last;
      }
      return allTxns;
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] fetchAllTransactions error: ${e.message}');
      return allTxns;
    } catch (e) {
      AppLogger.debug('[Firestore] fetchAllTransactions unexpected error: $e');
      return allTxns;
    }
  }

  // ── Category Operations ───────────────────────────────────────────────

  /// Upsert a custom category to Firestore.
  Future<void> upsertCategory(cat_model.Category category) async {
    if (!category.isCustom) return; // only sync custom categories
    try {
      await _catCollection.doc(category.id).set({
        'id': category.id,
        'name': category.name,
        'iconCodePoint': category.icon.codePoint,
        'iconFontFamily': category.icon.fontFamily,
        'colorValue': category.color.toARGB32(),
        'isCustom': true,
        'type': category.type,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertCategory error: ${e.message}');
    }
  }

  /// Delete a custom category from Firestore.
  Future<void> deleteCategory(String categoryId) async {
    try {
      await _catCollection.doc(categoryId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteCategory error: ${e.message}');
    }
  }

  /// Real-time stream of custom categories for the current user.
  Stream<List<cat_model.Category>> categoriesStream() {
    if (_auth.currentUserId == null) return Stream.value([]);

    return _catCollection
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) {
                try {
                  final data = doc.data();
                  return cat_model.Category(
                    id: data['id'] as String,
                    name: data['name'] as String,
                    icon: cat_model.CategoryIconHelper.fromCodePoint(
                      data['iconCodePoint'] as int?,
                    ),
                    color: Color(data['colorValue'] as int),
                    isCustom: data['isCustom'] as bool? ?? true,
                    type: data['type'] as String? ?? 'expense',
                  );
                } catch (e) {
                  AppLogger.debug(
                    '[Firestore] Failed to parse category ${doc.id}: $e',
                  );
                  return null;
                }
              })
              .whereType<cat_model.Category>()
              .toList(),
        )
        .handleError((Object e) {
          AppLogger.debug('[Firestore] categoriesStream error: $e');
          return <cat_model.Category>[];
        });
  }

  // ── Budget Operations ─────────────────────────────────────────────────

  /// Upsert a budget to Firestore.
  Future<void> upsertBudget(Budget budget) async {
    try {
      await _budgetCollection.doc(budget.id).set({
        'id': budget.id,
        'categoryId': budget.categoryId,
        'amount': budget.amount,
        'month': budget.month,
        'year': budget.year,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertBudget error: ${e.message}');
    }
  }

  /// Delete a budget from Firestore.
  Future<void> deleteBudget(String budgetId) async {
    try {
      await _budgetCollection.doc(budgetId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteBudget error: ${e.message}');
    }
  }

  /// Real-time stream of budgets for the current user for a given month/year.
  Stream<List<Budget>> budgetsStream(int month, int year) {
    if (_auth.currentUserId == null) return Stream.value([]);

    return _budgetCollection
        .where('month', isEqualTo: month)
        .where('year', isEqualTo: year)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) {
                try {
                  return Budget.fromMap(doc.data());
                } catch (e) {
                  AppLogger.debug(
                    '[Firestore] Failed to parse budget ${doc.id}: $e',
                  );
                  return null;
                }
              })
              .whereType<Budget>()
              .toList(),
        )
        .handleError((Object e) {
          AppLogger.debug('[Firestore] budgetsStream error: $e');
          return <Budget>[];
        });
  }

  // ── User Profile ─────────────────────────────────────────────────────

  /// Ensure the user document exists / is up-to-date on first sign-in.
  Future<void> ensureUserProfile({
    required String displayName,
    required String email,
  }) async {
    try {
      await _db.collection('users').doc(_uid).set({
        'displayName': displayName,
        'email': email,
        'lastSyncTime': FieldValue.serverTimestamp(),
        'syncVersion': 1,
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] ensureUserProfile error: ${e.message}');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  List<TransactionRecord> _docsToTransactions(QuerySnapshot snap) {
    return snap.docs
        .map((doc) {
          try {
            return TransactionRecord.fromFirestore(
              doc.id,
              doc.data() as Map<String, dynamic>,
            );
          } catch (e) {
            AppLogger.debug('[Firestore] Failed to parse doc ${doc.id}: $e');
            return null;
          }
        })
        .whereType<TransactionRecord>()
        .toList();
  }

  CollectionReference<Map<String, dynamic>> get _tombstoneCollection =>
      _db.collection('users').doc(_uid).collection('tombstones');

  Future<void> createTombstone(String transactionId) async {
    try {
      await _tombstoneCollection.doc(transactionId).set({
        'id': transactionId,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] createTombstone error: ${e.message}');
      rethrow;
    }
  }

  Future<void> deleteTombstone(String transactionId) async {
    try {
      await _tombstoneCollection.doc(transactionId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteTombstone error: ${e.message}');
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> tombstonesStream() {
    if (_auth.currentUserId == null) return Stream.value([]);
    return _tombstoneCollection
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()).toList())
        .handleError((Object e) {
          AppLogger.debug('[Firestore] tombstonesStream error: $e');
          return <Map<String, dynamic>>[];
        });
  }

  // ── Recurring Rules Sync ─────────────────────────────────────────────

  Future<void> upsertRecurringRule(RecurringRule rule) async {
    try {
      await _recurringRulesCollection
          .doc(rule.id)
          .set(rule.toFirestore(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertRecurringRule error: ${e.message}');
      rethrow;
    }
  }

  Future<void> deleteRecurringRule(String ruleId) async {
    try {
      await _recurringRulesCollection.doc(ruleId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteRecurringRule error: ${e.message}');
      rethrow;
    }
  }

  Stream<List<RecurringRule>> recurringRulesStream() {
    if (_auth.currentUserId == null) return Stream.value([]);
    return _recurringRulesCollection
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) {
                try {
                  return RecurringRule.fromFirestore(
                    doc.id,
                    doc.data(),
                  );
                } catch (e) {
                  AppLogger.debug('[Firestore] Failed to parse rule ${doc.id}: $e');
                  return null;
                }
              })
              .whereType<RecurringRule>()
              .toList();
        })
        .handleError((Object e) {
          AppLogger.debug('[Firestore] recurringRulesStream error: $e');
          return <RecurringRule>[];
        });
  }

  Future<List<RecurringRule>> fetchAllRecurringRules() async {
    if (_auth.currentUserId == null) return [];
    try {
      final snap = await _recurringRulesCollection.get();
      return snap.docs
          .map((doc) {
            try {
              return RecurringRule.fromFirestore(
                doc.id,
                doc.data(),
              );
            } catch (e) {
              AppLogger.debug('[Firestore] Failed to parse rule ${doc.id}: $e');
              return null;
            }
          })
          .whereType<RecurringRule>()
          .toList();
    } catch (e) {
      AppLogger.debug('[Firestore] fetchAllRecurringRules error: $e');
      return [];
    }
  }

  // ── Recurring Occurrences Sync ───────────────────────────────────────

  Future<void> upsertRecurringOccurrence(RecurringOccurrence occurrence) async {
    try {
      await _recurringOccurrencesCollection
          .doc(occurrence.id)
          .set(occurrence.toFirestore(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertRecurringOccurrence error: ${e.message}');
      rethrow;
    }
  }

  Future<void> deleteRecurringOccurrence(String occurrenceId) async {
    try {
      await _recurringOccurrencesCollection.doc(occurrenceId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteRecurringOccurrence error: ${e.message}');
      rethrow;
    }
  }

  Stream<List<RecurringOccurrence>> recurringOccurrencesStream() {
    if (_auth.currentUserId == null) return Stream.value([]);
    return _recurringOccurrencesCollection
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) {
                try {
                  return RecurringOccurrence.fromFirestore(
                    doc.id,
                    doc.data(),
                  );
                } catch (e) {
                  AppLogger.debug('[Firestore] Failed to parse occurrence ${doc.id}: $e');
                  return null;
                }
              })
              .whereType<RecurringOccurrence>()
              .toList();
        })
        .handleError((Object e) {
          AppLogger.debug('[Firestore] recurringOccurrencesStream error: $e');
          return <RecurringOccurrence>[];
        });
  }

  // ── Saving Goals Sync ────────────────────────────────────────────────

  Future<void> upsertSavingGoal(SavingGoal goal) async {
    try {
      await _savingGoalsCollection
          .doc(goal.id)
          .set(goal.toMap(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertSavingGoal error: ${e.message}');
    }
  }

  Future<void> deleteSavingGoal(String goalId) async {
    try {
      await _savingGoalsCollection.doc(goalId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteSavingGoal error: ${e.message}');
    }
  }

  Stream<List<SavingGoal>> savingGoalsStream() {
    if (_auth.currentUserId == null) return Stream.value([]);
    return _savingGoalsCollection
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) {
                try {
                  return SavingGoal.fromMap(doc.data());
                } catch (e) {
                  AppLogger.debug(
                    '[Firestore] Failed to parse saving goal ${doc.id}: $e',
                  );
                  return null;
                }
              })
              .whereType<SavingGoal>()
              .toList();
        })
        .handleError((Object e) {
          AppLogger.debug('[Firestore] savingGoalsStream error: $e');
          return <SavingGoal>[];
        });
  }

  Future<List<SavingGoal>> fetchAllSavingGoals() async {
    if (_auth.currentUserId == null) return [];
    try {
      final snap = await _savingGoalsCollection.get();
      return snap.docs
          .map((doc) {
            try {
              return SavingGoal.fromMap(doc.data());
            } catch (e) {
              AppLogger.debug(
                '[Firestore] Failed to parse saving goal ${doc.id}: $e',
              );
              return null;
            }
          })
          .whereType<SavingGoal>()
          .toList();
    } catch (e) {
      AppLogger.debug('[Firestore] fetchAllSavingGoals error: $e');
      return [];
    }
  }

  // ── Recurring Payments Sync ──────────────────────────────────────────

  Future<void> upsertRecurringPayment(RecurringPayment payment) async {
    try {
      await _recurringPaymentsCollection
          .doc(payment.id)
          .set(payment.toMap(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertRecurringPayment error: ${e.message}');
    }
  }

  Future<void> deleteRecurringPayment(String paymentId) async {
    try {
      await _recurringPaymentsCollection.doc(paymentId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteRecurringPayment error: ${e.message}');
    }
  }

  Stream<List<RecurringPayment>> recurringPaymentsStream() {
    if (_auth.currentUserId == null) return Stream.value([]);
    return _recurringPaymentsCollection
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) {
                try {
                  return RecurringPayment.fromMap(doc.data());
                } catch (e) {
                  AppLogger.debug(
                    '[Firestore] Failed to parse recurring payment ${doc.id}: $e',
                  );
                  return null;
                }
              })
              .whereType<RecurringPayment>()
              .toList();
        })
        .handleError((Object e) {
          AppLogger.debug('[Firestore] recurringPaymentsStream error: $e');
          return <RecurringPayment>[];
        });
  }

  Future<List<RecurringPayment>> fetchAllRecurringPayments() async {
    if (_auth.currentUserId == null) return [];
    try {
      final snap = await _recurringPaymentsCollection.get();
      return snap.docs
          .map((doc) {
            try {
              return RecurringPayment.fromMap(doc.data());
            } catch (e) {
              AppLogger.debug(
                '[Firestore] Failed to parse recurring payment ${doc.id}: $e',
              );
              return null;
            }
          })
          .whereType<RecurringPayment>()
          .toList();
    } catch (e) {
      AppLogger.debug('[Firestore] fetchAllRecurringPayments error: $e');
      return [];
    }
  }

  // ── Recurring Payment History Sync ───────────────────────────────────

  Future<void> upsertRecurringPaymentHistory(
    RecurringPaymentHistory history,
  ) async {
    try {
      await _recurringPaymentHistoryCollection
          .doc(history.id)
          .set(history.toMap(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug(
        '[Firestore] upsertRecurringPaymentHistory error: ${e.message}',
      );
    }
  }

  Future<void> deleteRecurringPaymentHistory(String historyId) async {
    try {
      await _recurringPaymentHistoryCollection.doc(historyId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug(
        '[Firestore] deleteRecurringPaymentHistory error: ${e.message}',
      );
    }
  }

  Future<List<RecurringPaymentHistory>> fetchAllRecurringPaymentHistory() async {
    if (_auth.currentUserId == null) return [];
    try {
      final snap = await _recurringPaymentHistoryCollection.get();
      return snap.docs
          .map((doc) {
            try {
              return RecurringPaymentHistory.fromMap(doc.data());
            } catch (e) {
              AppLogger.debug(
                '[Firestore] Failed to parse payment history ${doc.id}: $e',
              );
              return null;
            }
          })
          .whereType<RecurringPaymentHistory>()
          .toList();
    } catch (e) {
      AppLogger.debug('[Firestore] fetchAllRecurringPaymentHistory error: $e');
      return [];
    }
  }

  // ── Smart Alerts Sync ────────────────────────────────────────────────

  Future<void> upsertAlert(AppAlert alert) async {
    try {
      await _alertsCollection
          .doc(alert.id)
          .set(alert.toMap(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] upsertAlert error: ${e.message}');
    }
  }

  Future<void> deleteAlert(String alertId) async {
    try {
      await _alertsCollection.doc(alertId).delete();
    } on FirebaseException catch (e) {
      AppLogger.debug('[Firestore] deleteAlert error: ${e.message}');
    }
  }

  Stream<List<AppAlert>> alertsStream() {
    if (_auth.currentUserId == null) return Stream.value([]);
    return _alertsCollection
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) {
                try {
                  return AppAlert.fromMap(doc.data());
                } catch (e) {
                  AppLogger.debug(
                    '[Firestore] Failed to parse alert ${doc.id}: $e',
                  );
                  return null;
                }
              })
              .whereType<AppAlert>()
              .toList();
        })
        .handleError((Object e) {
          AppLogger.debug('[Firestore] alertsStream error: $e');
          return <AppAlert>[];
        });
  }

  Future<List<AppAlert>> fetchAllAlerts() async {
    if (_auth.currentUserId == null) return [];
    try {
      final snap = await _alertsCollection.get();
      return snap.docs
          .map((doc) {
            try {
              return AppAlert.fromMap(doc.data());
            } catch (e) {
              AppLogger.debug(
                '[Firestore] Failed to parse alert ${doc.id}: $e',
              );
              return null;
            }
          })
          .whereType<AppAlert>()
          .toList();
    } catch (e) {
      AppLogger.debug('[Firestore] fetchAllAlerts error: $e');
      return [];
    }
  }

  // ── Weekly Limits Write & Read Operations ────────────────────────────

  Future<void> upsertWeeklyLimit(WeeklyLimit limit) async {
    if (!isAuthenticated) return;
    try {
      await _weeklyLimitsCollection.doc(limit.id).set(
        limit.toMap(),
        SetOptions(merge: true),
      );
    } catch (e) {
      AppLogger.warn(
        'Failed to sync weekly limit ${limit.id}: $e',
        label: 'FirestoreSync',
      );
    }
  }

  Future<void> deleteWeeklyLimit(String id) async {
    if (!isAuthenticated) return;
    try {
      await _weeklyLimitsCollection.doc(id).delete();
    } catch (e) {
      AppLogger.warn(
        'Failed to delete weekly limit $id: $e',
        label: 'FirestoreSync',
      );
    }
  }

  Stream<List<WeeklyLimit>> weeklyLimitsStream() {
    if (!isAuthenticated) return const Stream.empty();
    return _weeklyLimitsCollection
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) {
                try {
                  return WeeklyLimit.fromMap(doc.data());
                } catch (e) {
                  AppLogger.warn(
                    'Failed to parse weekly limit ${doc.id}: $e',
                    label: 'FirestoreSync',
                  );
                  return null;
                }
              })
              .whereType<WeeklyLimit>()
              .toList();
        })
        .handleError((Object e) {
          AppLogger.warn(
            'weeklyLimitsStream error: $e',
            label: 'FirestoreSync',
          );
          return <WeeklyLimit>[];
        });
  }

  Future<List<WeeklyLimit>> fetchAllWeeklyLimits() async {
    if (!isAuthenticated) return [];
    try {
      final snap = await _weeklyLimitsCollection.get();
      return snap.docs
          .map((doc) {
            try {
              return WeeklyLimit.fromMap(doc.data());
            } catch (e) {
              AppLogger.warn(
                'Failed to parse weekly limit ${doc.id}: $e',
                label: 'FirestoreSync',
              );
              return null;
            }
          })
          .whereType<WeeklyLimit>()
          .toList();
    } catch (e) {
      AppLogger.warn(
        'fetchAllWeeklyLimits error: $e',
        label: 'FirestoreSync',
      );
      return [];
    }
  }
}
