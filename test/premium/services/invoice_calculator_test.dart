import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/services/invoice_calculator.dart';
import 'package:pet/premium/services/upi_link.dart';

void main() {
  group('totals', () {
    const items = [
      InvoiceItem(
          description: 'Logo design', quantity: 1, rate: 10000, gstRate: 18),
      InvoiceItem(
          description: 'Revisions', quantity: 2, rate: 1500, gstRate: 18),
    ];

    test('without GST: just the sum, rounded to the rupee', () {
      final t = InvoiceCalculator.compute(items: const [
        InvoiceItem(description: 'Tuition', quantity: 3, rate: 333.33),
      ]);
      expect(t.subtotal, 999.99);
      expect(t.totalTax, 0);
      expect(t.total, 1000);
      expect(t.roundOff, 0.01);
    });

    test('same state: CGST + SGST, half the rate each', () {
      final t = InvoiceCalculator.compute(items: items, gstEnabled: true);
      expect(t.subtotal, 13000);
      expect(t.cgst, 1170);
      expect(t.sgst, 1170);
      expect(t.igst, 0);
      expect(t.total, 15340);
    });

    test('other state: IGST at the full rate', () {
      final t = InvoiceCalculator.compute(
          items: items, gstEnabled: true, interState: true);
      expect(t.cgst, 0);
      expect(t.igst, 2340);
      expect(t.total, 15340);
    });

    test('the discount is shared across lines before tax', () {
      final t = InvoiceCalculator.compute(
        items: const [
          InvoiceItem(description: 'A', rate: 1000, gstRate: 5),
          InvoiceItem(description: 'B', rate: 3000, gstRate: 18),
        ],
        discount: 400,
        gstEnabled: true,
      );
      expect(t.lineTaxable, [900, 2700]);
      expect(t.taxableValue, 3600);
      expect(t.cgst, 22.5 + 243);
      expect(t.total, (3600 + 45 + 486).roundToDouble());
    });

    test('a discount larger than the subtotal is capped', () {
      final t = InvoiceCalculator.compute(
        items: const [InvoiceItem(description: 'A', rate: 500)],
        discount: 900,
      );
      expect(t.discount, 500);
      expect(t.total, 0);
    });

    test('GST off ignores line rates', () {
      final t = InvoiceCalculator.compute(items: items);
      expect(t.totalTax, 0);
      expect(t.total, 13000);
    });
  });

  group('numbering', () {
    test('financial year runs April to March', () {
      expect(InvoiceCalculator.financialYear(DateTime(2026, 3, 31)), '25-26');
      expect(InvoiceCalculator.financialYear(DateTime(2026, 4, 1)), '26-27');
    });

    test('numbers are consecutive per year and at most 16 characters', () {
      final d = DateTime(2026, 11, 2);
      final n = InvoiceCalculator.nextNumber('inv', d, [
        'INV/26-27/0001',
        'INV/26-27/0007',
        'INV/25-26/0042',
        'BILL/26-27/0099',
      ]);
      expect(n, 'INV/26-27/0008');
      expect(InvoiceCalculator.nextNumber('INV', DateTime(2027, 4, 1), [n]),
          'INV/27-28/0001');
      expect(InvoiceCalculator.formatNumber('acme-studio', d, 1).length,
          lessThanOrEqualTo(16));
      expect(InvoiceCalculator.cleanPrefix(''), 'INV');
    });
  });

  group('amount in words', () {
    test('Indian lakh and crore', () {
      expect(InvoiceCalculator.numberInWords(12345678),
          'One Crore Twenty Three Lakh Forty Five Thousand Six Hundred Seventy Eight');
      expect(InvoiceCalculator.numberInWords(100000), 'One Lakh');
      expect(InvoiceCalculator.numberInWords(15), 'Fifteen');
    });

    test('rupees and paise', () {
      expect(InvoiceCalculator.amountInWords(15340),
          'Rupees Fifteen Thousand Three Hundred Forty Only');
      expect(InvoiceCalculator.amountInWords(1001.5),
          'Rupees One Thousand One and Fifty Paise Only');
    });
  });

  group('GSTIN', () {
    test('valid GSTINs pass and give their state', () {
      expect(InvoiceCalculator.isValidGstin('27AAPFU0939F1ZV'), isTrue);
      expect(InvoiceCalculator.isValidGstin('06bzahm6385p6z0'), isTrue);
      expect(InvoiceCalculator.stateCodeOfGstin('27AAPFU0939F1ZV'), '27');
    });

    test('a wrong check digit or shape fails', () {
      expect(InvoiceCalculator.isValidGstin('27AAPFU0939F1ZW'), isFalse);
      expect(InvoiceCalculator.isValidGstin('27AAPFU0939F1Z'), isFalse);
      expect(InvoiceCalculator.isValidGstin('hello'), isFalse);
    });
  });

  group('UPI link', () {
    test('carries the exact amount and invoice number', () {
      final link = UpiLink.build(
        vpa: 'studio@okaxis',
        payeeName: 'Acme Studio',
        amount: 15340,
        note: 'Invoice INV/26-27/0008',
        reference: 'INV/26-27/0008',
      );
      final uri = Uri.parse(link);
      expect(uri.scheme, 'upi');
      expect(uri.queryParameters['pa'], 'studio@okaxis');
      expect(uri.queryParameters['pn'], 'Acme Studio');
      expect(uri.queryParameters['am'], '15340.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tr'], 'INV/26-27/0008');
    });

    test('UPI ID shape', () {
      expect(UpiLink.isValidVpa('studio@okaxis'), isTrue);
      expect(UpiLink.isValidVpa('9876543210@ybl'), isTrue);
      expect(UpiLink.isValidVpa('no-at-sign'), isFalse);
    });
  });

  group('invoice status', () {
    Invoice invoice({
      InvoiceStatus status = InvoiceStatus.sent,
      List<InvoicePayment> payments = const [],
      DateTime? due,
    }) =>
        Invoice(
          id: 'i1',
          number: 'INV/26-27/0001',
          billTo: const BillTo(name: 'Acme'),
          issueDate: DateTime(2026, 11, 1),
          dueDate: due ?? DateTime(2026, 11, 15),
          status: status,
          items: const [InvoiceItem(description: 'Work', rate: 1000)],
          payments: payments,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        );
    final now = DateTime(2026, 11, 10);
    InvoicePayment pay(double a) =>
        InvoicePayment(id: 'p$a', amount: a, date: now);

    test('draft, sent, partly paid, paid, overdue, cancelled', () {
      expect(invoice(status: InvoiceStatus.draft).displayStatus('', now),
          InvoiceDisplayStatus.draft);
      expect(invoice().displayStatus('', now), InvoiceDisplayStatus.sent);
      expect(invoice(payments: [pay(400)]).displayStatus('', now),
          InvoiceDisplayStatus.partiallyPaid);
      expect(invoice(payments: [pay(400), pay(600)]).displayStatus('', now),
          InvoiceDisplayStatus.paid);
      expect(invoice(due: DateTime(2026, 11, 5)).displayStatus('', now),
          InvoiceDisplayStatus.overdue);
      expect(invoice(status: InvoiceStatus.cancelled).displayStatus('', now),
          InvoiceDisplayStatus.cancelled);
      expect(invoice(payments: [pay(400)]).balanceDue(''), 600);
    });

    test('round-trips through Firestore maps and SQLite rows', () {
      final inv = invoice(payments: [pay(250)]);
      expect(Invoice.fromMap(inv.toMap()).toMap(), inv.toMap());
      expect(Invoice.fromRow(inv.toRow()).toMap(), inv.toMap());
    });
  });
}
