import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/services/invoice_calculator.dart';
import 'package:pet/premium/services/upi_link.dart';

/// Business details printed on every invoice, set up once.
class InvoiceProfileScreen extends StatefulWidget {
  const InvoiceProfileScreen({super.key});

  @override
  State<InvoiceProfileScreen> createState() => _InvoiceProfileScreenState();
}

class _InvoiceProfileScreenState extends State<InvoiceProfileScreen> {
  final _form = GlobalKey<FormState>();
  late InvoiceProfile _p = context.read<InvoiceProvider>().profile;
  late final _name = TextEditingController(text: _p.businessName);
  late final _address = TextEditingController(text: _p.address);
  late final _phone = TextEditingController(text: _p.phone);
  late final _email = TextEditingController(text: _p.email);
  late final _upi = TextEditingController(text: _p.upiId);
  late final _gstin = TextEditingController(text: _p.gstin);
  late final _prefix = TextEditingController(text: _p.prefix);
  late final _terms = TextEditingController(text: _p.terms);

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _phone,
      _email,
      _upi,
      _gstin,
      _prefix,
      _terms
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final gstin = _gstin.text.trim().toUpperCase();
    await context.read<InvoiceProvider>().saveProfile(_p.copyWith(
          businessName: _name.text.trim(),
          address: _address.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          upiId: _upi.text.trim(),
          gstin: gstin,
          // A GSTIN starts with the state code.
          stateCode: _p.gstEnabled && gstin.isNotEmpty
              ? InvoiceCalculator.stateCodeOfGstin(gstin)
              : _p.stateCode,
          prefix: InvoiceCalculator.cleanPrefix(_prefix.text),
          terms: _terms.text.trim(),
        ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Business details'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const _Hint('Printed on every invoice you send.'),
            _field(_name, 'Business or your name *',
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            _field(_address, 'Address', maxLines: 3),
            _field(_phone, 'Phone', keyboard: TextInputType.phone),
            _field(_email, 'Email', keyboard: TextInputType.emailAddress),
            _field(_upi, 'UPI ID (for the payment QR)',
                hint: 'yourname@okaxis',
                validator: (v) =>
                    (v ?? '').trim().isEmpty || UpiLink.isValidVpa(v!.trim())
                        ? null
                        : 'Enter a UPI ID like name@bank'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I am registered for GST'),
              subtitle: const Text('Adds GSTIN, HSN/SAC and tax to invoices'),
              value: _p.gstEnabled,
              onChanged: (v) => setState(() => _p = _p.copyWith(gstEnabled: v)),
            ),
            if (_p.gstEnabled) ...[
              _field(_gstin, 'GSTIN',
                  caps: TextCapitalization.characters,
                  validator: (v) => (v ?? '').trim().isEmpty ||
                          InvoiceCalculator.isValidGstin(v!)
                      ? null
                      : 'This GSTIN isn\'t valid (check the 15 characters)'),
              DropdownButtonFormField<double>(
                initialValue:
                    InvoiceCalculator.gstRates.contains(_p.defaultGstRate)
                        ? _p.defaultGstRate
                        : 18,
                decoration: const InputDecoration(labelText: 'Usual GST rate'),
                items: [
                  for (final r in InvoiceCalculator.gstRates)
                    DropdownMenuItem(
                        value: r, child: Text('${r.toStringAsFixed(0)}%')),
                ],
                onChanged: (v) =>
                    setState(() => _p = _p.copyWith(defaultGstRate: v)),
              ),
              const SizedBox(height: 12),
            ],
            GstStatePicker(
              value: _p.stateCode,
              label: 'Your state',
              onChanged: (v) => setState(() => _p = _p.copyWith(stateCode: v)),
            ),
            const SizedBox(height: 12),
            _field(_prefix, 'Invoice number prefix',
                hint: 'INV', caps: TextCapitalization.characters),
            DropdownButtonFormField<int>(
              initialValue:
                  [0, 7, 15, 30, 45, 60].contains(_p.dueDays) ? _p.dueDays : 15,
              decoration: const InputDecoration(labelText: 'Payment due'),
              items: [
                for (final d in [0, 7, 15, 30, 45, 60])
                  DropdownMenuItem(
                      value: d,
                      child: Text(d == 0 ? 'On receipt' : 'In $d days')),
              ],
              onChanged: (v) => setState(() => _p = _p.copyWith(dueDays: v)),
            ),
            const SizedBox(height: 12),
            _field(_terms, 'Terms (printed at the bottom)', maxLines: 3),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.none,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          textCapitalization: caps,
          validator: validator,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// GST state picker (also decides CGST+SGST vs IGST).
class GstStatePicker extends StatelessWidget {
  const GstStatePicker({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final String value;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: kGstStates.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in kGstStates.entries)
            DropdownMenuItem(
                value: e.key, child: Text('${e.value} (${e.key})')),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      );
}
