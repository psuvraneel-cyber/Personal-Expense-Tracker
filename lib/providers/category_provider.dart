import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pet/data/models/category.dart';
import 'package:pet/data/repositories/category_repository.dart';
import 'package:pet/core/constants/categories.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:uuid/uuid.dart';

class CategoryProvider extends ChangeNotifier {
  final CategoryRepository _repository = CategoryRepository();
  final FirestoreSyncService _firestoreSync = FirestoreSyncService();
  final Uuid _uuid = const Uuid();

  List<Category> _categories = [];
  bool _isLoading = false;
  StreamSubscription<List<Category>>? _firestoreSubscription;

  List<Category> get categories => _categories;
  List<Category> get expenseCategories => _categories
      .where((c) => c.type == 'expense' || c.type == 'both')
      .toList();
  List<Category> get incomeCategories =>
      _categories.where((c) => c.type == 'income' || c.type == 'both').toList();
  bool get isLoading => _isLoading;

  Future<void> loadCategories() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (kIsWeb) {
        // Web: start with default categories immediately so the UI has data,
        // then subscribe to Firestore for custom categories.
        _categories = List<Category>.from(defaultCategories);
        _subscribeToFirestoreCustomCategories();
      } else {
        // Mobile/desktop: load from SQLite.
        final dbCategories = await _repository.getAllCategories();
        if (dbCategories.isEmpty) {
          // First run — SQLite not seeded yet. Use defaults in-memory.
          _categories = List<Category>.from(defaultCategories);
        } else {
          _categories = dbCategories;
        }
        // Mirror custom categories from Firestore in the background.
        _subscribeToFirestoreCustomCategories();
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
      if (_categories.isEmpty) {
        _categories = List<Category>.from(defaultCategories);
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Subscribes to Firestore custom categories and merges them on top of defaults.
  void _subscribeToFirestoreCustomCategories() {
    if (AccountDeletionService.isDeletionInProgress) {
      debugPrint('[Category] Skip subscribe — account deletion in progress');
      return;
    }
    _firestoreSubscription?.cancel();
    try {
      _firestoreSubscription = _firestoreSync.categoriesStream().listen(
        (remoteCustomCats) {
          // Keep default categories, replace/add custom ones from Firestore.
          final defaultIds = defaultCategories.map((c) => c.id).toSet();
          final merged = List<Category>.from(defaultCategories);
          for (final cat in remoteCustomCats) {
            if (!defaultIds.contains(cat.id)) {
              final existingIdx = merged.indexWhere((c) => c.id == cat.id);
              if (existingIdx >= 0) {
                merged[existingIdx] = cat;
              } else {
                merged.add(cat);
              }
            }
          }
          _categories = merged;
          notifyListeners();
        },
        onError: (Object e) =>
            debugPrint('[CategoryProvider] Firestore stream error: $e'),
      );
    } catch (e) {
      debugPrint('[CategoryProvider] Could not subscribe to Firestore: $e');
    }
  }

  Category? getCategoryById(String id) {
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addCustomCategory({
    required String name,
    required IconData icon,
    required Color color,
    required String type,
  }) async {
    final category = Category(
      id: 'cat_custom_${_uuid.v4().substring(0, 8)}',
      name: name,
      icon: icon,
      color: color,
      isCustom: true,
      type: type,
    );

    if (!kIsWeb) {
      await _repository
          .insertCategory(category)
          .catchError(
            (Object e) => debugPrint('SQLite category insert failed: $e'),
          );
    }
    _categories.add(category);
    notifyListeners();

    // Mirror to Firestore in background.
    _firestoreSync
        .upsertCategory(category)
        .catchError((Object e) => debugPrint('[Sync] category upsert: $e'));
  }

  Future<void> updateCategory(Category category) async {
    if (!kIsWeb) {
      await _repository
          .updateCategory(category)
          .catchError(
            (Object e) => debugPrint('SQLite category update failed: $e'),
          );
    }
    final index = _categories.indexWhere((c) => c.id == category.id);
    if (index != -1) {
      _categories[index] = category;
      notifyListeners();
    }

    _firestoreSync
        .upsertCategory(category)
        .catchError((Object e) => debugPrint('[Sync] category update: $e'));
  }

  Future<void> deleteCategory(String id) async {
    if (!kIsWeb) {
      await _repository
          .deleteCategory(id)
          .catchError(
            (Object e) => debugPrint('SQLite category delete failed: $e'),
          );
    }
    _categories.removeWhere((c) => c.id == id);
    notifyListeners();

    _firestoreSync
        .deleteCategory(id)
        .catchError((Object e) => debugPrint('[Sync] category delete: $e'));
  }

  /// Clear all in-memory state, cancel Firestore subscriptions,
  /// and wipe custom categories from SQLite.
  /// Called on sign-out to prevent data leaking between accounts.
  Future<void> clearData() async {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _categories = [];
    notifyListeners();

    // Wipe custom categories from SQLite.
    if (!kIsWeb) {
      await _repository.deleteAllCustomCategories().catchError(
        (Object e) => debugPrint('SQLite cat clear failed: $e'),
      );
    }
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}
