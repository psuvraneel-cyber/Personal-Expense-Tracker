import 'package:flutter/material.dart';

/// Design-system color tokens extracted from gradient UI/UX background assets.
///
/// The gradient background pack uses vibrant purple → blue → teal flows with
/// warm accent pops. These tokens map that palette onto the existing P.E.T
/// wallet aesthetic while adding the new gradient vocabulary.
///
/// Font note: The asset pack recommends **Open Sans**. P.E.T already ships
/// **Poppins** (bundled in `google_fonts/`), which is geometrically similar but
/// offers wider weight variety. We keep Poppins and add Open Sans only as an
/// optional secondary (body-copy) typeface.
abstract final class ColorTokens {
  // ─────────────────────────── Primary gradient stops ──────────────────────
  /// Deep indigo – hero gradient start (dark mode scaffold)
  static const Color gradientStart = Color(0xFF1A0533);

  /// Rich violet – hero gradient mid
  static const Color gradientMid = Color(0xFF4A1A8A);

  /// Electric purple – hero gradient end / accent anchor
  static const Color gradientEnd = Color(0xFF8B5CF6);

  /// Warm magenta – warm accent gradient start
  static const Color warmStart = Color(0xFFE040A0);

  /// Coral pink – warm accent gradient end
  static const Color warmEnd = Color(0xFFF97316);

  /// Teal cyan – cool accent
  static const Color coolAccent = Color(0xFF06B6D4);

  /// Aqua green – secondary cool accent
  static const Color coolSecondary = Color(0xFF14B8A6);

  // ─────────────────────────── Semantic colors ─────────────────────────────
  static const Color income = Color(0xFF10B981);
  static const Color expense = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  /// Transfers between the user's own accounts: neither income nor spending.
  static const Color transfer = info;

  // ─────────────────────────── Dark palette ────────────────────────────────
  static const Color darkBg = Color(0xFF0D0B1E);
  static const Color darkSurface = Color(0xFF141127);
  static const Color darkCard = Color(0xFF1A1731);
  static const Color darkCardElevated = Color(0xFF1E1B33);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkTextTertiary = Color(0xFF6B7280);
  static const Color darkBorder = Color(0x0FFFFFFF); // 6 % white

  // ─────────────────────────── Light palette ───────────────────────────────
  static const Color lightBg = Color(0xFFF5F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF1F5F9);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);
  static const Color lightBorder = Color(0x14000000); // 8 % black

  // ─────────────────────────── Accent ──────────────────────────────────────
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentTeal = Color(0xFF14B8A6);

  // ─────────────────────────── Pre-built gradients ─────────────────────────

  /// Primary hero gradient – use on dashboard header / splash
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
    stops: [0.0, 0.5, 1.0],
  );

  /// Warm accent gradient – CTAs, highlights
  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [warmStart, warmEnd],
  );

  /// Cool accent gradient
  static const LinearGradient coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [coolAccent, coolSecondary],
  );

  /// Full-screen background gradient (dark)
  static const LinearGradient darkScreenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF150D2E), Color(0xFF0D0B1E), Color(0xFF0A0818)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Full-screen background gradient (light)
  static const LinearGradient lightScreenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF0EAFF), Color(0xFFF5F7FB), Color(0xFFFFFFFF)],
    stops: [0.0, 0.4, 1.0],
  );

  /// Card shimmer gradient (dark)
  static const LinearGradient darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkCardElevated, darkCard],
  );

  /// Card shimmer gradient (light)
  static const LinearGradient lightCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
  );

  /// Income gradient
  static const LinearGradient incomeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );

  /// Expense gradient
  static const LinearGradient expenseGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
  );

  /// Transfer gradient
  static const LinearGradient transferGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
  );

  /// Purple accent gradient
  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
  );

  /// Teal accent gradient
  static const LinearGradient tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
  );

  // ─────────────────────────── Status (scores, budget use) ──────────────────
  /// For scores and how much of a budget is used.
  static const Color good = Color(0xFF00C853);
  static const Color caution = Color(0xFFFFB300);
  static const Color nearLimit = Color(0xFFFF9800);
  static const Color alert = Color(0xFFFF6B6B);

  /// Colour for how much of a budget is used (0.6 = 60 %).
  static Color budgetUse(double fraction) {
    if (fraction < 0.60) return good;
    if (fraction < 0.85) return caution;
    if (fraction < 1.0) return nearLimit;
    return alert;
  }

  /// Colour for a 0–100 score.
  static Color score(int score) {
    if (score >= 70) return good;
    if (score >= 40) return caution;
    return alert;
  }

  /// Home hero surface: deep violet in dark mode; in light mode it follows
  /// the time of day (blue morning, teal afternoon, violet evening).
  static LinearGradient homeHero({required bool isDark, DateTime? now}) {
    if (isDark) return _heroDark;
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return _heroMorning;
    if (hour < 17) return _heroAfternoon;
    return _heroEvening;
  }

  static const LinearGradient _heroDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1C3E), Color(0xFF2D1B69)],
  );
  static const LinearGradient _heroMorning = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3D5AFE), Color(0xFF5C6BC0)],
  );
  static const LinearGradient _heroAfternoon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00897B), Color(0xFF3D5AFE)],
  );
  static const LinearGradient _heroEvening = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C4DFF), Color(0xFF1A237E)],
  );

  // ─────────────────────────── Helpers ─────────────────────────────────────

  /// Returns the appropriate screen gradient for the current brightness.
  static LinearGradient screenGradient(Brightness brightness) =>
      brightness == Brightness.dark ? darkScreenGradient : lightScreenGradient;

  /// Returns the appropriate card gradient for the current brightness.
  static LinearGradient cardGradient(Brightness brightness) =>
      brightness == Brightness.dark ? darkCardGradient : lightCardGradient;
}
