import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pet/config/app_links.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/referral_service.dart';

/// Invite friends: share your code, or enter a friend's code. Both people
/// get a month of Premium.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _codeController = TextEditingController();
  late final Future<String?> _myCode =
      _isGuest ? Future.value(null) : ReferralService.myCode();
  bool _redeeming = false;
  ReferralResult? _result;

  bool get _isGuest => FirebaseAuth.instance.currentUser?.isAnonymous ?? true;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _redeeming = true;
      _result = null;
    });
    final result = await ReferralService.redeem(code);
    if (!mounted) return;
    setState(() {
      _redeeming = false;
      _result = result;
    });
    if (result.ok) {
      AnalyticsService.instance.logEvent('referral_redeemed');
      // Picks up the new promotional entitlement (bypassing the SDK's
      // cached customer info).
      final premium = context.read<PremiumProvider>();
      try {
        await Purchases.invalidateCustomerInfoCache();
      } catch (_) {}
      premium.load();
    }
  }

  void _share(String code) {
    AnalyticsService.instance.logEvent('referral_shared');
    SharePlus.instance.share(ShareParams(
      text: ReferralService.shareText(code, AppLinks.playStoreListing),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.card_giftcard_rounded,
                    color: Colors.white, size: 32),
                SizedBox(height: 12),
                Text(
                  'Give a month, get a month',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'When a friend new to P.E.T uses your code, you both get '
                  'a month of Premium free.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_isGuest)
            const Text(
              'Sign in with Google (Settings → Account) to get your invite '
              'code or use a friend\'s.',
            )
          else ...[
            Text('Your invite code', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: _myCode,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final code = snapshot.data;
                if (code == null) {
                  return const Text(
                      "Couldn't load your code. Check your connection.");
                }
                return Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        code,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy code',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')),
                        );
                      },
                    ),
                    FilledButton.icon(
                      onPressed: () => _share(code),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Share'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            Text('Got a code from a friend?',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 12,
              decoration: const InputDecoration(
                hintText: 'Enter invite code',
                counterText: '',
              ),
              onSubmitted: (_) => _redeem(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _redeeming ? null : _redeem,
              child: _redeeming
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Apply code'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(
                _result!.message,
                style: TextStyle(
                  color: _result!.ok
                      ? AppTheme.incomeGreen
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          Text(
            'Codes work for accounts new to P.E.T (first 30 days). Each '
            'account can use one code. Inviters can earn up to 12 free '
            'months a year.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
