import 'package:flutter/material.dart';
import 'package:pet/config/app_links.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/database/database_helper.dart';

/// Shown when the encrypted local database exists but can't be unlocked
/// (e.g. Android Keystore was reset by an OS update or restore). Instead of
/// a silently broken app, the user can reset local data; signed-in users get
/// their cloud backup back after signing in again.
class DatabaseRecoveryApp extends StatelessWidget {
  final Future<void> Function() onRestart;

  /// True when the encryption key is the problem (vs. a corrupt database or a
  /// failed upgrade) — only changes the explanation shown.
  final bool keyProblem;
  const DatabaseRecoveryApp({
    super.key,
    required this.onRestart,
    this.keyProblem = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: _DatabaseRecoveryScreen(
        onRestart: onRestart,
        keyProblem: keyProblem,
      ),
    );
  }
}

class _DatabaseRecoveryScreen extends StatefulWidget {
  final Future<void> Function() onRestart;
  final bool keyProblem;
  const _DatabaseRecoveryScreen({
    required this.onRestart,
    required this.keyProblem,
  });

  @override
  State<_DatabaseRecoveryScreen> createState() =>
      _DatabaseRecoveryScreenState();
}

class _DatabaseRecoveryScreenState extends State<_DatabaseRecoveryScreen> {
  bool _working = false;

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset local data?'),
        content: const Text(
          'This permanently deletes the data stored on this device. '
          'If you use Google sign-in, your backed-up transactions will be '
          'restored after you sign in. Guest-mode data cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _working = true);
    await DatabaseHelper().resetLocalDatabase();
    await widget.onRestart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_reset_rounded, size: 64),
              const SizedBox(height: 16),
              Text(
                "Your data couldn't be unlocked",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                widget.keyProblem
                    ? 'Android could not provide the key that protects your '
                        'encrypted P.E.T data. This can happen after a system '
                        'update or device restore.\n\nTry restarting your '
                        'phone first. If the problem continues, reset local '
                        'data.'
                    : 'P.E.T could not open its data on this device (the '
                        'storage may be damaged or an update did not finish).'
                        '\n\nTry again first. If the problem continues, reset '
                        'local data.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _working ? null : widget.onRestart,
                child: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _working ? null : _reset,
                child: _working
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reset local data'),
              ),
              TextButton(
                onPressed: () => AppLinks.emailSupport(context),
                child: const Text('Contact support'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
