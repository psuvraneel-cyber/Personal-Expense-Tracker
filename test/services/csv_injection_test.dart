import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/export_service.dart';

/// Audit P2-14: SMS-derived text must not run as a spreadsheet formula.
void main() {
  test('formula-like cells are neutralised', () {
    for (final cell in ['=HYPERLINK("x")', '+1+1', '@SUM(A1)', '-2+3']) {
      expect(ExportService.neutralizeFormula(cell), "'$cell");
    }
  });

  test('ordinary values and negative numbers are untouched', () {
    expect(ExportService.neutralizeFormula('Swiggy'), 'Swiggy');
    expect(ExportService.neutralizeFormula('-250.00'), '-250.00');
    expect(ExportService.neutralizeFormula(''), '');
  });
}
