import 'package:pet/core/constants/categories.dart';

/// Central mapping service between parser category strings / merchant types
/// and canonical P.E.T. category IDs.
class CategoryMapper {
  CategoryMapper._();

  static const String fallbackExpenseCategoryId = 'cat_other_expense';
  static const String fallbackIncomeCategoryId = 'cat_other_income';

  /// IDs older builds wrote that match no category (shown as "Unknown"),
  /// mapped to the categories they meant.
  static const Map<String, String> legacyCategoryIds = {
    'cat_other': fallbackExpenseCategoryId,
    'cat_investments': 'cat_investment',
    'cat_gifts': 'cat_gift_income',
  };

  /// Returns the current ID for [categoryId], replacing legacy IDs.
  static String canonicalCategoryId(String categoryId) =>
      legacyCategoryIds[categoryId] ?? categoryId;

  /// Every ID [mapToCategoryId] can return. Visible for testing.
  static Set<String> get allMappedIds => {
        fallbackExpenseCategoryId,
        fallbackIncomeCategoryId,
        ..._knownCategoryMappings.values,
      };

  /// Map of known category names / keywords to canonical category IDs.
  static const Map<String, String> _knownCategoryMappings = {
    // Food & Dining
    'food & dining': 'cat_food',
    'food': 'cat_food',
    'dining': 'cat_food',
    'restaurant': 'cat_food',
    'cafe': 'cat_food',
    'zomato': 'cat_food',
    'swiggy': 'cat_food',
    'starbucks': 'cat_food',
    'mcdonalds': 'cat_food',
    'dominos': 'cat_food',

    // Groceries
    'groceries': 'cat_groceries',
    'grocery': 'cat_groceries',
    'supermarket': 'cat_groceries',
    'blinkit': 'cat_groceries',
    'zepto': 'cat_groceries',
    'instamart': 'cat_groceries',
    'bigbasket': 'cat_groceries',
    'dmart': 'cat_groceries',

    // Transport
    'transport': 'cat_transport',
    'transportation': 'cat_transport',
    'travel': 'cat_transport',
    'cab': 'cat_transport',
    'ride': 'cat_transport',
    'fuel': 'cat_transport',
    'petrol': 'cat_transport',
    'uber': 'cat_transport',
    'ola': 'cat_transport',
    'rapido': 'cat_transport',
    'metro': 'cat_transport',
    'irctc': 'cat_transport',

    // Bills & Utilities
    'bills & utilities': 'cat_bills',
    'bills': 'cat_bills',
    'utilities': 'cat_bills',
    'utility': 'cat_bills',
    'electricity': 'cat_bills',
    'water': 'cat_bills',
    'gas': 'cat_bills',
    'broadband': 'cat_bills',
    'wifi': 'cat_bills',
    'telecom': 'cat_bills',
    'recharge': 'cat_bills',
    'mobile': 'cat_bills',
    'jio': 'cat_bills',
    'airtel': 'cat_bills',
    'vi': 'cat_bills',

    // Shopping
    'shopping': 'cat_shopping',
    'ecommerce': 'cat_shopping',
    'retail': 'cat_shopping',
    'amazon': 'cat_shopping',
    'flipkart': 'cat_shopping',
    'myntra': 'cat_shopping',
    'meesho': 'cat_shopping',
    'nykaa': 'cat_shopping',

    // Health
    'health': 'cat_health',
    'medical': 'cat_health',
    'pharmacy': 'cat_health',
    'hospital': 'cat_health',
    'doctor': 'cat_health',
    'apollo': 'cat_health',
    '1mg': 'cat_health',
    'pharmeasy': 'cat_health',

    // Entertainment
    'entertainment': 'cat_entertainment',
    'movie': 'cat_entertainment',
    'movies': 'cat_entertainment',
    'streaming': 'cat_entertainment',
    'netflix': 'cat_entertainment',
    'spotify': 'cat_entertainment',
    'bookmyshow': 'cat_entertainment',
    'pvr': 'cat_entertainment',
    'hotstar': 'cat_entertainment',

    // Education
    'education': 'cat_education',
    'books': 'cat_education',
    'course': 'cat_education',
    'college': 'cat_education',
    'school': 'cat_education',
    'udemy': 'cat_education',
    'coursera': 'cat_education',

    // Income categories
    'salary': 'cat_salary',
    'payroll': 'cat_salary',
    'freelance': 'cat_freelance',
    'consulting': 'cat_freelance',
    'investments': 'cat_investment',
    'investment': 'cat_investment',
    'dividend': 'cat_investment',
    'interest': 'cat_investment',
    'mutual fund': 'cat_investment',
    'stocks': 'cat_investment',
    'groww': 'cat_investment',
    'zerodha': 'cat_investment',
    'gifts': 'cat_gift_income',
    'gift': 'cat_gift_income',
    'cashback': 'cat_other_income',
    'refund': 'cat_other_income',
  };

