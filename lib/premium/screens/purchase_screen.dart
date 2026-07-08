import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  Offerings? _offerings;
  bool _isLoading = true;
  Package? _selectedPackage;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  Future<void> _fetchOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _isLoading = false;
          // Default to the first available package or monthly/yearly if present
          if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
            _selectedPackage = offerings.current!.availablePackages.first;
          }
        });
      }
    } on PlatformException catch (e) {
      debugPrint("Error fetching offerings: $e");
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
      final customerInfo = await Purchases.purchasePackage(_selectedPackage!);
      if (customerInfo.entitlements.all["P.E.T Premium"]?.isActive == true) {
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

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1E1035), const Color(0xFF0F0B1E), const Color(0xFF0A0915)]
                : [const Color(0xFFF3E8FF), const Color(0xFFFAFAFA), Colors.white],
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
                      icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      TextButton(
                        onPressed: _restorePurchases,
                        child: Text(
                          'Restore',
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
                              color: AppTheme.accentPurple.withValues(alpha: 0.15),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentPurple.withValues(alpha: 0.2),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                )
                              ]
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              size: 72,
                              color: Colors.amber,
                            ),
                          )
                              .animate(onPlay: (controller) => controller.repeat(reverse: true))
                              .shimmer(duration: 2000.ms, color: Colors.amber.withValues(alpha: 0.3))
                              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1500.ms),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Unlock P.E.T Premium',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black87,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),
                        const SizedBox(height: 8),
                        Text(
                          'Gain access to elite wealth tracking features and AI-driven insights.',
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
                        const SizedBox(height: 36),

                        // Premium Features list
                        _buildFeatureRow(
                          icon: Icons.auto_awesome_rounded,
                          title: 'AI Financial Copilot',
                          subtitle: 'Custom advice & automated budget adjustments.',
                          color: const Color(0xFFEC4899),
                          isDark: isDark,
                        ).animate().fadeIn(delay: 250.ms, duration: 450.ms).slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          icon: Icons.account_balance_rounded,
                          title: 'Advanced Tax Buckets',
                          subtitle: 'Track 80C, 80D, HRA deductions dynamically.',
                          color: const Color(0xFF10B981),
                          isDark: isDark,
                        ).animate().fadeIn(delay: 350.ms, duration: 450.ms).slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          icon: Icons.insights_rounded,
                          title: 'Cashflow Forecasting',
                          subtitle: 'Runways, safe-to-spend targets & projections.',
                          color: const Color(0xFF8B5CF6),
                          isDark: isDark,
                        ).animate().fadeIn(delay: 450.ms, duration: 450.ms).slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          icon: Icons.timer_rounded,
                          title: 'Spending Focus Mode',
                          subtitle: 'Temporarily pause impulse transactions.',
                          color: const Color(0xFFF59E0B),
                          isDark: isDark,
                        ).animate().fadeIn(delay: 550.ms, duration: 450.ms).slideX(begin: -0.1, end: 0),
                        
                        const SizedBox(height: 40),
                        Text(
                          'Choose Your Subscription Plan',
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
                        else if (_offerings != null &&
                            _offerings!.current != null &&
                            _offerings!.current!.availablePackages.isNotEmpty)
                          ..._offerings!.current!.availablePackages.map((package) {
                            final isSelected = _selectedPackage == package;
                            return _buildPackageItem(package, isSelected, isDark)
                                .animate()
                                .fadeIn(delay: 100.ms)
                                .scale(begin: const Offset(0.97, 0.97), end: const Offset(1, 1), duration: 250.ms);
                          })
                        else
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24.0),
                              child: Text(
                                'No subscription packages available at this time.',
                                style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                              ),
                            ),
                          ),
                        const SizedBox(height: 120), // Bottom padding for content scroll clearance
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
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isDark
                            ? [Colors.transparent, const Color(0xFF0F0B1E).withValues(alpha: 0.95), const Color(0xFF0A0915)]
                            : [Colors.transparent, Colors.white.withValues(alpha: 0.95), Colors.white],
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
                            shadowColor: AppTheme.accentPurple.withValues(alpha: 0.4),
                          ),
                          onPressed: _isLoading ? null : _purchaseSelectedPackage,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'Subscribe & Continue',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Secured with Google Play billing. Cancel anytime.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                          textAlign: TextAlign.center,
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

  Widget _buildPackageItem(Package package, bool isSelected, bool isDark) {
    // Generate helpful duration markers for titles
    String durationTag = 'Subscription';
    bool isYearly = false;
    
    if (package.packageType == PackageType.lifetime) {
      durationTag = 'Lifetime Access';
    } else if (package.packageType == PackageType.annual) {
      durationTag = 'Yearly Plan';
      isYearly = true;
    } else if (package.packageType == PackageType.monthly) {
      durationTag = 'Monthly Plan';
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
              ? (isSelected ? AppTheme.accentPurple.withValues(alpha: 0.15) : AppTheme.surfaceDark)
              : (isSelected ? AppTheme.accentPurple.withValues(alpha: 0.08) : AppTheme.surfaceLight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentPurple
                : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
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
                      if (isYearly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentTeal.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.accentTeal.withValues(alpha: 0.5)),
                          ),
                          child: const Text(
                            'BEST VALUE',
                            style: TextStyle(
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
                    package.packageType == PackageType.lifetime
                        ? 'Pay once, unlock forever'
                        : 'Cancel anytime. Auto-renews.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              package.storeProduct.priceString,
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
