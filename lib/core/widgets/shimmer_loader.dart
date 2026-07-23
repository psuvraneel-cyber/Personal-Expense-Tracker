import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A shimmering placeholder rectangle for skeleton loading states.
///
/// Adapts its shimmer color to the current theme (light/dark).
/// Uses [flutter_animate] for the shimmer effect.
class ShimmerLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: isDark
                ? Colors.white.withAlpha(15)
                : Colors.black.withAlpha(10),
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: const Duration(milliseconds: 1200),
          color: isDark
              ? Colors.white.withAlpha(20)
              : Colors.black.withAlpha(15),
        );
  }
}

/// Pre-built skeleton for a single transaction list item.
///
/// Shows a circular icon placeholder, two text lines, and an amount placeholder.
class TransactionSkeleton extends StatelessWidget {
  const TransactionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const ShimmerLoader(width: 44, height: 44, borderRadius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerLoader(width: 120, height: 14),
                SizedBox(height: 6),
                ShimmerLoader(width: 80, height: 10),
              ],
            ),
          ),
          const ShimmerLoader(width: 60, height: 16),
        ],
      ),
    );
  }
}

/// Pre-built skeleton for a summary card (e.g. income/expense total).
class SummaryCardSkeleton extends StatelessWidget {
  const SummaryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          ShimmerLoader(width: 80, height: 12),
          SizedBox(height: 10),
          ShimmerLoader(width: 120, height: 22),
          SizedBox(height: 8),
          ShimmerLoader(width: 60, height: 10),
        ],
      ),
    );
  }
}

/// A list of [TransactionSkeleton] items — drop-in replacement for loading.
class TransactionListSkeleton extends StatelessWidget {
  final int itemCount;

  const TransactionListSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(itemCount, (_) => const TransactionSkeleton()),
    );
  }
}
