import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3-step onboarding flow for first-time users.
///
/// Steps:
/// 1. Grant SMS permission (auto-detect transactions)
/// 2. Set monthly budget
/// 3. Add first category
///
/// Shown only once via SharedPreferences flag `onboardingCompleted`.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isAggressiveOem = false;
  String _manufacturer = '';

  int get _totalSteps => _isAggressiveOem ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _checkOem();
  }

  Future<void> _checkOem() async {
    final reader = NativeSmsReader();
    final isAggressive = await reader.isAggressiveOem();
    final m = await reader.getDeviceManufacturer();
    if (mounted && isAggressive) {
      setState(() {
        _isAggressiveOem = true;
        _manufacturer = m.toUpperCase();
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      setState(() => _currentStep++);
    } else {
      _complete();
    }
  }

  void _skip() => _complete();

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingCompleted', true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep(
                    icon: Icons.sms_rounded,
                    iconColor: AppTheme.accentTeal,
                    title: 'Auto-Detect Transactions',
                    subtitle:
                        'P.E.T reads your bank SMS to automatically\ntrack your spending. No data ever leaves your device.',
                    badge: '100% On-Device',
                    badgeIcon: Icons.lock_outline,
                  ),
                  _buildStep(
                    icon: Icons.pie_chart_rounded,
                    iconColor: AppTheme.accentPurple,
                    title: 'Set Your Monthly Budget',
                    subtitle:
                        'Stay on top of your finances with customisable\nbudgets for each spending category.',
                    badge: 'Smart Alerts',
                    badgeIcon: Icons.notifications_active_outlined,
                  ),
                  _buildStep(
                    icon: Icons.category_rounded,
                    iconColor: AppTheme.incomeGreen,
                    title: 'Personalise Your Categories',
                    subtitle:
                        'Add custom categories that match your lifestyle.\nFood, Travel, Subscriptions — you decide.',
                    badge: 'Fully Customisable',
                    badgeIcon: Icons.palette_outlined,
                  ),
                  if (_isAggressiveOem) _buildOemStep(),
                ],
              ),
            ),

            // Step indicator + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalSteps, (index) {
                      final isActive = index == _currentStep;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.accentPurple
                              : AppTheme.textTertiary.withAlpha(80),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),

                  // CTA button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _nextStep,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accentPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _currentStep == _totalSteps - 1
                            ? 'Get Started'
                            : 'Continue',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badge,
    required IconData badgeIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large icon container
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [iconColor.withAlpha(40), iconColor.withAlpha(10)],
              ),
            ),
            child: Icon(icon, size: 56, color: iconColor),
          ),
          const SizedBox(height: 40),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  badge,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOemStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.expenseRed.withAlpha(40),
                  AppTheme.expenseRed.withAlpha(10),
                ],
              ),
            ),
            child: const Icon(
              Icons.battery_saver_rounded,
              size: 56,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Background Sync Whitelist',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your device ($_manufacturer) aggressively restricts background apps. '
            'To ensure P.E.T auto-detects all transactions without missing any SMS, '
            'please disable battery saver restrictions for P.E.T.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await NativeSmsReader().openBatteryOptimizationSettings();
            },
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open Battery Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
