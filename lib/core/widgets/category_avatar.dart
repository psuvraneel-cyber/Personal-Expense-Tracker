import 'package:flutter/material.dart';
import 'package:pet/core/theme/spacing.dart';

/// An icon on a soft tint of its own colour: the one way the app shows a
/// category, account or feature next to a row, instead of emoji.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withAlpha(dark ? 38 : 28),
          borderRadius: BorderRadius.circular(
            size >= 36 ? Spacing.radiusMd - 2 : Spacing.radiusSm,
          ),
        ),
        child: Icon(icon, size: size * 0.5, color: color),
      ),
    );
  }
}
