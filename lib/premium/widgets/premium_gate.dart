import 'dart:ui' show ImageFilter;
import 'package:pet/l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/screens/purchase_screen.dart';
import 'package:pet/core/theme/app_theme.dart';

/// Shows [child] to premium users. Free users get an upgrade card instead —
/// over a blurred preview of the real screen when [showPreview] is true, so
/// they can see the feature working on their own data before paying.
class PremiumGate extends StatelessWidget {
  final Widget child;
  final String title;
  final String subtitle;
  final bool requiresExperimental;

  /// Render [child] blurred and non-interactive behind the upgrade card.
  final bool showPreview;

  /// Optional personalised hook shown on the card, e.g. "We found 7
  /// recurring payments costing ₹2,340 a month". Return null to omit.
  final String? Function(BuildContext context)? teaser;

  const PremiumGate({
    super.key,
    required this.child,
    required this.title,
    required this.subtitle,
    this.requiresExperimental = false,
    this.showPreview = false,
    this.teaser,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PremiumProvider>(
      builder: (context, premium, _) {
        if (premium.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (premium.isPremium &&
            (!requiresExperimental || premium.experimentalEnabled)) {
          return child;
        }

        final card = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: _UpgradeCard(
              title: title,
              subtitle: subtitle,
              teaser: premium.isPremium ? null : teaser?.call(context),
              isPremium: premium.isPremium,
              onPressed: () {
                if (!premium.isPremium) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PurchaseScreen(source: title),
                    ),
                  );
                } else if (requiresExperimental) {
                  premium.setExperimental(true);
                }
              },
            ),
          ),
        );

        if (!showPreview) return card;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          children: [
            // Hidden from screen readers and taps: it's a picture of the
            // feature, not a usable copy of it.
            Positioned.fill(
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                    child: child,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: (isDark ? AppTheme.primaryDark : AppTheme.primaryLight)
                    .withValues(alpha: 0.35),
              ),
            ),
            card,
          ],
        );
      },
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    required this.title,
    required this.subtitle,
    required this.teaser,
    required this.isPremium,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String? teaser;
  final bool isPremium;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(
                duration: 2500.ms,
                color: Colors.white.withValues(alpha: 0.2),
              )
              .scale(
                begin: const Offset(0.96, 0.96),
                end: const Offset(1.04, 1.04),
                duration: 2000.ms,
              ),
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
          if (teaser != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.accentTeal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                teaser!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
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
            onPressed: onPressed,
            child: Text(
              !isPremium
                  ? AppLocalizations.of(context).gateUnlock
                  : 'Enable Experimental Features',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
