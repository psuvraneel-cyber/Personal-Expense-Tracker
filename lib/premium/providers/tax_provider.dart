import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which income-tax regime the user files under. Most deductions tracked
/// here (80C, 80D, HRA, LTA, 80E) can only be claimed under the old regime.
enum TaxRegime { oldRegime, newRegime }

class TaxProvider extends ChangeNotifier {
  // Default indicative limits (editable). HRA has no fixed limit: the
  // exemption is a formula on salary, HRA received and rent, which the app
  // can't know, so the bucket only records rent paid.
  static const Map<String, double> defaultLimits = {
    '80C': 150000.0,
    '80D': 25000.0, // self, spouse, children (₹50,000 if 60 or older)
    '80DP': 25000.0, // parents (₹50,000 if they are 60 or older)
    'HRA': double.infinity,
    'LTA': 20000.0,
    '80E': double.infinity, // No statutory limit
  };

  /// Sections whose totals are records, not amounts with a known cap that
  /// can be counted towards a tax-saving estimate.
  static const Set<String> recordOnlySections = {'HRA'};

  /// Income-tax slab rates a user can pick for the estimate.
  static const List<double> slabRates = [0.05, 0.10, 0.15, 0.20, 0.30];

  /// Health and education cess added to income tax.
  static const double cess = 0.04;

  static const _kRegime = 'tax_regime';
  static const _kSlabRate = 'tax_slab_rate';

  Map<String, double> _limits = Map.from(defaultLimits);
  TaxRegime? _regime;
  double _slabRate = 0.20;

  Map<String, double> get limits => Map.unmodifiable(_limits);

  /// Null until the user says which regime they use.
  TaxRegime? get regime => _regime;
  double get slabRate => _slabRate;

  TaxProvider() {
    _loadLimits();
  }

  /// Tagged amounts that can count: each section capped at its limit,
  /// excluding record-only sections.
  static double claimable(
    Map<String, double> totals,
    Map<String, double> limits,
  ) {
    var sum = 0.0;
    totals.forEach((section, amount) {
      if (recordOnlySections.contains(section)) return;
      final limit = limits[section] ?? double.infinity;
      sum += amount < limit ? amount : limit;
    });
    return sum;
  }

  /// Rough tax saved: only under the old regime, at the user's slab plus
  /// cess. Zero when the regime is new or unknown.
  static double estimatedSaving({
    required double claimable,
    required TaxRegime? regime,
    required double slabRate,
  }) =>
      regime == TaxRegime.oldRegime ? claimable * slabRate * (1 + cess) : 0.0;

  Future<void> _loadLimits() async {
    final prefs = await SharedPreferences.getInstance();
    bool updated = false;

    for (final key in defaultLimits.keys) {
      if (!defaultLimits[key]!.isFinite) continue; // never stored
      final storedValue = prefs.getDouble('tax_limit_$key');
      if (storedValue != null) {
        _limits[key] = storedValue;
        updated = true;
      }
    }

    final regime = prefs.getString(_kRegime);
    if (regime != null) {
      _regime = regime == 'old' ? TaxRegime.oldRegime : TaxRegime.newRegime;
      updated = true;
    }
    final rate = prefs.getDouble(_kSlabRate);
    if (rate != null && slabRates.contains(rate)) {
      _slabRate = rate;
      updated = true;
    }

    if (updated) {
      notifyListeners();
    }
  }

  Future<void> setRegime(TaxRegime regime) async {
    _regime = regime;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kRegime, regime == TaxRegime.oldRegime ? 'old' : 'new');
  }

  Future<void> setSlabRate(double rate) async {
    if (!slabRates.contains(rate)) return;
    _slabRate = rate;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSlabRate, rate);
  }

  Future<void> setLimit(String section, double value) async {
    if (!(defaultLimits[section]?.isFinite ?? false)) return; // no-limit

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
      if (!defaultLimits[key]!.isFinite) continue;
      await prefs.remove('tax_limit_$key');
    }
  }

  void clearData() {
    _limits = Map.from(defaultLimits);
    _regime = null;
    _slabRate = 0.20;
    notifyListeners();
  }
}
