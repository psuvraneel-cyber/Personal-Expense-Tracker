import 'dart:io';
import 'package:pet/core/utils/app_logger.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';

/// Service for exporting transactions to CSV or PDF files.
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _amountFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  // ── CSV Export ──────────────────────────────────────────────────────

  /// Export transactions to CSV and open the share sheet.
  Future<void> exportToCsv(
    List<TransactionRecord> transactions, {
    DateTime? startDate,
    DateTime? endDate,
    Map<String, String> categoryNames = const {},
  }) async {
    final filtered = _filterByDate(transactions, startDate, endDate);
    final rows = <List<String>>[
      ['Date', 'Type', 'Amount', 'Category', 'Merchant', 'Payment Method', 'Note'],
      ...filtered.map(
        (t) {
          final catName = categoryNames[t.categoryId] ?? 'Uncategorized';
          return [
            _dateFormat.format(t.date),
            t.type.toJson(),
            t.amount.toStringAsFixed(2),
            catName,
            t.merchantName ?? '',
            t.paymentMethod.toJson(),
            t.note,
          ];
        },
      ),
    ];

    // Simple CSV generation — escape fields containing commas/quotes
    final csvString = rows
        .map((row) {
          return row
              .map((field) {
                if (field.contains(',') ||
                    field.contains('"') ||
                    field.contains('\n')) {
                  return '"${field.replaceAll('"', '""')}"';
                }
                return field;
              })
              .join(',');
        })
        .join('\n');
    final file = await _writeTempFile(
      'pet_transactions_${_fileTimestamp()}.csv',
      csvString,
    );
    await _shareFile(file, 'PET Transactions (CSV)');
  }

  // ── PDF Export ──────────────────────────────────────────────────────

  /// Export transactions to a formatted PDF and open the share sheet.
  Future<void> exportToPdf(
    List<TransactionRecord> transactions, {
    DateTime? startDate,
    DateTime? endDate,
    Map<String, String> categoryNames = const {},
  }) async {
    final filtered = _filterByDate(transactions, startDate, endDate);

    // Summary stats
    double totalIncome = 0;
    double totalExpense = 0;
    for (final t in filtered) {
      if (t.type == TransactionType.income) {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }
    }

    final pdf = pw.Document();
    final dateRange = startDate != null && endDate != null
        ? '${_dateFormat.format(startDate)} – ${_dateFormat.format(endDate)}'
        : 'All time';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'P.E.T — Transaction Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(dateRange, style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _pdfStat('Income', _amountFormat.format(totalIncome)),
                _pdfStat('Expense', _amountFormat.format(totalExpense)),
                _pdfStat(
                  'Savings',
                  _amountFormat.format(totalIncome - totalExpense),
                ),
              ],
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFEDE9FE),
            ),
            cellPadding: const pw.EdgeInsets.all(6),
            headers: ['Date', 'Type', 'Amount', 'Category', 'Merchant', 'Payment', 'Note'],
            data: filtered
                .map(
                  (t) {
                    final catName = categoryNames[t.categoryId] ?? 'Uncategorized';
                    return [
                      _dateFormat.format(t.date),
                      t.type.toString().split('.').last,
                      _amountFormat.format(t.amount),
                      catName,
                      t.merchantName ?? '',
                      t.paymentMethod.toString().split('.').last,
                      t.note,
                    ];
                  },
                )
                .toList(),
          ),
        ],
      ),
    );

    final pdfBytes = await pdf.save();
    final file = await _writeTempFile(
      'pet_transactions_${_fileTimestamp()}.pdf',
      null,
      bytes: pdfBytes,
    );
    await _shareFile(file, 'PET Transactions (PDF)');
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  List<TransactionRecord> _filterByDate(
    List<TransactionRecord> list,
    DateTime? start,
    DateTime? end,
  ) {
    if (start == null && end == null) return list;
    return list.where((t) {
      if (start != null && t.date.isBefore(start)) return false;
      if (end != null && t.date.isAfter(end)) return false;
      return true;
    }).toList();
  }

  pw.Widget _pdfStat(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  Future<File> _writeTempFile(
    String name,
    String? text, {
    List<int>? bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(text!);
    }
    AppLogger.debug('[Export] Wrote temp file for sharing');
    return file;
  }

  String _fileTimestamp() =>
      DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

  Future<void> _shareFile(File file, String subject) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }
}
