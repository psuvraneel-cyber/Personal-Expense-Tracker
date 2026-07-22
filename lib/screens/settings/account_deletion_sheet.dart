import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:pet/services/firebase_auth_service.dart';
import 'package:pet/screens/auth/google_sign_in_screen.dart';

class AccountDeletionSheet extends StatefulWidget {
  const AccountDeletionSheet({super.key});
  @override
  State<AccountDeletionSheet> createState() => _AccountDeletionSheetState();
}

class _AccountDeletionSheetState extends State<AccountDeletionSheet> {
  int _step = 0; // 0=info, 1=reauth, 2=confirm, 3=deleting, 4=done
  bool _confirmChecked = false;
  // ignore: unused_field
  bool _isDeleting = false;
  DeletionStep? _currentDeletionStep;
  String? _errorMessage;

  // ── Step 0: Information ─────────────────────────────────────────────────
  Widget _buildInfoStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade400,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Delete Account',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'This will permanently delete:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 12),
          for (final item in [
            'All your transactions (manual + SMS-detected)',
            'All budgets and category settings',
            'Savings goals and progress',
            'Recurring bills and alerts',
            'All data stored on this device',
            'Your account from our servers',
          ]) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: Colors.red.shade400)),
                Expanded(
                  child: Text(item, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.red.shade400, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'This action is IRREVERSIBLE. Your data cannot be recovered.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                  ),
                  onPressed: () => setState(() => _step = 1),
                  child: const Text(
                    'Continue →',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 1: Re-authentication ──────────────────────────────────────────
  Widget _buildReAuthStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Confirm it\'s you',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'For security, please sign in again before deleting your account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _reAuthenticate,
            icon: Image.asset('assets/google_logo.png', width: 20),
            label: const Text('Sign in with Google'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('← Back'),
          ),
        ],
      ),
    );
  }

  Future<void> _reAuthenticate() async {
    try {
      final success = await FirebaseAuthService().reauthenticateGoogle();
      if (!success) {
        if (mounted) setState(() => _errorMessage = 'Sign-in failed or was cancelled.');
        return;
      }
      if (mounted) setState(() => _step = 2);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Sign-in failed. Please try again.');
    }
  }

  // ── Step 2: Final Confirmation ─────────────────────────────────────────
  Widget _buildConfirmStep() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your account';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Are you absolutely sure?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'This will delete the account signed in as:',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            value: _confirmChecked,
            onChanged: (v) => setState(() => _confirmChecked = v ?? false),
            title: const Text(
              'I understand this is permanent and cannot be undone',
              style: TextStyle(fontSize: 14),
            ),
            activeColor: Colors.red,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _confirmChecked
                        ? Colors.red.shade600
                        : Colors.grey,
                  ),
                  onPressed: _confirmChecked ? _executeDelete : null,
                  icon: const Icon(
                    Icons.delete_forever,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'DELETE MY ACCOUNT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 3: Deleting Progress ──────────────────────────────────────────
  Widget _buildDeletingStep() {
    final stepLabels = {
      DeletionStep.deletingCloudTransactions: 'Deleting cloud transactions...',
      DeletionStep.deletingCloudBudgets: 'Deleting cloud budgets...',
      DeletionStep.deletingCloudCategories: 'Deleting cloud categories...',
      DeletionStep.deletingCloudTombstones: 'Deleting cloud deletion tombstones...',
      DeletionStep.deletingCloudPremiumData: 'Deleting premium data...',
      DeletionStep.deletingUserProfile: 'Deleting user profile...',
      DeletionStep.deletingAuthAccount: 'Removing account...',
      DeletionStep.clearingLocalData: 'Removing local data...',
      DeletionStep.clearingPreferences: 'Clearing preferences...',
      DeletionStep.complete: 'Done!',
    };

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMessage == null)
            const CircularProgressIndicator()
          else
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
          const SizedBox(height: 24),
          Text(
            _errorMessage ??
                stepLabels[_currentDeletionStep] ??
                'Deleting your account...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: _errorMessage != null ? Colors.red.shade400 : null,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 4: Completion ─────────────────────────────────────────────────
  Widget _buildDoneStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade50,
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.green.shade600,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Account Deleted',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your account and all associated data have been permanently removed.\n\nThank you for using PET.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () {
              // Pop all routes and navigate to sign-in screen
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/sign_in', (route) => false);
            },
            child: const Text('Get Started'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeDelete() async {
    final targetUid = FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == null) {
      if (mounted) setState(() => _errorMessage = 'No authenticated user');
      return;
    }

    setState(() {
      _step = 3;
      _isDeleting = true;
    });

    final service = context.read<AccountDeletionService>();

    // Listen to progress stream
    service.progress.listen(
      (step) {
        if (mounted) setState(() => _currentDeletionStep = step);
        if (step == DeletionStep.complete && mounted) {
          // Immediately route to sign-in
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const GoogleSignInScreen()),
            (route) => false,
          );
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Deletion failed: $e';
            _isDeleting = false;
          });
        }
      },
    );

    try {
      await service.deleteAccount(targetUid: targetUid);
    } catch (e) {
      // Handle synchronous or unexpected errors that didn't go through the stream
      if (mounted) {
        setState(() {
          _errorMessage = 'Deletion failed: $e';
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDeleting,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: _step == 0
              ? _buildInfoStep()
              : _step == 1
              ? _buildReAuthStep()
              : _step == 2
              ? _buildConfirmStep()
              : _step == 3
              ? _buildDeletingStep()
              : _buildDoneStep(),
        ),
      ),
    );
  }
}
