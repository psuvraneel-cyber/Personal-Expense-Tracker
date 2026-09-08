/// Central mapping service between parser category strings / merchant types
/// and canonical P.E.T. category IDs.
class CategoryMapper {
  CategoryMapper._();

  static const String fallbackExpenseCategoryId = 'cat_other';
  static const String fallbackIncomeCategoryId = 'cat_other_income';

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
    'investments': 'cat_investments',
    'investment': 'cat_investments',
    'dividend': 'cat_investments',
    'interest': 'cat_investments',
    'mutual fund': 'cat_investments',
    'stocks': 'cat_investments',
    'groww': 'cat_investments',
    'zerodha': 'cat_investments',
    'gifts': 'cat_gifts',
    'gift': 'cat_gifts',
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
        return _knownCategoryMappings[normalizedCat]!;
      }
      for (final entry in _knownCategoryMappings.entries) {
        if (normalizedCat.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    if (merchantName != null && merchantName.trim().isNotEmpty) {
      final normalizedMerchant = merchantName.trim().toLowerCase();
      for (final entry in _knownCategoryMappings.entries) {
        if (normalizedMerchant.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    return isIncome ? fallbackIncomeCategoryId : fallbackExpenseCategoryId;
  }
}
