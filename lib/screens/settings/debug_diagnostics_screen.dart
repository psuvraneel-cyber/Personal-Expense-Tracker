import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/services/debug_diagnostics_service.dart';

/// Debug-only, read-only diagnostics export. It contains aggregate counts and
/// short digests; it never displays raw message text or full identifiers.
class DebugDiagnosticsScreen extends StatefulWidget {
  const DebugDiagnosticsScreen({super.key});

  @override
  State<DebugDiagnosticsScreen> createState() => _DebugDiagnosticsScreenState();
}

class _DebugDiagnosticsScreenState extends State<DebugDiagnosticsScreen> {
  late Future<String> _report;

  @override
  void initState() {
    super.initState();
    _report = _loadReport();
  }

  Future<String> _loadReport() async {
    final smsProvider = context.read<SmsTransactionProvider>();
    final sms = await smsProvider.getDiagnostics();
    final reconciliation = await smsProvider.getReconciliationDiagnostics();
    final service = DebugDiagnosticsService();
    final report = await service.collect(
      smsService: sms,
      reconciliation: reconciliation,
    );
    report['duplicateCandidate'] = await service.duplicateCandidateReport();
    report['timestampRepairDryRun'] = await service.timestampRepairDryRun();
    return const JsonEncoder.withIndent('  ').convert(report);
  }

  void _refresh() => setState(() => _report = _loadReport());

  Future<void> _copy(String report) async {
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingestion Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Diagnostics unavailable: ${snapshot.error}'));
          }
          final report = snapshot.data ?? '{}';
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Read-only privacy-safe counts and candidate analysis. '
                        'No scan or database mutation is performed.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _copy(report),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: SelectableText(
                    report,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
