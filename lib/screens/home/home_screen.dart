import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:pet/core/widgets/analytics_consent_sheet.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/biometric_service.dart';
import 'package:pet/services/engagement_tracker.dart';
import 'package:pet/services/financial_ingestion_service.dart';
import 'package:pet/services/home_widget_service.dart';
import 'package:pet/services/household_service.dart';
import 'package:pet/screens/dashboard/dashboard_screen.dart';
import 'package:pet/screens/transactions/transactions_screen.dart';
import 'package:pet/screens/transactions/add_edit_transaction_screen.dart';
import 'package:pet/screens/budget/budget_screen.dart';
import 'package:pet/screens/settings/settings_screen.dart';
import 'package:pet/screens/settings/account_deletion_sheet.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDarkMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ThemeMode? themeMode;
  final bool showDeletionImmediately;

  const HomeScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
    this.onThemeModeChanged,
    this.themeMode,
    this.showDeletionImmediately = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Cache screen instances so they aren't recreated on tab switch
  static const _dashboard = DashboardScreen();
  static const _transactions = TransactionsScreen();
  static const _budget = BudgetScreen();

  Timer? _engagementTimer;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!widget.showDeletionImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startEngagement());
    }
    if (widget.showDeletionImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showModalBottomSheet(
          useSafeArea: true,
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (_) => const AccountDeletionSheet(),
        );
      });
    }
  }

  @override
  void dispose() {
    _engagementTimer?.cancel();
    _lifecycle?.dispose();
    FinancialIngestionService.ledgerRevision
        .removeListener(_scheduleEngagementCheck);
    super.dispose();
  }

  /// Asks for analytics consent once, then keeps funnel milestones and the
  /// review prompt up to date as transactions are imported.
  Future<void> _startEngagement() async {
    if (!mounted) return;
    if (await AnalyticsService.shouldAskForConsent() && mounted) {
      await showAnalyticsConsentSheet(context);
    }
    if (!mounted) return;
    FinancialIngestionService.ledgerRevision
        .addListener(_scheduleEngagementCheck);
    _lifecycle = AppLifecycleListener(
      onResume: _scheduleEngagementCheck,
      // Leaving the app: push fresh numbers (incl. budget or lock changes)
      // to the home-screen widget.
      onHide: HomeWidgetService.refresh,
    );
    _scheduleEngagementCheck();
  }

  void _scheduleEngagementCheck() {
    _engagementTimer?.cancel();
    // Let imports settle and the screen become idle before any prompt.
    _engagementTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      // Only prompt while the user is on the home screen itself, unlocked.
      final canPrompt = (ModalRoute.of(context)?.isCurrent ?? true) &&
          !BiometricService.instance.isLocked;
      EngagementTracker.instance.evaluate(allowReviewPrompt: canPrompt);
      HomeWidgetService.refresh();
      HouseholdSync.publishMine();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // SettingsScreen must be rebuilt so the theme picker reflects the current mode
    final screens = <Widget>[
      _dashboard,
      _transactions,
      _budget,
      SettingsScreen(
        onThemeToggle: widget.onThemeToggle,
        isDarkMode: widget.isDarkMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        themeMode: widget.themeMode,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: screens),
      floatingActionButton: _currentIndex < 2
          ? Semantics(
              label: AppLocalizations.of(context).addTransactionSemantics,
              button: true,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: AppTheme.heroGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentPurple.withAlpha(80),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: FloatingActionButton.extended(
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const AddEditTransactionScreen(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          return SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 350),
                      ),
                    );
                  },
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  icon: const Icon(Icons.add_rounded, size: 22),
                  label: Text(
                    AppLocalizations.of(context).addTransactionShort,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            )
          : null,
      // SafeArea keeps the floating bar above the system navigation bar
      // (Android 15+/targetSdk 35+ draws edge-to-edge).
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildBottomNav(context, isDark),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 20),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1A1731).withAlpha(250)
                : Colors.white.withAlpha(250),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(8)
                  : Colors.black.withAlpha(6),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: AppLocalizations.of(context).navHome,
                isDark: isDark,
              ),
              _navItem(
                index: 1,
                icon: Icons.swap_horiz_rounded,
                activeIcon: Icons.swap_horiz_rounded,
                label: AppLocalizations.of(context).navHistory,
                isDark: isDark,
              ),
              _navItem(
                index: 2,
                icon: Icons.pie_chart_outline_rounded,
                activeIcon: Icons.pie_chart_rounded,
                label: AppLocalizations.of(context).navBudget,
                isDark: isDark,
              ),
              _navItem(
                index: 3,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                label: AppLocalizations.of(context).navSettings,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isDark,
  }) {
    final isActive = _currentIndex == index;
    return Expanded(
      child: Semantics(
        label: AppLocalizations.of(context).navTabSemantics(label),
        selected: isActive,
        child: GestureDetector(
          onTap: () => setState(() => _currentIndex = index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.accentPurple.withAlpha(isDark ? 35 : 22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  size: 22,
                  color: isActive
                      ? AppTheme.accentPurple
                      : (isDark
                          ? AppTheme.textTertiary
                          : AppTheme.textSecondaryLight),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? AppTheme.accentPurple
                        : (isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
