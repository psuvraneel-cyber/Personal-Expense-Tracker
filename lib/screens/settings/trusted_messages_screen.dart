import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/services/trusted_template_service.dart';

/// Message types the user chose to always add ("Always add messages like
/// this" in Pending Review). Removing one sends its messages back to review.
class TrustedMessagesScreen extends StatefulWidget {
  const TrustedMessagesScreen({super.key, this.service});

  /// For tests; defaults to the app database.
  final TrustedTemplateService? service;

  @override
  State<TrustedMessagesScreen> createState() => _TrustedMessagesScreenState();
}

class _TrustedMessagesScreenState extends State<TrustedMessagesScreen> {
  late final TrustedTemplateService _service =
      widget.service ?? TrustedTemplateService();
  late Future<List<TrustedTemplate>> _templates = _service.all();

  Future<void> _remove(TrustedTemplate t) async {
    await _service.remove(t.templateHash);
    if (!mounted) return;
    // Block body: an arrow would return the Future, which setState rejects.
    setState(() {
      _templates = _service.all();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed. Messages like this will go to Pending Review.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-added messages'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<List<TrustedTemplate>>(
        future: _templates,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final templates = snapshot.data ?? const <TrustedTemplate>[];
          if (templates.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing here yet. When you accept a message in Pending '
                  'Review, similar messages from the same sender are added '
                  'automatically and listed here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: templates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = templates[i];
              final isCredit = t.direction == 'credit';
              final used = t.useCount == 0
                  ? 'Not used yet'
                  : 'Added ${t.useCount} '
                      '${t.useCount == 1 ? 'time' : 'times'}, last on '
                      '${DateFormat('d MMM').format(t.lastUsedAt ?? t.createdAt)}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isCredit
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: isCredit ? AppTheme.incomeGreen : AppTheme.expenseRed,
                ),
                title: Text(
                    '${t.sender} · ${isCredit ? 'money in' : 'money out'}'),
                subtitle: Text(
                  '${t.example}\n$used',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Stop auto-adding',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _remove(t),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
