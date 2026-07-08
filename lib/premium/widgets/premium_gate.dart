import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/screens/purchase_screen.dart';
import 'package:pet/core/theme/app_theme.dart';

class PremiumGate extends StatelessWidget {
  final Widget child;
  final String title;
  final String subtitle;
  final bool requiresExperimental;

  const PremiumGate({
    super.key,
    required this.child,
    required this.title,
    required this.subtitle,
    this.requiresExperimental = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Consumer<PremiumProvider>(
      builder: (context, premium, _) {
        if (premium.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (premium.isPremium &&
            (!requiresExperimental || premium.experimentalEnabled)) {
          return child;
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.accentPurple.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentPurple.withValues(alpha: 0.08),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPurple.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 48,
                      color: AppTheme.accentPurple,
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .shimmer(duration: 2500.ms, color: Colors.white.withValues(alpha: 0.2))
                   .scale(begin: const Offset(0.96, 0.96), end: const Offset(1.04, 1.04), duration: 2000.ms),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      minimumSize: const Size(double.infinity, 50),
                      elevation: 4,
                      shadowColor: AppTheme.accentPurple.withValues(alpha: 0.3),
                    ),
                    onPressed: () {
                      if (!premium.isPremium) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PurchaseScreen(),
                          ),
                        );
                      } else if (requiresExperimental) {
                        premium.setExperimental(true);
                      }
                    },
                    child: Text(
                      !premium.isPremium ? 'Unlock Premium' : 'Enable Experimental Features',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
