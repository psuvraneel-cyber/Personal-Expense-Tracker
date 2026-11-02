import 'package:pet/premium/models/invoice.dart';

/// Totals of an invoice, with the GST breakup.
class InvoiceTotals {
  const InvoiceTotals({
    required this.subtotal,
    required this.discount,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.roundOff,
    required this.total,
    required this.lineTaxable,
    required this.lineTax,
  });

  /// Sum of quantity × rate before the discount.
  final double subtotal;
  final double discount;

  /// Subtotal after the discount (what GST is charged on).
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;

  /// Rounding to the nearest rupee, shown as its own line.
  final double roundOff;
  final double total;

  /// Per line: taxable value after its share of the discount, and its tax.
  final List<double> lineTaxable;
  final List<double> lineTax;

  double get totalTax => cgst + sgst + igst;
}

/// Pure invoice arithmetic: no I/O, so it is exhaustively unit-tested.
class InvoiceCalculator {
  InvoiceCalculator._();

  /// GST rates offered in the editor (after the 2025 rationalisation).
  static const List<double> gstRates = [0, 5, 18, 40];

  static double round2(double v) => (v * 100).roundToDouble() / 100;

  /// Totals for [items]. The invoice [discount] is shared across lines in
  /// proportion to their value, before tax (so GST is charged on the
  /// discounted value). With [gstEnabled], tax is CGST + SGST when
  /// [interState] is false and IGST when it is true.
  static InvoiceTotals compute({
    required List<InvoiceItem> items,
    double discount = 0,
    bool gstEnabled = false,
    bool interState = false,
  }) {
    final lineValues = [for (final i in items) round2(i.quantity * i.rate)];
    final subtotal = round2(lineValues.fold(0.0, (s, v) => s + v));
    final appliedDiscount = round2(discount.clamp(0, subtotal).toDouble());

    final lineTaxable = <double>[];
    final lineTax = <double>[];
    double cgst = 0, sgst = 0, igst = 0;
    for (var i = 0; i < items.length; i++) {
      final share = subtotal == 0 ? 0.0 : lineValues[i] / subtotal;
      final taxable = round2(lineValues[i] - appliedDiscount * share);
      lineTaxable.add(taxable);
      if (!gstEnabled || items[i].gstRate <= 0) {
        lineTax.add(0);
        continue;
      }
      if (interState) {
        final tax = round2(taxable * items[i].gstRate / 100);
        igst += tax;
        lineTax.add(tax);
      } else {
        // Each half is rounded on its own, as it is printed.
        final half = round2(taxable * items[i].gstRate / 200);
        cgst += half;
        sgst += half;
        lineTax.add(half * 2);
      }
    }
    final taxableValue = round2(lineTaxable.fold(0.0, (s, v) => s + v));
    cgst = round2(cgst);
    sgst = round2(sgst);
    igst = round2(igst);
    final exact = round2(taxableValue + cgst + sgst + igst);
    final total = exact.roundToDouble();
    return InvoiceTotals(
      subtotal: subtotal,
      discount: appliedDiscount,
      taxableValue: taxableValue,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      roundOff: round2(total - exact),
      total: total,
      lineTaxable: lineTaxable,
      lineTax: lineTax,
    );
  }

  // ── Financial year & numbering ────────────────────────────────────────

  /// Indian financial year (April–March) of [date], e.g. "26-27".
  static String financialYear(DateTime date) {
    final start = date.month >= 4 ? date.year : date.year - 1;
    String two(int y) => (y % 100).toString().padLeft(2, '0');
    return '${two(start)}-${two(start + 1)}';
  }

  /// "INV/26-27/0001". GST rules allow at most 16 characters, so the prefix
  /// is capped at 5.
  static String formatNumber(String prefix, DateTime date, int sequence) {
    final p = cleanPrefix(prefix);
    return '$p/${financialYear(date)}/${sequence.toString().padLeft(4, '0')}';
  }

  /// Letters and digits only, upper case, at most 5 (default "INV").
  static String cleanPrefix(String prefix) {
    final p = prefix.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (p.isEmpty) return 'INV';
    return p.length > 5 ? p.substring(0, 5) : p;
  }

  /// The next number in [date]'s financial year for [prefix], one after
  /// the highest already used (so numbers stay consecutive per year).
  static String nextNumber(
      String prefix, DateTime date, Iterable<String> existing) {
    final head = '${cleanPrefix(prefix)}/${financialYear(date)}/';
    var highest = 0;
    for (final n in existing) {
      if (!n.startsWith(head)) continue;
      final seq = int.tryParse(n.substring(head.length));
      if (seq != null && seq > highest) highest = seq;
    }
    return formatNumber(prefix, date, highest + 1);
  }

  // ── Amount in words (Indian system) ───────────────────────────────────

  static const _ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  static const _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  static String _belowHundred(int n) =>
      n < 20 ? _ones[n] : '${_tens[n ~/ 10]} ${_ones[n % 10]}'.trim();

  static String _belowThousand(int n) {
    final h = n ~/ 100, r = n % 100;
    return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _belowHundred(r)]
        .join(' ');
  }

  /// Whole rupees in words: 1,23,45,678 → "One Crore Twenty Three Lakh
  /// Forty Five Thousand Six Hundred Seventy Eight".
  static String numberInWords(int n) {
    if (n == 0) return 'Zero';
    final parts = <String>[];
    final crore = n ~/ 10000000;
    if (crore > 0) parts.add('${numberInWords(crore)} Crore');
    final lakh = (n ~/ 100000) % 100;
    if (lakh > 0) parts.add('${_belowHundred(lakh)} Lakh');
    final thousand = (n ~/ 1000) % 100;
    if (thousand > 0) parts.add('${_belowHundred(thousand)} Thousand');
    final rest = n % 1000;
    if (rest > 0) parts.add(_belowThousand(rest));
    return parts.join(' ');
  }

  /// "Rupees Twelve Thousand and Fifty Paise Only".
  static String amountInWords(double amount) {
    final paise = (amount * 100).round();
    final rupees = paise ~/ 100, p = paise % 100;
    final words = 'Rupees ${numberInWords(rupees)}';
    return p > 0 ? '$words and ${_belowHundred(p)} Paise Only' : '$words Only';
  }

  // ── GSTIN ─────────────────────────────────────────────────────────────

  static final RegExp _gstinShape =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
  static const _gstinChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// A well-formed GSTIN with a valid check digit.
  static bool isValidGstin(String raw) {
    final g = raw.trim().toUpperCase();
    if (!_gstinShape.hasMatch(g)) return false;
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      final product = _gstinChars.indexOf(g[i]) * (i.isEven ? 1 : 2);
      sum += product ~/ 36 + product % 36;
    }
    final check = (36 - sum % 36) % 36;
    return g[14] == _gstinChars[check];
  }

  /// The two-digit state code a GSTIN starts with.
  static String? stateCodeOfGstin(String gstin) {
    final g = gstin.trim();
    return g.length >= 2 && RegExp(r'^\d{2}').hasMatch(g)
        ? g.substring(0, 2)
        : null;
  }
}

/// GST state and union-territory codes.
const Map<String, String> kGstStates = {
  '01': 'Jammu & Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '26': 'Dadra & Nagar Haveli and Daman & Diu',
  '27': 'Maharashtra',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman & Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
  '97': 'Other Territory',
};
