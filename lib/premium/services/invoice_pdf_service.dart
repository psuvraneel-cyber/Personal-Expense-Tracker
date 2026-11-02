import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/services/invoice_calculator.dart';
import 'package:pet/premium/services/upi_link.dart';
import 'package:pet/services/export_service.dart';

/// Builds the A4 invoice PDF: business and client details, line items with
/// the GST breakup, amount in words, and a UPI QR code for the balance due.
class InvoicePdfService {
  InvoicePdfService._();

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _date = DateFormat('dd MMM yyyy');
  static const _accent = PdfColor.fromInt(0xFF6D28D9);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _line = PdfColor.fromInt(0xFFE2E8F0);

  /// File name for sharing ("/" isn't allowed in file names).
  static String fileName(Invoice invoice) =>
      'Invoice_${invoice.number.replaceAll('/', '-')}.pdf';

  /// The UPI link printed as a QR code, or null when there's nothing to pay
  /// or no valid UPI ID in the profile.
  static String? paymentLink(Invoice invoice, InvoiceProfile profile) {
    final balance = invoice.balanceDue(profile.stateCode);
    if (balance <= 0 ||
        invoice.status == InvoiceStatus.cancelled ||
        !UpiLink.isValidVpa(profile.upiId)) {
      return null;
    }
    return UpiLink.build(
      vpa: profile.upiId,
      payeeName: profile.businessName,
      amount: balance,
      note: 'Invoice ${invoice.number}',
      reference: invoice.number,
    );
  }

