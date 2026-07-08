import 'package:pet/premium/models/tax_category.dart';

class TaxCategoryService {
  TaxCategoryService._();

  static final List<TaxCategory> defaults = [
    TaxCategory(id: '80C', name: '80C (ELSS, LIC, PPF)'),
    TaxCategory(id: '80D', name: '80D (Health Insurance)'),
    TaxCategory(id: 'HRA', name: 'House Rent Allowance (HRA)'),
    TaxCategory(id: 'LTA', name: 'Leave Travel Allowance (LTA)'),
    TaxCategory(id: '80E', name: '80E (Education Loan)'),
  ];
}
