import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';

/// Enhanced FeatureCard with gradient accent, a live badge, and a shimmer.
class FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color accentColor;
  final String? badge; // e.g. "3 goals" or "₹4,200 saved"
  final List<Color>? gradientColors;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.accentColor = AppTheme.accentPurple,
    this.badge,
    this.gradientColors,
  });

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors =
        widget.gradientColors ??
        [
          widget.accentColor.withAlpha(isDark ? 40 : 28),
          widget.accentColor.withAlpha(isDark ? 18 : 10),
        ];

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.accentColor.withAlpha(isDark ? 40 : 30),
        ),
        boxShadow: widget.onTap != null
            ? [
                BoxShadow(
                  color: widget.accentColor.withAlpha(isDark ? 18 : 12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.accentColor.withAlpha(isDark ? 40 : 28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, size: 20, color: widget.accentColor),
              ),
              const Spacer(),
              Icon(
                widget.onTap != null
                    ? Icons.chevron_right_rounded
                    : Icons.lock_outline_rounded,
                size: 18,
                color: AppTheme.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall),
          if (widget.badge != null || widget.onTap == null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.onTap != null
                    ? widget.accentColor.withAlpha(isDark ? 50 : 35)
                    : AppTheme.textTertiary.withAlpha(isDark ? 40 : 25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.badge ?? 'Coming Soon',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: widget.onTap != null
                      ? widget.accentColor
                      : AppTheme.textTertiary,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.onTap == null) {
      return Opacity(opacity: 0.6, child: card);
    }

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap!();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: card),
    );
  }
}
