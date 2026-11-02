import 'package:flutter/material.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:pet/core/theme/motion.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/category_avatar.dart';
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
    final l10n = AppLocalizations.of(context);
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
                  l10n.onboardingSkip,
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
                    step: 1,
                    icon: Icons.sms_rounded,
                    iconColor: AppTheme.accentTeal,
                    title: l10n.onboardingAutoTitle,
                    subtitle: l10n.onboardingAutoBody,
                    badge: l10n.onboardingAutoBadge,
                    badgeIcon: Icons.lock_outline,
                  ),
                  _buildStep(
                    step: 2,
                    icon: Icons.pie_chart_rounded,
                    iconColor: AppTheme.accentPurple,
                    title: l10n.onboardingBudgetTitle,
                    subtitle: l10n.onboardingBudgetBody,
                    badge: l10n.onboardingBudgetBadge,
                    badgeIcon: Icons.notifications_active_outlined,
                  ),
                  _buildStep(
                    step: 3,
                    icon: Icons.category_rounded,
                    iconColor: AppTheme.incomeGreen,
                    title: l10n.onboardingCategoriesTitle,
                    subtitle: l10n.onboardingCategoriesBody,
                    badge: l10n.onboardingCategoriesBadge,
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
                        duration: Motion.of(context, Motion.standard),
                        curve: Motion.easeOut,
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
                      ),
                      child: Text(
                        _currentStep == _totalSteps - 1
                            ? l10n.onboardingGetStarted
                            : l10n.onboardingContinue,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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
    required int step,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badge,
    required IconData badgeIcon,
  }) {
    return _StepLayout(
      step: step,
      of: _totalSteps,
      icon: icon,
      iconColor: iconColor,
      title: title,
      body: Text(
        subtitle,
        style: TextStyle(
          fontSize: 16,
          color: AppTheme.textSecondary,
          height: 1.55,
        ),
      ),
      footer: Row(
        children: [
          Icon(badgeIcon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(215),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOemStep() {
    final l10n = AppLocalizations.of(context);
    return _StepLayout(
      step: _totalSteps,
      of: _totalSteps,
      icon: Icons.battery_saver_rounded,
      iconColor: Colors.amber,
      title: l10n.onboardingOemTitle,
      body: Text(
        l10n.onboardingOemBody(_manufacturer),
        style: TextStyle(
          fontSize: 15,
          color: AppTheme.textSecondary,
          height: 1.55,
        ),
      ),
      footer: OutlinedButton.icon(
        onPressed: () async {
          await NativeSmsReader().openBatteryOptimizationSettings();
        },
        icon: const Icon(Icons.settings_outlined, size: 18),
        label: Text(l10n.onboardingOemButton),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.amber,
          side: BorderSide(color: Colors.amber.withAlpha(120)),
        ),
      ),
    );
  }
}

/// One onboarding step: counter, icon tile, a large left-aligned title,
/// body text and a footer line. Eases in when it appears.
class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.step,
    required this.of,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.footer,
  });

  final int step;
  final int of;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryAvatar(icon: icon, color: iconColor, size: 64),
          const SizedBox(height: 28),
          Text(
            '$step of $of',
            style: AppTypography.overline(color: AppTheme.textTertiary),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.8,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),
          body,
          const SizedBox(height: 28),
          footer,
        ],
      ),
    );
    if (Motion.reduced(context)) return content;
    return content
        .animate()
        .fadeIn(duration: Motion.emphasized, curve: Motion.easeOut)
        .moveY(
          begin: 12,
          end: 0,
          duration: Motion.emphasized,
          curve: Motion.easeOut,
        );
  }
}
