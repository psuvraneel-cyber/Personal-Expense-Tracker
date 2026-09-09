import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/core/theme/app_theme.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String email;

  const ProfileSetupScreen({super.key, required this.email});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  bool _isSaving = false;
  String? _errorText;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Please enter your name');
      return;
    }
    if (name.length < 2) {
      setState(() => _errorText = 'Name must be at least 2 characters');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      // Profile name comes from Google Account — just cache it locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', name);

      if (!mounted) return;

      // Navigate to home and clear backstack
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Failed to save profile. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                // Success icon
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: AppTheme.incomeGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.incomeGreen.withAlpha(40),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Phone verified!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Let\'s set up your profile to personalise your experience.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 40),
                // Avatar placeholder
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.accentPurple.withAlpha(30),
                              AppTheme.accentTeal.withAlpha(15),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.accentPurple.withAlpha(40),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _nameController.text.trim().isNotEmpty
                                ? _nameController.text.trim()[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppTheme.textPrimary
                                  : AppTheme.accentPurple,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: AppTheme.purpleGradient,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? AppTheme.primaryDark
                                  : AppTheme.primaryLight,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Name label
                Text(
                  'Your name',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
                // Name field
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(6) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _errorText != null
                          ? AppTheme.expenseRed
                          : (isDark
                              ? Colors.white.withAlpha(10)
                              : Colors.black.withAlpha(8)),
                      width: _errorText != null ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? Colors.black : Colors.grey).withAlpha(
                          isDark ? 20 : 8,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    decoration: InputDecoration(
                      hintText: 'Enter your name',
                      prefixIcon: Icon(
                        Icons.person_rounded,
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                    onChanged: (_) {
                      if (_errorText != null) {
                        setState(() => _errorText = null);
                      }
                      setState(() {}); // Update avatar letter
                    },
                  ),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppTheme.expenseRed,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                          color: AppTheme.expenseRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSaving ? null : _saveProfile,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: _isSaving ? null : AppTheme.heroGradient,
                          color: _isSaving
                              ? (isDark
                                  ? Colors.white.withAlpha(10)
                                  : Colors.black.withAlpha(10))
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _isSaving
                              ? null
                              : [
                                  BoxShadow(
                                    color: AppTheme.accentPurple.withAlpha(40),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                        ),
                        child: Center(
                          child: _isSaving
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: isDark
                                        ? AppTheme.textPrimary
                                        : AppTheme.textPrimaryLight,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Get Started',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
