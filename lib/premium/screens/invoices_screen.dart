import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/screens/invoice_clients_screen.dart';
import 'package:pet/premium/screens/invoice_detail_screen.dart';
import 'package:pet/premium/screens/invoice_editor_screen.dart';
import 'package:pet/premium/screens/invoice_profile_screen.dart';
import 'package:pet/premium/screens/purchase_screen.dart';

enum _Filter { all, unpaid, overdue, paid, drafts }

/// Invoices the user sends: what's owed, what's overdue, what was paid.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InvoiceProvider>().load();
    });
  }

  Future<void> _newInvoice() async {
    final provider = context.read<InvoiceProvider>();
    final navigator = Navigator.of(context);
    if (!provider.profile.isSetUp) {
      final saved = await navigator.push<bool>(
          MaterialPageRoute(builder: (_) => const InvoiceProfileScreen()));
      if (saved != true) return;
    }
    if (!mounted) return;
    if (!provider.canCreateInvoice(
        isPremium: context.read<PremiumProvider>().isPremium)) {
      navigator.push(MaterialPageRoute(
          builder: (_) => const PurchaseScreen(source: 'Invoices')));
      return;
    }
    final saved = await navigator.push<Invoice>(
        MaterialPageRoute(builder: (_) => const InvoiceEditorScreen()));
    if (saved != null) {
      navigator.push(MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: saved.id)));
    }
  }

  /// Payments spotted on this phone that need a yes or no.
  Widget _confirmBanner(BuildContext context, InvoiceProvider provider) {
    final pending = provider.pendingSuggestions;
    final ids = pending.map((s) => s.transactionId).toSet();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: ListTile(
          leading:
              const Icon(Icons.payments_rounded, color: AppTheme.accentPurple),
          title: Text(ids.length == 1
              ? '1 payment to confirm'
              : '${ids.length} payments to confirm'),
          subtitle: const Text('Money came in that may be for an invoice'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  InvoiceDetailScreen(invoiceId: pending.first.invoiceId),
            ),
          ),
        ),
      ),
    );
  }

  bool _matches(InvoiceProvider p, Invoice inv) {
    final s = p.statusOf(inv);
    return switch (_filter) {
      _Filter.all => true,
      _Filter.unpaid => s == InvoiceDisplayStatus.sent ||
          s == InvoiceDisplayStatus.partiallyPaid ||
          s == InvoiceDisplayStatus.overdue,
      _Filter.overdue => s == InvoiceDisplayStatus.overdue,
      _Filter.paid => s == InvoiceDisplayStatus.paid,
      _Filter.drafts => s == InvoiceDisplayStatus.draft,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<InvoiceProvider>();
    final isPremium = context.watch<PremiumProvider>().isPremium;
    final shown =
        provider.invoices.where((i) => _matches(provider, i)).toList();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Invoices'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          IconButton(
            tooltip: 'Clients',
            icon: const Icon(Icons.people_alt_rounded),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const InvoiceClientsScreen())),
          ),
          IconButton(
            tooltip: 'Business details',
            icon: const Icon(Icons.storefront_rounded),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const InvoiceProfileScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newInvoice,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New invoice'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (!provider.profile.isSetUp) _setupCard(context, isDark),
          if (provider.profile.isSetUp) _summary(context, provider, isDark),
          if (!isPremium)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Free: ${(InvoiceProvider.freeInvoiceLimit - provider.issuedCount).clamp(0, InvoiceProvider.freeInvoiceLimit)} '
                'of ${InvoiceProvider.freeInvoiceLimit} invoices left. Premium is unlimited.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (provider.pendingSuggestions.isNotEmpty)
            _confirmBanner(context, provider),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (f) {
                      _Filter.all => 'All',
                      _Filter.unpaid => 'Unpaid',
                      _Filter.overdue => 'Overdue',
                      _Filter.paid => 'Paid',
                      _Filter.drafts => 'Drafts',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                provider.invoices.isEmpty
                    ? 'No invoices yet. Tap New invoice to bill a client; '
                        'they can pay by scanning the UPI QR on it.'
                    : 'Nothing here.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final inv in shown) _tile(context, provider, inv, isDark),
        ],
      ),
    );
  }

  Widget _setupCard(BuildContext context, bool isDark) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const Icon(Icons.storefront_rounded,
              color: AppTheme.accentPurple),
          title: const Text('Set up your business details'),
          subtitle: const Text(
              'Your name, UPI ID and (optionally) GSTIN, printed on every invoice.'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const InvoiceProfileScreen())),
        ),
      );

  Widget _summary(BuildContext context, InvoiceProvider p, bool isDark) {
    final s = p.summary;
    Widget stat(String label, String value, Color color) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          ]),
        );
    final agingTotal = s.aging.fold(0.0, (a, b) => a + b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            stat('Outstanding', _money.format(s.outstanding),
                AppTheme.accentPurple),
            stat(
                'Overdue (${s.overdueCount})',
                _money.format(s.overdueAmount),
                s.overdueCount > 0
                    ? AppTheme.expenseRed
                    : AppTheme.textTertiary),
            stat('Paid this month', _money.format(s.paidThisMonth),
                AppTheme.incomeGreen),
          ]),
          if (agingTotal > 0) ...[
            const SizedBox(height: 12),
            Text('How long unpaid',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(children: [
                for (final (i, v) in s.aging.indexed)
                  if (v > 0)
                    Expanded(
                      flex: (v / agingTotal * 1000).round().clamp(1, 1000),
                      child: Container(
                        height: 8,
                        color: [
                          AppTheme.accentPurple,
                          AppTheme.warningYellow,
                          AppTheme.expenseRed
                        ][i],
                      ),
                    ),
              ]),
            ),
            const SizedBox(height: 4),
            Text(
              '0–30 days ${_money.format(s.aging[0])} · 31–60 ${_money.format(s.aging[1])} · '
              '60+ ${_money.format(s.aging[2])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }

  Widget _tile(
      BuildContext context, InvoiceProvider p, Invoice inv, bool isDark) {
    final status = p.statusOf(inv);
    final color = InvoiceDetailScreen.statusColor(status);
    final total = p.totalsOf(inv).total;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => InvoiceDetailScreen(invoiceId: inv.id))),
        title: Text(inv.billTo.name.isEmpty ? 'No client' : inv.billTo.name),
        subtitle: Text(
            '${inv.number} · due ${DateFormat('d MMM').format(inv.dueDate)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money.format(total),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(status.label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
