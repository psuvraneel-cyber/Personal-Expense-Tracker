import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/theme/typography.dart';

/// A group of related rows in one rounded surface, separated by hairlines,
/// with an optional small label above it.
///
/// Use this instead of giving every row its own bordered card: one container
/// per group keeps the page calm and lets the content stand out.
class PetSection extends StatelessWidget {
  const PetSection({
    super.key,
    required this.children,
    this.title,
    this.trailing,
    this.padding = EdgeInsets.zero,
    this.dividerIndent = 68,
  });

  final List<Widget> children;

  /// Shown above the group in small capitals.
  final String? title;

  /// Sits at the end of the title line (e.g. a "See all" button).
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// Where hairlines start, so they line up with row text, not icons.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, indent: dividerIndent));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || trailing != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, Spacing.sm),
            child: Row(
              children: [
                if (title != null)
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title!.toUpperCase(),
                        style: AppTypography.overline(
                          color: dark
                              ? AppTheme.textTertiary
                              : AppTheme.textSecondaryLight,
                        ),
                      ),
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: dark ? AppTheme.cardDark : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(Spacing.radiusLg),
            border: dark
                ? null
                : Border.all(color: Colors.black.withAlpha(8), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Spacing.radiusLg),
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One line inside a [PetSection]: leading visual, title and subtitle, and a
/// trailing value or control.
class PetRow extends StatelessWidget {
  const PetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Adds a chevron after [trailing] for rows that open another screen.
  final bool showChevron;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: Spacing.md + 2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall(
                    color: titleColor ??
                        (dark
                            ? AppTheme.textPrimary
                            : AppTheme.textPrimaryLight),
                  ).copyWith(fontSize: 15),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall(
                      color: dark
                          ? AppTheme.textSecondary
                          : AppTheme.textSecondaryLight,
                    ).copyWith(fontSize: 13, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.md),
            trailing!,
          ],
          if (showChevron) ...[
            const SizedBox(width: Spacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: dark ? AppTheme.textTertiary : AppTheme.textSecondaryLight,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    // A row inside a group highlights rather than shrinks: scaling one slice
    // of a shared surface looks broken.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        splashFactory: InkRipple.splashFactory,
        highlightColor:
            (dark ? Colors.white : Colors.black).withAlpha(dark ? 10 : 8),
        child: row,
      ),
    );
  }
}
