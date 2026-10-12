import 'package:pet/premium/models/tax_category.dart';

class TaxCategoryService {
  TaxCategoryService._();

  static final List<TaxCategory> defaults = [
    TaxCategory(id: '80C', name: '80C (ELSS, LIC, PPF)'),
    TaxCategory(id: '80D', name: '80D (Health Insurance: self & family)'),
    TaxCategory(id: '80DP', name: '80D (Health Insurance: parents)'),
    TaxCategory(id: 'HRA', name: 'Rent paid (for HRA)'),
    TaxCategory(id: 'LTA', name: 'Leave Travel Allowance (LTA)'),
    TaxCategory(id: '80E', name: '80E (Education Loan)'),
  ];
}
