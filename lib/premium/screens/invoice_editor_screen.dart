import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/utils/amount_input.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/screens/invoice_clients_screen.dart';
import 'package:pet/premium/screens/invoice_profile_screen.dart';
import 'package:pet/premium/services/invoice_calculator.dart';

/// Create or edit an invoice. Pops with the saved invoice.
class InvoiceEditorScreen extends StatefulWidget {
  const InvoiceEditorScreen({super.key, this.invoice});

  /// Null for a new invoice.
  final Invoice? invoice;

  @override
  State<InvoiceEditorScreen> createState() => _InvoiceEditorScreenState();
}

class _InvoiceEditorScreenState extends State<InvoiceEditorScreen> {
  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _date = DateFormat('dd MMM yyyy');

  late Invoice _inv =
      widget.invoice ?? context.read<InvoiceProvider>().newDraft();
  late final _discount = TextEditingController(
      text: _inv.discount > 0 ? AmountInput.format(_inv.discount) : '');
  late final _notes = TextEditingController(text: _inv.notes);
  bool _saving = false;

  @override
  void dispose() {
    _discount.dispose();
    _notes.dispose();
    super.dispose();
  }

  InvoiceProfile get _profile => context.read<InvoiceProvider>().profile;

  void _pickClient(InvoiceClient c) => setState(() {
        _inv = _inv.copyWith(
          clientId: c.id,
          billTo: c.toBillTo(),
          placeOfSupply:
              c.stateCode.isNotEmpty ? c.stateCode : _profile.stateCode,
        );
      });

  Future<void> _newClient() async {
    final c = await InvoiceClientsScreen.editClient(context);
    if (c != null) _pickClient(c);
  }

  Future<void> _pickDate({required bool due}) async {
    final initial = due ? _inv.dueDate : _inv.issueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _inv = _inv.copyWith(dueDate: picked);
      } else {
        final gap = _inv.dueDate.difference(_inv.issueDate);
        _inv = _inv.copyWith(
          issueDate: picked,
          dueDate: picked.add(gap.isNegative ? Duration.zero : gap),
          // A new invoice's number follows the year of its date.
          number: widget.invoice == null
              ? context.read<InvoiceProvider>().nextNumber(picked)
              : null,
        );
      }
    });
  }

  Future<void> _editItem([int? index]) async {
    final item = await showModalBottomSheet<InvoiceItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemSheet(
        item: index == null ? null : _inv.items[index],
        gst: _inv.gstEnabled,
        defaultRate: _profile.defaultGstRate,
      ),
    );
    if (item == null) return;
    setState(() {
      final items = List.of(_inv.items);
      index == null ? items.add(item) : items[index] = item;
      _inv = _inv.copyWith(items: items);
    });
  }

  Future<void> _save({required bool send}) async {
    final messenger = ScaffoldMessenger.of(context);
    String? problem;
    if (_inv.billTo.name.trim().isEmpty) {
      problem = 'Choose who the invoice is for';
    }
    if (_inv.items.isEmpty) problem ??= 'Add at least one item';
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<InvoiceProvider>();
    var inv = _inv.copyWith(
      discount: AmountInput.parse(_discount.text) ?? 0,
      notes: _notes.text.trim(),
    );
    if (send && inv.status == InvoiceStatus.draft) {
      inv = inv.copyWith(status: InvoiceStatus.sent);
    }
    final saved = await provider.saveInvoice(inv);
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<InvoiceProvider>();
    final totals = InvoiceCalculator.compute(
      items: _inv.items,
      discount: AmountInput.parse(_discount.text) ?? 0,
      gstEnabled: _inv.gstEnabled,
      interState: _inv.isInterState(provider.profile.stateCode),
    );
    final isNew = widget.invoice == null;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: Text(isNew ? 'New invoice' : 'Edit ${_inv.number}'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          Text(_inv.number, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _section('Bill to'),
          DropdownButtonFormField<String>(
            key: ValueKey(provider.clients.length),
            initialValue: provider.clientById(_inv.clientId)?.id,
            isExpanded: true,
            hint: const Text('Choose a client'),
            items: [
              for (final c in provider.clients)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (id) {
              final c = provider.clientById(id);
              if (c != null) _pickClient(c);
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _newClient,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('New client'),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _dateTile('Invoice date', _inv.issueDate,
                    () => _pickDate(due: false))),
            const SizedBox(width: 12),
            Expanded(
                child: _dateTile(
                    'Due date', _inv.dueDate, () => _pickDate(due: true))),
          ]),
          if (provider.profile.gstEnabled) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('GST tax invoice'),
              value: _inv.gstEnabled,
              onChanged: (v) =>
                  setState(() => _inv = _inv.copyWith(gstEnabled: v)),
            ),
            if (_inv.gstEnabled)
              GstStatePicker(
                value: _inv.placeOfSupply,
                label: 'Place of supply',
                onChanged: (v) =>
                    setState(() => _inv = _inv.copyWith(placeOfSupply: v)),
              ),
          ],
          const SizedBox(height: 16),
          _section('Items'),
          for (var i = 0; i < _inv.items.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_inv.items[i].description),
                subtitle: Text(
                  '${_fmtQty(_inv.items[i].quantity)} ${_inv.items[i].unit} × '
                  '${_money.format(_inv.items[i].rate)}'
                  '${_inv.gstEnabled ? ' · GST ${_fmtQty(_inv.items[i].gstRate)}%' : ''}',
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_money.format(_inv.items[i].amount)),
                  IconButton(
                    tooltip: 'Remove item',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _inv =
                        _inv.copyWith(items: List.of(_inv.items)..removeAt(i))),
                  ),
                ]),
                onTap: () => _editItem(i),
              ),
            ),
          if (_inv.items.length < Invoice.maxItems)
            OutlinedButton.icon(
              onPressed: () => _editItem(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add item'),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _discount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: AmountInput.formatters,
            decoration: const InputDecoration(
                labelText: 'Discount (₹)', prefixText: '₹ '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Notes for the client',
                hintText: 'e.g. Thank you for your business'),
          ),
          const SizedBox(height: 16),
          _TotalsCard(
              totals: totals,
              gst: _inv.gstEnabled,
              interState: _inv.isInterState(provider.profile.stateCode)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            if (_inv.status == InvoiceStatus.draft) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(send: false),
                  child: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : () => _save(send: true),
                child: Text(_inv.status == InvoiceStatus.draft
                    ? 'Save & issue'
                    : 'Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _dateTile(String label, DateTime d, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(_date.format(d)),
        ),
      );
}

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

