import 'package:flutter/material.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:pet/config/app_links.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';

import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/remote_config_service.dart';

/// Index of the package to pre-select for the Remote Config [plan]
/// ('annual', 'monthly', 'lifetime' or 'first'); falls back to the first
/// package when the offering has no package of that type.
int defaultPackageIndex(List<PackageType> types, String plan) {
  final wanted = switch (plan) {
    'annual' => PackageType.annual,
    'monthly' => PackageType.monthly,
    'lifetime' => PackageType.lifetime,
    _ => null,
  };
  final index = wanted == null ? -1 : types.indexOf(wanted);
  return index < 0 ? 0 : index;
}

/// "7-day free trial" for a Play free-trial phase, or null if none.
String? freeTrialLabel(Period? period) {
  if (period == null || period.value <= 0) return null;
  final n = period.value;
  return switch (period.unit) {
    PeriodUnit.day => '$n-day free trial',
    PeriodUnit.week => n == 1 ? '7-day free trial' : '$n-week free trial',
    PeriodUnit.month => n == 1 ? '1-month free trial' : '$n-month free trial',
    PeriodUnit.year => n == 1 ? '1-year free trial' : '$n-year free trial',
    PeriodUnit.unknown => 'Free trial',
  };
}

/// Whole-percent saving of a yearly price over twelve monthly payments, or
/// null when there's no real saving to show.
int? annualSavingsPercent({required double annual, required double monthly}) {
  if (annual <= 0 || monthly <= 0) return null;
  final percent = ((1 - annual / (monthly * 12)) * 100).floor();
  return percent >= 5 ? percent : null;
}

/// The free-trial label of [package]'s default Play offer, if it has one.
String? packageTrialLabel(Package package) => freeTrialLabel(
    package.storeProduct.defaultOption?.freePhase?.billingPeriod);

/// RevenueCat offering shown to people whose Premium has lapsed. Set it up
/// with a Google Play win-back offer (see docs/growth-launch-checklist.md);
/// when it doesn't exist the current offering is used.
const String kWinBackOfferingId = 'winback';

/// Which offering to show: the win-back one for lapsed subscribers when it
/// exists, otherwise RevenueCat's current offering (null = current).
String? offeringIdToShow({
  required bool lapsed,
  required Iterable<String> available,
}) =>
    lapsed && available.contains(kWinBackOfferingId)
        ? kWinBackOfferingId
        : null;

class PurchaseScreen extends StatefulWidget {
  /// Which locked feature opened the paywall (analytics label).
  final String source;

  const PurchaseScreen({super.key, this.source = 'unknown'});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  Offerings? _offerings;

