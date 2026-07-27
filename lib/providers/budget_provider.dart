import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/budget.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:uuid/uuid.dart';

class BudgetProvider extends ChangeNotifier {
  final BudgetRepository _budgetRepository = BudgetRepository();
  final TransactionRepository _transactionRepository = TransactionRepository();
  final FirestoreSyncService _firestoreSync = FirestoreSyncService();
  final Uuid _uuid = const Uuid();

  List<Budget> _budgets = [];
  Map<String, double> _spentAmounts = {};
  bool _isLoading = false;
  int _currentMonth = DateTime.now().month;
  int _currentYear = DateTime.now().year;
  List<TransactionRecord>? _lastTransactionsForSpent;

  List<Budget> get budgets => _budgets;
  Map<String, double> get spentAmounts => _spentAmounts;
  bool get isLoading => _isLoading;
  int get currentMonth => _currentMonth;
  int get currentYear => _currentYear;

  Future<void> loadBudgets({int? month, int? year}) async {
    _isLoading = true;
    notifyListeners();

    if (month != null) _currentMonth = month;
    if (year != null) _currentYear = year;

    try {
      if (!kIsWeb) {
        _budgets = await _budgetRepository.getBudgetsByMonth(
          _currentMonth,
          _currentYear,
        );

        _spentAmounts = {};
        for (final budget in _budgets) {
          final spent = await _transactionRepository.getSpentInCategory(
            budget.categoryId,
            _currentMonth,
            _currentYear,
          );
          _spentAmounts[budget.categoryId] = spent;
        }
      }
      // On web, budgets are populated via refreshSpentFromTransactions()
      // and setBudget() which writes directly to Firestore.
    } catch (e) {
      AppLogger.error('Error loading budgets', error: e, label: 'BudgetProvider');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setBudget({
    required String categoryId,
    required double amount,
  }) async {
    final existingIndex = _budgets.indexWhere(
      (b) => b.categoryId == categoryId,
    );
    final budget = Budget(
      id: existingIndex >= 0 ? _budgets[existingIndex].id : _uuid.v4(),
      categoryId: categoryId,
      amount: amount,
      month: _currentMonth,
      year: _currentYear,
    );

    if (!kIsWeb) {
      await _budgetRepository
          .insertOrUpdateBudget(budget)
          .catchError(
            (Object e) => AppLogger.error('SQLite budget insert failed', error: e, label: 'DB'),
          );

      // Update spent amount from SQLite
      final spent = await _transactionRepository.getSpentInCategory(
        categoryId,
        _currentMonth,
        _currentYear,
      );
      _spentAmounts[categoryId] = spent;
    }

    if (existingIndex >= 0) {
      _budgets[existingIndex] = budget;
    } else {
      _budgets.add(budget);
    }
    notifyListeners();

    // Mirror to Firestore in background.
    _firestoreSync
        .upsertBudget(budget)
        .catchError((Object e) => AppLogger.error('budget upsert failed', error: e, label: 'Sync'));
  }

  Future<void> deleteBudget(String categoryId) async {
    final budget = _budgets.firstWhere(
      (b) => b.categoryId == categoryId,
      orElse: () => Budget(
        id: '',
        categoryId: categoryId,
        amount: 0,
        month: _currentMonth,
        year: _currentYear,
      ),
    );

    if (!kIsWeb) {
      await _budgetRepository
          .deleteBudgetForCategory(categoryId, _currentMonth, _currentYear)
          .catchError(
            (Object e) => AppLogger.error('SQLite budget delete failed', error: e, label: 'DB'),
          );
    }

    _budgets.removeWhere((b) => b.categoryId == categoryId);
    _spentAmounts.remove(categoryId);
    notifyListeners();

    if (budget.id.isNotEmpty) {
      _firestoreSync
          .deleteBudget(budget.id)
          .catchError((Object e) => AppLogger.error('budget delete failed', error: e, label: 'Sync'));
    }
  }

  double getSpentForCategory(String categoryId) {
    return _spentAmounts[categoryId] ?? 0.0;
  }

  double getBudgetProgress(String categoryId) {
    final budget = _budgets
        .where((b) => b.categoryId == categoryId)
        .firstOrNull;
    if (budget == null || budget.amount == 0) return 0.0;
    final spent = _spentAmounts[categoryId] ?? 0.0;
    return (spent / budget.amount).clamp(0.0, 2.0);
  }

  bool isOverBudget(String categoryId) {
    return getBudgetProgress(categoryId) >= 1.0;
  }

  List<String> getOverBudgetCategories() {
    return _budgets
        .where((b) => isOverBudget(b.categoryId))
        .map((b) => b.categoryId)
        .toList();
  }

  void setMonth(int month, int year) {
    _currentMonth = month;
    _currentYear = year;
    loadBudgets();
  }

  void refreshSpentFromTransactions(List<TransactionRecord> transactions) {
    if (identical(_lastTransactionsForSpent, transactions)) return;
    _lastTransactionsForSpent = transactions;
    if (_budgets.isEmpty) return;

    final Map<String, double> spent = {};
    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      if (t.date.month != _currentMonth || t.date.year != _currentYear) {
        continue;
      }
      spent[t.categoryId] = (spent[t.categoryId] ?? 0) + t.amount;
    }

    _spentAmounts = spent;
    notifyListeners();
  }

  /// Clear all in-memory state and wipe budgets from SQLite.
  /// Called on sign-out to prevent data leaking between accounts.
  Future<void> clearData() async {
    _budgets = [];
    _spentAmounts = {};
    notifyListeners();

    // Wipe budgets from SQLite.
    if (!kIsWeb) {
      await _budgetRepository.deleteAllBudgets().catchError(
        (Object e) => AppLogger.error('SQLite budget clear failed', error: e, label: 'DB'),
      );
    }
  }
}
