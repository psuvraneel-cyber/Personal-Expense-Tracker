import 'package:flutter/material.dart';
import 'package:pet/config/app_links.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/services/secure_storage_service.dart';

/// Shown when the local database didn't open.
///
/// Usually that's temporary: another task has it, or an update is working.
/// The data is fine, so this waits and retries by itself and doesn't mention
/// resetting. For a real failure (Android Keystore reset by an OS update or
/// restore, a damaged file) the user can reset local data, but only after
/// "Try again" has failed too; signed-in users get their cloud backup back
/// after signing in.
class DatabaseRecoveryApp extends StatelessWidget {
  final Future<void> Function() onRestart;

  /// Why the database didn't open.
  final Object error;

  /// Replaces the real open in tests.
  final Future<void> Function()? open;

  const DatabaseRecoveryApp({
    super.key,
    required this.onRestart,
    required this.error,
    this.open,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: _DatabaseRecoveryScreen(
        onRestart: onRestart,
        error: error,
        open: open ?? () => DatabaseHelper().database,
      ),
    );
  }
}

class _DatabaseRecoveryScreen extends StatefulWidget {
  final Future<void> Function() onRestart;
  final Object error;
  final Future<void> Function() open;
  const _DatabaseRecoveryScreen({
    required this.onRestart,
    required this.error,
    required this.open,
  });

  @override
  State<_DatabaseRecoveryScreen> createState() =>
      _DatabaseRecoveryScreenState();
}

class _DatabaseRecoveryScreenState extends State<_DatabaseRecoveryScreen> {
  /// Automatic tries while it's only busy, before asking the user to step in.
  static const int _autoRetries = 3;

  bool _working = false;
  late Object _error = widget.error;

  /// "Try again" presses that failed.
  int _failedTries = 0;

  /// Still retrying by itself.
  bool _waiting = false;

  bool get _temporary => DatabaseHelper.isTemporaryOpenFailure(_error);
  bool get _keyProblem => _error is DatabaseKeyUnavailableException;

  @override
  void initState() {
    super.initState();
    if (_temporary) {
      _waiting = true;
      _waitForDatabase();
    }
  }

  Future<void> _waitForDatabase() async {
    for (var i = 0; i < _autoRetries && _temporary; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      if (await _open()) return;
    }
    if (mounted) setState(() => _waiting = false);
  }

  /// True when the database opened and the app is starting.
  Future<bool> _open() async {
    try {
      await widget.open();
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return false;
    }
    await widget.onRestart();
    return true;
  }

  Future<void> _tryAgain() async {
    setState(() => _working = true);
    final opened = await _open();
    if (!mounted || opened) return;
    setState(() {
      _working = false;
      _failedTries++;
    });
  }

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

  String get _title {
    if (_waiting) return 'Finishing your update';
    if (_temporary) return 'This is taking longer than usual';
    return "Your data couldn't be unlocked";
  }

  String get _message {
    if (_waiting) {
      return 'P.E.T is getting your data ready. This can take a minute after '
          'an update. Your data is safe.';
    }
    if (_temporary) {
      return 'P.E.T is still busy with your data, which is safe. Try again '
          'in a moment, or restart your phone if this keeps happening.';
    }
    if (_keyProblem) {
      return 'Android could not provide the key that protects your encrypted '
          'P.E.T data. This can happen after a system update or device '
          'restore.\n\nTry restarting your phone first. If the problem '
          'continues, reset local data.';
    }
    return 'P.E.T could not open its data on this device (the storage may be '
        'damaged or an update did not finish).\n\nTry again first. If the '
        'problem continues, reset local data.';
  }

  @override
  Widget build(BuildContext context) {
    // Resetting deletes the data, so it isn't offered for a busy database,
    // nor before a retry has shown the problem is real.
    final canReset = !_temporary && _failedTries > 0;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_waiting)
                const Center(child: CircularProgressIndicator())
              else
                Icon(
                  _temporary
                      ? Icons.hourglass_top_rounded
                      : Icons.lock_reset_rounded,
                  size: 64,
                ),
              const SizedBox(height: 16),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(_message, textAlign: TextAlign.center),
              if (!_waiting) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _working ? null : _tryAgain,
                  child: const Text('Try again'),
                ),
                if (canReset) ...[
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
                ],
                TextButton(
                  onPressed: () => AppLinks.emailSupport(context),
                  child: const Text('Contact support'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