  static Future<Uint8List> build(Invoice invoice, InvoiceProfile profile,
      {DateTime? now}) async {
    final theme = await ExportService.pdfTheme();
    final doc = pw.Document(theme: theme, title: invoice.number);
    final gst = invoice.gstEnabled;
    final totals = invoice.totals(profile.stateCode);
    final interState = invoice.isInterState(profile.stateCode);
    final balance = invoice.balanceDue(profile.stateCode);
    final status =
        invoice.displayStatus(profile.stateCode, now ?? DateTime.now());
    final link = paymentLink(invoice, profile);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('This is a computer-generated invoice.',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
      build: (context) => [
        _header(invoice, profile, gst, status),
        pw.SizedBox(height: 18),
        _parties(invoice, profile, gst),
        pw.SizedBox(height: 18),
        _itemsTable(invoice, totals, gst),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 5,
              child: link == null
                  ? pw.SizedBox()
                  : _payBox(link, balance, profile.upiId),
            ),
            pw.SizedBox(width: 18),
            pw.Expanded(
              flex: 5,
              child: _totalsBox(invoice, totals, gst, interState, balance),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
            'Amount in words: ${InvoiceCalculator.amountInWords(totals.total)}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        if (invoice.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          _labelled('Notes', invoice.notes),
        ],
        if (profile.terms.trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _labelled('Terms', profile.terms),
        ],
        if (gst) ...[
          pw.SizedBox(height: 10),
          pw.Text('Tax payable on reverse charge: No',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ],
        pw.SizedBox(height: 28),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(children: [
            pw.Text('For ${profile.businessName}',
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 28),
            pw.Container(width: 140, height: 0.5, color: _muted),
            pw.SizedBox(height: 3),
            pw.Text('Authorised signatory',
                style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
        ),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _header(Invoice invoice, InvoiceProfile profile, bool gst,
      InvoiceDisplayStatus status) {
    final stamp = switch (status) {
      InvoiceDisplayStatus.paid => ('PAID', const PdfColor.fromInt(0xFF059669)),
      InvoiceDisplayStatus.cancelled => (
          'CANCELLED',
          const PdfColor.fromInt(0xFFDC2626)
        ),
      _ => null,
    };
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(profile.businessName,
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ..._lines([
                profile.address,
                [profile.phone, profile.email]
                    .where((s) => s.isNotEmpty)
                    .join('  ·  '),
                if (gst && profile.gstin.isNotEmpty) 'GSTIN: ${profile.gstin}',
              ]),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(gst ? 'TAX INVOICE' : 'INVOICE',
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _accent)),
            pw.SizedBox(height: 6),
            _kv('Invoice no.', invoice.number),
            _kv('Date', _date.format(invoice.issueDate)),
            _kv('Due', _date.format(invoice.dueDate)),
            if (gst && invoice.placeOfSupply.isNotEmpty)
              _kv('Place of supply',
                  '${kGstStates[invoice.placeOfSupply] ?? ''} (${invoice.placeOfSupply})'),
            if (stamp != null) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: stamp.$2, width: 1.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(stamp.$1,
                    style: pw.TextStyle(
                        color: stamp.$2,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _parties(Invoice invoice, InvoiceProfile profile, bool gst) {
    final b = invoice.billTo;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF8FAFC),
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('BILL TO',
              style: pw.TextStyle(
                  fontSize: 8, color: _muted, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(b.name,
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ..._lines([
            b.address,
            [b.phone, b.email].where((s) => s.isNotEmpty).join('  ·  '),
            if (gst && b.gstin.isNotEmpty) 'GSTIN: ${b.gstin}',
            if (gst && b.stateCode.isNotEmpty)
              'State: ${kGstStates[b.stateCode] ?? ''} (${b.stateCode})',
          ]),
        ],
      ),
    );
  }

  static pw.Widget _itemsTable(
      Invoice invoice, InvoiceTotals totals, bool gst) {
    final headers = [
      '#',
      'Description',
      if (gst) 'HSN/SAC',
      'Qty',
      'Rate',
      if (gst) 'GST',
      'Amount',
    ];
    final rows = [
      for (var i = 0; i < invoice.items.length; i++)
        [
          '${i + 1}',
          invoice.items[i].description,
          if (gst) invoice.items[i].hsnSac,
          '${_qty(invoice.items[i].quantity)} ${invoice.items[i].unit}'.trim(),
          _money.format(invoice.items[i].rate),
          if (gst) '${_qty(invoice.items[i].gstRate)}%',
          _money.format(invoice.items[i].amount),
        ],
    ];
    final right = {
      for (var c = 0; c < headers.length; c++)
        if (c >= headers.length - (gst ? 4 : 3)) c: pw.Alignment.centerRight,
    };
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
          fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _accent),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      cellAlignments: right,
      columnWidths: {1: const pw.FlexColumnWidth(4)},
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.5),
        bottom: pw.BorderSide(color: _line, width: 0.5),
      ),
    );
  }

  static pw.Widget _totalsBox(Invoice invoice, InvoiceTotals t, bool gst,
      bool interState, double balance) {
    final rows = <(String, double, bool)>[
      ('Subtotal', t.subtotal, false),
      if (t.discount > 0) ('Discount', -t.discount, false),
      if (gst) ('Taxable value', t.taxableValue, false),
      if (gst && !interState) ('CGST', t.cgst, false),
      if (gst && !interState) ('SGST', t.sgst, false),
      if (gst && interState) ('IGST', t.igst, false),
      if (t.roundOff != 0) ('Round off', t.roundOff, false),
      ('Total', t.total, true),
      if (invoice.amountPaid > 0) ('Paid', -invoice.amountPaid, false),
      if (invoice.amountPaid > 0) ('Balance due', balance, true),
    ];
    return pw.Column(children: [
      for (final r in rows)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: r.$3
              ? const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: _line)))
              : null,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(r.$1,
                  style: pw.TextStyle(
                      fontSize: r.$3 ? 11 : 9,
                      fontWeight: r.$3 ? pw.FontWeight.bold : null)),
              pw.Text(_money.format(r.$2),
                  style: pw.TextStyle(
                      fontSize: r.$3 ? 11 : 9,
                      fontWeight: r.$3 ? pw.FontWeight.bold : null)),
            ],
          ),
        ),
    ]);
  }

  static pw.Widget _payBox(String link, double balance, String upiId) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: link,
          width: 84,
          height: 84,
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Scan to pay with any UPI app',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(_money.format(balance),
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _accent)),
              pw.SizedBox(height: 3),
              pw.Text('UPI ID: $upiId',
                  style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ],
          ),
        ),
      ]),
    );
  }

  static pw.Widget _labelled(String label, String text) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 8, color: _muted, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
        ],
      );

  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Text('$k: ',
              style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.Text(v,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static List<pw.Widget> _lines(List<String> lines) => [
        for (final l in lines.where((l) => l.trim().isNotEmpty))
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(l,
                style: const pw.TextStyle(fontSize: 9, color: _muted)),
          ),
      ];

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}
