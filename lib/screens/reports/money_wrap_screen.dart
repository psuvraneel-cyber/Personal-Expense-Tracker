import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pet/config/app_links.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/money_wrap.dart';
import 'package:pet/services/report_notifier.dart';

/// The monthly "Money Wrap": a month in review, shareable as an image.
///
/// The shared card leaves out rupee amounts unless the user turns them on,
/// so sharing never reveals how much someone earns or spends by default.
class MoneyWrapScreen extends StatefulWidget {
  const MoneyWrapScreen({super.key, required this.month});

  /// Any day in the month to show.
  final DateTime month;

  @override
  State<MoneyWrapScreen> createState() => _MoneyWrapScreenState();
}

class _MoneyWrapScreenState extends State<MoneyWrapScreen> {
  final _cardKey = GlobalKey();
  late final Future<MoneyWrap> _wrap = ReportNotifier.loadWrap(
    DateTime(widget.month.year, widget.month.month),
  );
  bool _showAmounts = false;
  bool _sharing = false;

  Future<void> _share(MoneyWrap wrap) async {
    setState(() => _sharing = true);
    File? file;
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/pet_money_wrap.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      AnalyticsService.instance.logEvent(
          'money_wrap_share', {'amounts': _showAmounts ? 'shown' : 'hidden'});
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'My ${DateFormat('MMMM').format(wrap.month)} Money Wrap, '
            'tracked automatically with P.E.T: ${AppLinks.playStoreListing}',
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share the Money Wrap.')),
        );
      }
    } finally {
      try {
        await file?.delete();
      } catch (_) {}
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('MMMM yyyy').format(widget.month);
    return Scaffold(
      appBar: AppBar(title: Text('$title Wrap')),
      body: FutureBuilder<MoneyWrap>(
        future: _wrap,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final wrap = snapshot.data;
          if (wrap == null || wrap.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No transactions were tracked that month.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RepaintBoundary(
                key: _cardKey,
                child: MoneyWrapCard(wrap: wrap, showAmounts: _showAmounts),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _showAmounts,
                onChanged: (v) => setState(() => _showAmounts = v),
                title: const Text('Show amounts on the card'),
                subtitle: const Text(
                    'Off by default, so sharing never reveals what you '
                    'spend or earn.'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentPurple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _sharing ? null : () => _share(wrap),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share my Money Wrap'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The shareable card itself.
class MoneyWrapCard extends StatelessWidget {
  const MoneyWrapCard({
    super.key,
    required this.wrap,
    required this.showAmounts,
  });

  final MoneyWrap wrap;
  final bool showAmounts;

  static final _inr =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  /// The card's lines, in order. Amount lines only appear when
  /// [showAmounts] is on.
  static List<(IconData, String)> linesFor(MoneyWrap wrap, bool showAmounts) {
    final prevMonth = DateFormat('MMMM')
        .format(DateTime(wrap.month.year, wrap.month.month - 1));
    final change = wrap.spentChangePercent;
    return [
      if (showAmounts)
        (Icons.payments_rounded, '${_inr.format(wrap.spent)} spent'),
      (
        Icons.receipt_long_rounded,
        '${wrap.transactionCount} transactions tracked'
            '${wrap.autoImportedCount > 0 ? ', ${wrap.autoImportedCount} automatically' : ''}',
      ),
      if (wrap.topCategory != null)
        (
          Icons.pie_chart_rounded,
          'Top category: ${wrap.topCategory} '
              '(${(wrap.topCategoryShare * 100).round()}% of spending)',
        ),
      if (change != null && change.abs() >= 1)
        (
          change < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
          'Spent ${change.abs().round()}% ${change < 0 ? 'less' : 'more'} '
              'than $prevMonth',
        ),
      if (wrap.biggestDropCategory != null && wrap.biggestDropPercent >= 5)
        (
          Icons.savings_rounded,
          'Biggest saving: ${wrap.biggestDropCategory}, '
              'down ${wrap.biggestDropPercent.round()}%'
              '${showAmounts ? ' (${_inr.format(wrap.biggestDropAmount)})' : ''}',
        ),
      if (wrap.subscriptionsFound > 0)
        (
          Icons.repeat_rounded,
          '${wrap.subscriptionsFound} subscription'
              '${wrap.subscriptionsFound == 1 ? '' : 's'} & bills found'
              '${showAmounts ? ' (${_inr.format(wrap.subscriptionsMonthly)}/month)' : ''}',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lines = linesFor(wrap, showAmounts);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('MMMM yyyy').format(wrap.month).toUpperCase(),
              style: const TextStyle(
                  fontSize: 12, letterSpacing: 1.5, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            const Text(
              'My Money Wrap',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            for (final (icon, text) in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
            const Divider(color: Colors.white24, height: 24),
            const Text(
              'Tracked automatically with P.E.T — Personal Expense Tracker',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
