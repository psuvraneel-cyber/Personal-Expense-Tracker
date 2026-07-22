import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages which dashboard cards are visible and their order.
///
/// Users can hide, show, and reorder dashboard sections:
/// - Summary card
/// - Spending chart
/// - Budget overview
/// - Recent transactions
/// - UPI activity
class DashboardConfigProvider extends ChangeNotifier {
  static const _kOrder = 'dashboardCardOrder';
  static const _kHidden = 'dashboardHiddenCards';

  /// Default card identifiers and their display order.
  static const defaultOrder = [
    'summary',
    'spending_chart',
    'budget',
    'transactions',
    'upi_activity',
  ];

  static const cardLabels = {
    'summary': 'Balance Summary',
    'spending_chart': 'Spending Chart',
    'budget': 'Budget Overview',
    'transactions': 'Recent Transactions',
    'upi_activity': 'UPI Activity',
  };

  List<String> _order = List.from(defaultOrder);
  Set<String> _hidden = {};

  List<String> get order => _order;
  Set<String> get hidden => _hidden;

  /// Visible cards in the configured order.
  List<String> get visibleCards =>
      _order.where((c) => !_hidden.contains(c)).toList();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList(_kOrder);
      final savedHidden = prefs.getStringList(_kHidden);
      if (savedOrder != null && savedOrder.isNotEmpty) _order = savedOrder;
      if (savedHidden != null) _hidden = savedHidden.toSet();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final visible = visibleCards;
    final item = visible.removeAt(oldIndex);
    visible.insert(newIndex, item);

    // Rebuild full order preserving hidden items in relative position
    _order = [...visible, ..._hidden];
    await _save();
    notifyListeners();
  }

  Future<void> toggleCard(String cardId) async {
    if (_hidden.contains(cardId)) {
      _hidden.remove(cardId);
    } else {
      _hidden.add(cardId);
    }
    await _save();
    notifyListeners();
  }

  Future<void> resetToDefault() async {
    _order = List.from(defaultOrder);
    _hidden = {};
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kOrder, _order);
      await prefs.setStringList(_kHidden, _hidden.toList());
    } catch (_) {}
  }

  void clearData() {
    _order = List.from(defaultOrder);
    _hidden = {};
    notifyListeners();
  }
}