class _TotalsCard extends StatelessWidget {
  const _TotalsCard(
      {required this.totals, required this.gst, required this.interState});

  final InvoiceTotals totals;
  final bool gst;
  final bool interState;

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final rows = <(String, double)>[
      ('Subtotal', t.subtotal),
      if (t.discount > 0) ('Discount', -t.discount),
      if (gst && !interState) ('CGST', t.cgst),
      if (gst && !interState) ('SGST', t.sgst),
      if (gst && interState) ('IGST', t.igst),
      if (t.roundOff != 0) ('Round off', t.roundOff),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: Text(r.$1)),
                Text(_money.format(r.$2)),
              ]),
            ),
          const Divider(),
          Row(children: [
            Expanded(
                child: Text('Total',
                    style: Theme.of(context).textTheme.titleMedium)),
            Text(_money.format(t.total),
                key: const Key('invoice_total'),
                style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(InvoiceCalculator.amountInWords(t.total),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
}

/// Adds or edits one line. Owns its controllers (disposed with the sheet).
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({this.item, required this.gst, required this.defaultRate});

  final InvoiceItem? item;
  final bool gst;
  final double defaultRate;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _form = GlobalKey<FormState>();
  late final _desc =
      TextEditingController(text: widget.item?.description ?? '');
  late final _qty =
      TextEditingController(text: _fmtQty(widget.item?.quantity ?? 1));
  late final _unit = TextEditingController(text: widget.item?.unit ?? '');
  late final _rate = TextEditingController(
      text: widget.item == null ? '' : AmountInput.format(widget.item!.rate));
  late final _hsn = TextEditingController(text: widget.item?.hsnSac ?? '');
  late double _gstRate = widget.item?.gstRate ?? widget.defaultRate;

  @override
  void dispose() {
    for (final c in [_desc, _qty, _unit, _rate, _hsn]) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      InvoiceItem(
        description: _desc.text.trim(),
        quantity: double.parse(_qty.text.trim()),
        unit: _unit.text.trim(),
        rate: AmountInput.parse(_rate.text) ?? 0,
        hsnSac: _hsn.text.trim(),
        gstRate: widget.gst ? _gstRate : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.item == null ? 'Add item' : 'Edit item',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            controller: _desc,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description *'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _qty,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Qty'),
                validator: (v) {
                  final q = double.tryParse((v ?? '').trim());
                  return q == null || q <= 0 ? 'Enter a quantity' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _unit,
                decoration: const InputDecoration(
                    labelText: 'Unit', hintText: 'hrs, pcs'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _rate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: AmountInput.formatters,
                decoration: const InputDecoration(labelText: 'Rate (₹) *'),
                validator: (v) =>
                    AmountInput.parse(v ?? '') == null ? 'Enter a rate' : null,
              ),
            ),
          ]),
          if (widget.gst) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _hsn,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'HSN/SAC'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<double>(
                  initialValue: InvoiceCalculator.gstRates.contains(_gstRate)
                      ? _gstRate
                      : 18,
                  decoration: const InputDecoration(labelText: 'GST'),
                  items: [
                    for (final r in InvoiceCalculator.gstRates)
                      DropdownMenuItem(
                          value: r, child: Text('${r.toStringAsFixed(0)}%')),
                  ],
                  onChanged: (v) => setState(() => _gstRate = v ?? _gstRate),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _done, child: const Text('Done')),
          ),
        ]),
      ),
    );
  }
}
