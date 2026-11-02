import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/utils/amount_input.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/screens/invoice_editor_screen.dart';
import 'package:pet/premium/services/invoice_pdf_service.dart';
import 'package:pet/services/export_service.dart';

/// One invoice: amounts, payments, and what can be done with it.
class InvoiceDetailScreen extends StatelessWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _date = DateFormat('dd MMM yyyy');

  static Color statusColor(InvoiceDisplayStatus s) => switch (s) {
        InvoiceDisplayStatus.paid => AppTheme.incomeGreen,
        InvoiceDisplayStatus.overdue => AppTheme.expenseRed,
        InvoiceDisplayStatus.partiallyPaid => AppTheme.warningYellow,
        InvoiceDisplayStatus.sent => AppTheme.accentPurple,
        InvoiceDisplayStatus.draft ||
        InvoiceDisplayStatus.cancelled =>
          AppTheme.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<InvoiceProvider>();
    final inv = provider.invoiceById(invoiceId);
    if (inv == null) {
      return const Scaffold(body: Center(child: Text('Invoice not found')));
    }
    final status = provider.statusOf(inv);
    final totals = provider.totalsOf(inv);
    final balance = provider.balanceOf(inv);
    final canEdit =
        inv.status != InvoiceStatus.cancelled && inv.payments.isEmpty;
    final canPay = inv.status != InvoiceStatus.cancelled && balance > 0;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: Text(inv.number),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => InvoiceEditorScreen(invoice: inv)),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, v, inv),
            itemBuilder: (_) => [
              if (inv.status == InvoiceStatus.draft)
                const PopupMenuItem(
                    value: 'delete', child: Text('Delete draft'))
              else if (inv.status != InvoiceStatus.cancelled &&
                  status != InvoiceDisplayStatus.paid)
                const PopupMenuItem(
                    value: 'cancel', child: Text('Cancel invoice')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Row(children: [
            Chip(
              label: Text(status.label),
              labelStyle: TextStyle(
                  color: statusColor(status), fontWeight: FontWeight.w600),
              side: BorderSide(color: statusColor(status).withAlpha(90)),
              backgroundColor: statusColor(status).withAlpha(25),
            ),
            const Spacer(),
            Text('Due ${_date.format(inv.dueDate)}'),
          ]),
          const SizedBox(height: 8),
          Text(inv.billTo.name, style: Theme.of(context).textTheme.titleLarge),
          Text('Issued ${_date.format(inv.issueDate)}'
              '${inv.gstEnabled ? ' · Tax invoice' : ''}'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _row(context, 'Total', totals.total, bold: true),
                if (totals.totalTax > 0)
                  _row(context, 'of which GST', totals.totalTax),
                _row(context, 'Paid', inv.amountPaid),
                const Divider(),
                _row(context, 'Balance due', balance,
                    bold: true,
                    color: balance > 0 ? null : AppTheme.incomeGreen),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleSmall),
          for (final item in inv.items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(item.description),
              trailing: Text(_money.format(item.amount)),
            ),
          if (inv.payments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Payments', style: Theme.of(context).textTheme.titleSmall),
            for (final p in inv.payments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.check_circle_rounded,
                    color: AppTheme.incomeGreen),
                title: Text(_money.format(p.amount)),
                subtitle: Text('${_date.format(p.date)} · ${p.method}'
                    '${p.note.isEmpty ? '' : ' · ${p.note}'}'),
                trailing: IconButton(
                  tooltip: 'Remove payment',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => provider.removePayment(inv, p.id),
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _share(context, inv),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share PDF'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: inv.status == InvoiceStatus.draft
                  ? FilledButton(
                      onPressed: () => provider.markSent(inv),
                      child: const Text('Mark as sent'),
                    )
                  : FilledButton(
                      onPressed: canPay
                          ? () => _recordPayment(context, inv, balance)
                          : null,
                      child: const Text('Record payment'),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, double v,
          {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(_money.format(v),
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : null,
                  color: color,
                  fontSize: bold ? 16 : null)),
        ]),
      );

  Future<void> _share(BuildContext context, Invoice inv) async {
    final provider = context.read<InvoiceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await InvoicePdfService.build(inv, provider.profile);
      await ExportService.instance.shareBytes(
          InvoicePdfService.fileName(inv), bytes, 'Invoice ${inv.number}');
      // Sharing a draft means it's going out.
      if (inv.status == InvoiceStatus.draft) await provider.markSent(inv);
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't create the PDF")));
    }
  }

  Future<void> _recordPayment(
      BuildContext context, Invoice inv, double balance) async {
    final provider = context.read<InvoiceProvider>();
    final result = await showDialog<(double, String, DateTime)>(
      context: context,
      builder: (_) => _PaymentDialog(balance: balance),
    );
    if (result == null) return;
    await provider.recordPayment(inv,
        amount: result.$1, method: result.$2, date: result.$3);
  }

  Future<void> _menu(BuildContext context, String action, Invoice inv) async {
    final provider = context.read<InvoiceProvider>();
    final navigator = Navigator.of(context);
    if (action == 'delete') {
      await provider.deleteDraft(inv);
      navigator.pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this invoice?'),
        content: const Text(
            'It stays in your records marked Cancelled, so invoice numbers stay in order.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel invoice')),
        ],
      ),
    );
    if (ok == true) await provider.cancel(inv);
  }
}

/// Amount, method and date of a payment. Owns its controller.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.balance});
  final double balance;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount =
      TextEditingController(text: AmountInput.format(widget.balance));
  String _method = 'UPI';
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record payment'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: AmountInput.formatters,
          decoration: InputDecoration(
              prefixText: '₹ ', labelText: 'Amount', errorText: _error),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _method,
          decoration: const InputDecoration(labelText: 'Paid by'),
          items: [
            for (final m in ['UPI', 'Cash', 'Bank transfer', 'Cheque', 'Other'])
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (v) => setState(() => _method = v ?? _method),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Date'),
          trailing: Text(DateFormat('dd MMM yyyy').format(_date)),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (d != null) setState(() => _date = d);
          },
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = AmountInput.parse(_amount.text);
            if (v == null || v <= 0) {
              setState(() => _error = 'Enter an amount');
              return;
            }
            Navigator.pop(context, (v, _method, _date));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
