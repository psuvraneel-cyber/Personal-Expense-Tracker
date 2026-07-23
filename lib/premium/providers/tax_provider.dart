import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaxProvider extends ChangeNotifier {
  // Default indicative limits
  static const Map<String, double> defaultLimits = {
    '80C': 150000.0,
    '80D': 25000.0,
    'HRA': 100000.0,
    'LTA': 20000.0,
    '80E': double.infinity, // No statutory limit
  };

  Map<String, double> _limits = Map.from(defaultLimits);

  Map<String, double> get limits => Map.unmodifiable(_limits);

  TaxProvider() {
    _loadLimits();
  }

  Future<void> _loadLimits() async {
    final prefs = await SharedPreferences.getInstance();
    bool updated = false;

    for (final key in defaultLimits.keys) {
      if (key == '80E') continue; // 80E is never stored, always infinity
      final storedValue = prefs.getDouble('tax_limit_$key');
      if (storedValue != null) {
        _limits[key] = storedValue;
        updated = true;
      }
    }

    if (updated) {
      notifyListeners();
    }
  }

  Future<void> setLimit(String section, double value) async {
    if (section == '80E') return; // Cannot edit 80E

    _limits[section] = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tax_limit_$section', value);
  }

  Future<void> resetToDefaults() async {
    _limits = Map.from(defaultLimits);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    for (final key in defaultLimits.keys) {
      if (key == '80E') continue;
      await prefs.remove('tax_limit_$key');
    }
  }

  void clearData() {
    _limits = Map.from(defaultLimits);
    notifyListeners();
  }
}