  /// Maps a parser-emitted category string or merchant string to a valid
  /// canonical category ID.
  ///
  /// [isIncome] indicates whether the transaction is an income credit.
  static String mapToCategoryId({
    String? parserCategory,
    String? merchantName,
    bool isIncome = false,
  }) {
    if (parserCategory != null && parserCategory.trim().isNotEmpty) {
      final normalizedCat = parserCategory.trim().toLowerCase();
      if (_knownCategoryMappings.containsKey(normalizedCat)) {
        final id = _knownCategoryMappings[normalizedCat]!;
        if (_categoryMatchesDirection(id, isIncome)) return id;
      }
      for (final entry in _knownCategoryMappings.entries) {
        if (_keyMatches(normalizedCat, entry.key)) {
          if (_categoryMatchesDirection(entry.value, isIncome)) {
            return entry.value;
          }
        }
      }
    }

    if (merchantName != null && merchantName.trim().isNotEmpty) {
      final normalizedMerchant = merchantName.trim().toLowerCase();
      for (final entry in _knownCategoryMappings.entries) {
        if (_keyMatches(normalizedMerchant, entry.key)) {
          if (_categoryMatchesDirection(entry.value, isIncome)) {
            return entry.value;
          }
        }
      }
    }

    return isIncome ? fallbackIncomeCategoryId : fallbackExpenseCategoryId;
  }

  /// Short generic words that must match a whole word: as substrings they
  /// hit ordinary text ("vi" in "via", "Savings" and "Ravi").
  static const Set<String> _wholeWordKeys = {
    'food',
    'cafe',
    'cab',
    'ride',
    'fuel',
    'gas',
    'wifi',
    'vi',
    'gift',
  };

  /// Short brands that banks often join to other words ("OLACABS",
  /// "JIOFIBER", "UBERINDIA"), so they only need to start a word.
  static const Set<String> _wordStartKeys = {'ola', 'jio', 'uber', 'pvr'};

  static final Map<String, RegExp> _keyPatterns = {};

  static bool _keyMatches(String text, String key) {
    if (_wholeWordKeys.contains(key)) {
      final re = _keyPatterns.putIfAbsent(
          key, () => RegExp('(?<![a-z0-9])${RegExp.escape(key)}(?![a-z0-9])'));
      return re.hasMatch(text);
    }
    if (_wordStartKeys.contains(key)) {
      final re = _keyPatterns.putIfAbsent(
          key, () => RegExp('(?<![a-z0-9])${RegExp.escape(key)}'));
      return re.hasMatch(text);
    }
    return text.contains(key);
  }

  static bool _categoryMatchesDirection(String categoryId, bool isIncome) {
    final category = defaultCategories.where((c) => c.id == categoryId);
    if (category.isEmpty) return true;
    final type = category.first.type;
    return type == 'transfer' || type == (isIncome ? 'income' : 'expense');
  }
}