  /// The offering on screen (current, or win-back for lapsed subscribers).
  Offering? _offering;
  bool _isLoading = true;
  Package? _selectedPackage;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance
        .logEvent(AnalyticsEvents.paywallView, {'source': widget.source});
    _fetchOfferings();
  }

  /// Fixed labels only — never the user's identity or purchase token.
  Map<String, Object> _purchaseParams(Package package) => {
        'plan': package.packageType.name,
        'value': package.storeProduct.price,
        'currency': package.storeProduct.currencyCode,
        'source': widget.source,
      };

  Future<void> _fetchOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      // Had Premium before but not now → offer the win-back deal.
      var lapsed = false;
      try {
        final info = await Purchases.getCustomerInfo();
        final entitlement = info.entitlements.all['P.E.T Premium'];
        lapsed = entitlement != null && !entitlement.isActive;
      } catch (_) {}
      final offeringId =
          offeringIdToShow(lapsed: lapsed, available: offerings.all.keys);
      if (offeringId != null) {
        AnalyticsService.instance
            .logEvent('paywall_winback_shown', {'source': widget.source});
      }
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _offering = offeringId == null
              ? offerings.current
              : offerings.all[offeringId];
          _isLoading = false;
          // Pre-select the plan chosen in Remote Config (annual by default).
          // Which packages exist is decided by the RevenueCat offering, so
          // RevenueCat Experiments can test prices without an app update.
          final packages = _offering?.availablePackages ?? const [];
          if (packages.isNotEmpty) {
            _selectedPackage = packages[defaultPackageIndex(
              packages.map((p) => p.packageType).toList(),
              RemoteConfigService.paywallDefaultPlan,
            )];
          }
        });
      }
    } on PlatformException catch (e) {
      AppLogger.error('Error fetching offerings',
          error: e, label: 'PurchaseScreen');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _purchaseSelectedPackage() async {
    if (_selectedPackage == null) return;
    setState(() => _isLoading = true);
    try {
      final package = _selectedPackage!;
      final result = await Purchases.purchase(PurchaseParams.package(package));
      final entitlement = result.customerInfo.entitlements.all["P.E.T Premium"];
      if (entitlement?.isActive == true) {
        // Trial-to-paid conversions happen later on Google's side; they reach
        // Firebase through RevenueCat's integration, not from the app.
        AnalyticsService.instance.logEvent(
          entitlement!.periodType == PeriodType.trial
              ? AnalyticsEvents.trialStart
              : AnalyticsEvents.subscribe,
          _purchaseParams(package),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Welcome to P.E.T Premium!'),
            backgroundColor: AppTheme.incomeGreen,
          ),
        );
        Navigator.pop(context);
      }
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: ${e.message}'),
            backgroundColor: AppTheme.expenseRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      final customerInfo = await Purchases.restorePurchases();
      if (customerInfo.entitlements.all["P.E.T Premium"]?.isActive == true) {
        AnalyticsService.instance.logEvent(AnalyticsEvents.purchaseRestored);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Purchases successfully restored!'),
            backgroundColor: AppTheme.incomeGreen,
          ),
        );
        Navigator.pop(context);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active subscriptions found to restore.'),
            backgroundColor: AppTheme.warningYellow,
          ),
        );
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: ${e.message}'),
          backgroundColor: AppTheme.expenseRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    // Remote Config copy is English; other languages use the translations.
    final english = Localizations.localeOf(context).languageCode == 'en';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    const Color(0xFF1E1035),
                    const Color(0xFF0F0B1E),
                    const Color(0xFF0A0915),
                  ]
                : [
                    const Color(0xFFF3E8FF),
                    const Color(0xFFFAFAFA),
                    Colors.white,
                  ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              CustomScrollView(
                slivers: [
                  // App Bar with close & restore buttons
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: IconButton(
                      tooltip: l10n.close,
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      TextButton(
                        onPressed: _restorePurchases,
                        child: Text(
                          l10n.paywallRestore,
                          style: TextStyle(
                            color: AppTheme.accentPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 20),
                        // Crown icon with glowing animation
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.accentPurple.withValues(
                                alpha: 0.15,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentPurple
                                      .withValues(alpha: 0.2),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              size: 72,
                              color: Colors.amber,
                            ),
                          )
                              .animate(
                                onPlay: (controller) =>
                                    controller.repeat(reverse: true),
                              )
                              .shimmer(
                                duration: 2000.ms,
                                color: Colors.amber.withValues(alpha: 0.3),
                              )
                              .scale(
                                begin: const Offset(0.95, 0.95),
                                end: const Offset(1.05, 1.05),
                                duration: 1500.ms,
                              ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          english
                              ? RemoteConfigService.paywallHeadline
                              : l10n.paywallHeadline,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black87,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        )
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.2, end: 0),
                        const SizedBox(height: 8),
                        Text(
                          english
                              ? RemoteConfigService.paywallSubtitle
                              : l10n.paywallSubtitle,
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
                        const SizedBox(height: 16),
                        _buildTrustStrip(isDark),
                        const SizedBox(height: 28),

                        // Premium Features list
                        _buildFeatureRow(
                          icon: Icons.auto_awesome_rounded,
                          title: l10n.paywallFeatureAiTitle,
                          subtitle: l10n.paywallFeatureAiBody,
                          color: const Color(0xFFEC4899),
                          isDark: isDark,
                        )
                            .animate()
                            .fadeIn(delay: 250.ms, duration: 450.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          icon: Icons.account_balance_rounded,
                          title: l10n.paywallFeatureTaxTitle,
                          subtitle: l10n.paywallFeatureTaxBody,
                          color: const Color(0xFF10B981),
                          isDark: isDark,
                        )
                            .animate()
                            .fadeIn(delay: 350.ms, duration: 450.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          icon: Icons.insights_rounded,
                          title: l10n.paywallFeatureCashflowTitle,
                          subtitle: l10n.paywallFeatureCashflowBody,
                          color: const Color(0xFF8B5CF6),
                          isDark: isDark,
                        )
                            .animate()
                            .fadeIn(delay: 450.ms, duration: 450.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          icon: Icons.timer_rounded,
                          title: l10n.paywallFeatureFocusTitle,
                          subtitle: l10n.paywallFeatureFocusBody,
                          color: const Color(0xFFF59E0B),
                          isDark: isDark,
                        )
                            .animate()
                            .fadeIn(delay: 550.ms, duration: 450.ms)
                            .slideX(begin: -0.1, end: 0),

                        const SizedBox(height: 40),
                        Text(
                          l10n.paywallChoosePlan,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Subscription product offerings
                        if (_isLoading && _offerings == null)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 40.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_offering != null &&
                            _offering!.availablePackages.isNotEmpty)
                          ..._offering!.availablePackages.map((
                            package,
                          ) {
                            final isSelected = _selectedPackage == package;
                            return _buildPackageItem(
                              package,
                              isSelected,
                              isDark,
                            ).animate().fadeIn(delay: 100.ms).scale(
                                  begin: const Offset(0.97, 0.97),
                                  end: const Offset(1, 1),
                                  duration: 250.ms,
                                );
                          })
                        else
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 24.0,
                              ),
                              child: Text(
                                l10n.paywallNoPackages,
                                style: TextStyle(
                                  color:
                                      isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(
                          height: 120,
                        ), // Bottom padding for content scroll clearance
                      ]),
                    ),
                  ),
                ],
              ),

              // Bottom sticky subscription button panel
              if (_selectedPackage != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      24,
                      24,
                      24 + MediaQuery.of(context).viewPadding.bottom,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isDark
                            ? [
                                Colors.transparent,
                                const Color(0xFF0F0B1E).withValues(alpha: 0.95),
                                const Color(0xFF0A0915),
                              ]
                            : [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.95),
                                Colors.white,
                              ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentPurple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 8,
                            shadowColor: AppTheme.accentPurple.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          onPressed:
                              _isLoading ? null : _purchaseSelectedPackage,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  switch (
                                      packageTrialLabel(_selectedPackage!)) {
                                    final trial? => 'Start $trial',
                                    null => l10n.paywallSubscribe,
                                  },
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Payment is charged to your Google Play account. '
                          'Subscriptions renew automatically at the price and '
                          'period shown unless cancelled at least 24 hours '
                          'before renewal in Google Play → Subscriptions.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  AppLinks.open(context, AppLinks.terms),
                              child: const Text('Terms',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            TextButton(
                              onPressed: () => AppLinks.open(
                                  context, AppLinks.privacyPolicy),
                              child: const Text('Privacy Policy',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            TextButton(
                              onPressed: () => AppLinks.open(
                                  context, AppLinks.manageSubscriptions),
                              child: const Text('Manage subscription',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "SAVE 40%" on the yearly plan (vs. paying monthly), else the trial
  /// length or "BEST VALUE".
  String _badgeFor(Package package, String? trial) {
    if (package.packageType == PackageType.annual) {
      final monthly = _offering?.monthly?.storeProduct.price;
      final saving = monthly == null
          ? null
          : annualSavingsPercent(
              annual: package.storeProduct.price, monthly: monthly);
      if (saving != null) return 'SAVE $saving%';
      if (trial == null) return 'BEST VALUE';
    }
    return trial!.toUpperCase();
  }

  /// Second line of a plan: trial terms first (Play requires the price after
  /// the trial to be clear), then the monthly equivalent for long plans.
  String _detailFor(Package package, String? trial, String periodSuffix) {
    final product = package.storeProduct;
    if (package.packageType == PackageType.lifetime) {
      return 'Pay once, unlock forever';
    }
    final perMonth = package.packageType != PackageType.monthly &&
            package.packageType != PackageType.weekly
        ? product.pricePerMonthString
        : null;
    final parts = <String>[
      if (trial != null)
        'Free for ${trial.replaceAll(' free trial', '')}, then '
            '${product.priceString}$periodSuffix.',
      if (perMonth != null) 'Just $perMonth a month.',
      'Cancel anytime.',
    ];
    return parts.join(' ');
  }

  Widget _buildTrustStrip(bool isDark) {
    final l10n = AppLocalizations.of(context);
    Widget item(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.accentTeal),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        item(Icons.lock_outline_rounded, l10n.trustNoBankLogin),
        item(Icons.phone_android_rounded, l10n.trustEncrypted),
        item(Icons.block_rounded, l10n.trustNeverSell),
      ],
    );
  }

  Widget _buildPackageItem(Package package, bool isSelected, bool isDark) {
    // Generate helpful duration markers for titles
    String durationTag = 'Subscription';
    String periodSuffix = '';
    bool isYearly = false;
    final product = package.storeProduct;
    final trial = packageTrialLabel(package);

    if (package.packageType == PackageType.lifetime) {
      durationTag = 'Lifetime Access';
      periodSuffix = ' once';
    } else if (package.packageType == PackageType.annual) {
      durationTag = 'Yearly Plan';
      periodSuffix = ' / year';
      isYearly = true;
    } else if (package.packageType == PackageType.sixMonth) {
      durationTag = '6-Month Plan';
      periodSuffix = ' / 6 months';
    } else if (package.packageType == PackageType.threeMonth) {
      durationTag = '3-Month Plan';
      periodSuffix = ' / 3 months';
    } else if (package.packageType == PackageType.monthly) {
      durationTag = 'Monthly Plan';
      periodSuffix = ' / month';
    } else if (package.packageType == PackageType.weekly) {
      durationTag = 'Weekly Plan';
      periodSuffix = ' / week';
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPackage = package;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? (isSelected
                  ? AppTheme.accentPurple.withValues(alpha: 0.15)
                  : AppTheme.surfaceDark)
              : (isSelected
                  ? AppTheme.accentPurple.withValues(alpha: 0.08)
                  : AppTheme.surfaceLight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentPurple
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio circle
            Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.accentPurple : Colors.grey,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        height: 12,
                        width: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentPurple,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        durationTag,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (isYearly || trial != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentTeal.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentTeal.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            _badgeFor(package, trial),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentTeal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _detailFor(package, trial, periodSuffix),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${product.priceString}$periodSuffix',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
