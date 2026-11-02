import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/screens/invoice_profile_screen.dart';
import 'package:pet/premium/services/invoice_calculator.dart';
import 'package:pet/premium/services/upi_link.dart';

/// People and businesses the user invoices.
class InvoiceClientsScreen extends StatelessWidget {
  const InvoiceClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<InvoiceProvider>();
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Clients'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editClient(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add client'),
      ),
      body: provider.clients.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No clients yet. Add the people and businesses you bill, '
                  'and their details fill in on every invoice.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: provider.clients.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = provider.clients[i];
                final sub = [
                  c.phone,
                  c.email,
                  if (c.gstin.isNotEmpty) 'GSTIN ${c.gstin}'
                ].where((s) => s.isNotEmpty).join(' · ');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.accentPurple.withAlpha(40),
                    child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()),
                  ),
                  title: Text(c.name),
                  subtitle: sub.isEmpty ? null : Text(sub),
                  onTap: () => editClient(context, client: c),
                );
              },
            ),
    );
  }

  /// Opens the client form; returns the saved client (or null).
  static Future<InvoiceClient?> editClient(BuildContext context,
      {InvoiceClient? client}) {
    return Navigator.push<InvoiceClient>(
      context,
      MaterialPageRoute(builder: (_) => ClientEditorScreen(client: client)),
    );
  }
}

class ClientEditorScreen extends StatefulWidget {
  const ClientEditorScreen({super.key, this.client});

  final InvoiceClient? client;

  @override
  State<ClientEditorScreen> createState() => _ClientEditorScreenState();
}

class _ClientEditorScreenState extends State<ClientEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final InvoiceClient? _c = widget.client;
  late final _name = TextEditingController(text: _c?.name ?? '');
  late final _address = TextEditingController(text: _c?.address ?? '');
  late final _phone = TextEditingController(text: _c?.phone ?? '');
  late final _email = TextEditingController(text: _c?.email ?? '');
  late final _gstin = TextEditingController(text: _c?.gstin ?? '');
  late final _upi = TextEditingController(text: _c?.upiId ?? '');
  late String _state = _c?.stateCode ?? '';

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email, _gstin, _upi]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final provider = context.read<InvoiceProvider>();
    final gstin = _gstin.text.trim().toUpperCase();
    final base = _c ?? provider.newClient(_name.text);
    final saved = await provider.saveClient(base.copyWith(
      name: _name.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      gstin: gstin,
      stateCode: gstin.isNotEmpty
          ? InvoiceCalculator.stateCodeOfGstin(gstin) ?? _state
          : _state,
      upiId: _upi.text.trim(),
    ));
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete client?'),
        content: const Text('Invoices already issued keep their details.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<InvoiceProvider>().deleteClient(_c!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: Text(_c == null ? 'New client' : 'Edit client'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          if (_c != null)
            IconButton(
              tooltip: 'Delete client',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _f(_name, 'Name *',
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            _f(_address, 'Address', maxLines: 3),
            _f(_phone, 'Phone (for WhatsApp)', keyboard: TextInputType.phone),
            _f(_email, 'Email', keyboard: TextInputType.emailAddress),
            _f(_gstin, 'GSTIN (if registered)',
                caps: TextCapitalization.characters,
                validator: (v) => (v ?? '').trim().isEmpty ||
                        InvoiceCalculator.isValidGstin(v!)
                    ? null
                    : 'This GSTIN isn\'t valid'),
            GstStatePicker(
              value: _state,
              label: 'State (decides CGST+SGST or IGST)',
              onChanged: (v) => setState(() => _state = v),
            ),
            const SizedBox(height: 12),
            _f(_upi, 'UPI ID they pay from (optional)',
                hint: 'Helps P.E.T recognise their payment',
                validator: (v) =>
                    (v ?? '').trim().isEmpty || UpiLink.isValidVpa(v!.trim())
                        ? null
                        : 'Enter a UPI ID like name@bank'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save client')),
          ],
        ),
      ),
    );
  }

  Widget _f(
    TextEditingController c,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.words,
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
