import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale for P.E.T design system.
///
/// Primary typeface: **Poppins** (bundled).
/// Secondary typeface: **Open Sans** (from design-asset recommendation,
/// resolved via google_fonts at build time with `allowRuntimeFetching = false`
/// — only used if Open Sans .ttf files are added to `google_fonts/`).
///
/// Follows Material 3 type-scale naming with custom extensions for the
/// expense-tracker domain (hero balance, currency amounts, etc.).
abstract final class AppTypography {
  // ─────────────────────── Headlines ──────────────────────────────────────
  static TextStyle displayLarge({Color? color}) => GoogleFonts.poppins(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.15,
        color: color,
      );

  static TextStyle displayMedium({Color? color}) => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        height: 1.2,
        color: color,
      );

  static TextStyle displaySmall({Color? color}) => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.25,
        color: color,
      );

  // ─────────────────────── Titles ─────────────────────────────────────────
  static TextStyle titleLarge({Color? color}) => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: color,
      );

  static TextStyle titleMedium({Color? color}) => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: color,
      );

  static TextStyle titleSmall({Color? color}) => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: color,
      );

  // ─────────────────────── Body ───────────────────────────────────────────
  static TextStyle bodyLarge({Color? color}) => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  static TextStyle bodySmall({Color? color}) => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  // ─────────────────────── Labels ─────────────────────────────────────────
  static TextStyle labelLarge({Color? color}) => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.4,
        color: color,
      );

  static TextStyle labelMedium({Color? color}) => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        height: 1.4,
        color: color,
      );

  static TextStyle labelSmall({Color? color}) => GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        height: 1.4,
        color: color,
      );

  // ─────────────────────── Domain-specific ────────────────────────────────

  /// Large hero balance number on dashboard.
  static TextStyle heroBalance({Color? color}) => GoogleFonts.poppins(
        fontSize: 38,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
        height: 1.1,
        color: color,
      );

  /// Currency amount inside cards.
  static TextStyle currencyAmount({Color? color}) => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
        color: color,
      );

  /// Small currency (e.g. transaction list).
  static TextStyle currencySmall({Color? color}) => GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.3,
        color: color,
      );

  /// Caption / timestamp text.
  static TextStyle caption({Color? color}) => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        height: 1.4,
        color: color,
      );

  // ─────────────────────── Redesign: Hero & Metric ──────────────────────────

  /// Hero greeting name (e.g. "Good Morning, Arjun!").
  static TextStyle heroGreeting({Color? color}) => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: color,
      );

  /// Metric pill value (e.g. "₹842").
  static TextStyle metricValue({Color? color}) => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.2,
        color: color,
      );

  /// Metric pill label (e.g. "Spent Today").
  static TextStyle metricLabel({Color? color}) => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      );

  /// Section header (e.g. "This Month", "Top Categories").
  static TextStyle sectionHeader({Color? color}) => GoogleFonts.poppins(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: color,
      );

  // ─────────────────────── Redesign: Financial Amounts ─────────────────────

  /// Large financial amount (e.g. "₹18,400" in hero cards).
  static TextStyle financialLarge({Color? color}) => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
        color: color,
      );

  /// Medium financial amount (e.g. inline list amounts).
  static TextStyle financialMedium({Color? color}) => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      );

  /// Small financial amount (e.g. category summaries).
  static TextStyle financialSmall({Color? color}) => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      );
}
