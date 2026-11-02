import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/spacing.dart';

class AppTheme {
  // ───────────── Semantic color aliases (backward-compatible) ─────────────
  static const Color primaryDark = ColorTokens.darkBg;
  static const Color surfaceDark = ColorTokens.darkSurface;
  static const Color cardDark = ColorTokens.darkCard;
  static const Color accentPurple = ColorTokens.accentPurple;
  static const Color accentTeal = ColorTokens.accentTeal;
  static const Color incomeGreen = ColorTokens.income;
  static const Color expenseRed = ColorTokens.expense;
  static const Color warningYellow = ColorTokens.warning;
  static const Color textPrimary = ColorTokens.darkTextPrimary;
  static const Color textSecondary = ColorTokens.darkTextSecondary;
  static const Color textTertiary = ColorTokens.darkTextTertiary;

  static const Color primaryLight = ColorTokens.lightBg;
  static const Color surfaceLight = ColorTokens.lightSurface;
  static const Color cardLight = ColorTokens.lightCard;
  static const Color textPrimaryLight = ColorTokens.lightTextPrimary;
  static const Color textSecondaryLight = ColorTokens.lightTextSecondary;

  static const Color cardPurpleAccent = Color(0xFF7B3FE4);
  static const Color cardDarkSurface = ColorTokens.darkCardElevated;

  // ───────────── Gradient aliases (backward-compatible) ──────────────────
  static const LinearGradient purpleGradient = ColorTokens.purpleGradient;
  static const LinearGradient tealGradient = ColorTokens.tealGradient;
  static const LinearGradient incomeGradient = ColorTokens.incomeGradient;
  static const LinearGradient expenseGradient = ColorTokens.expenseGradient;

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  );

  static const LinearGradient onboardingGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A0F3C), Color(0xFF0D0B1E)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E1B33), Color(0xFF151229)],
  );

  // ───────────── NEW — design-asset gradient backgrounds ─────────────────
  /// Primary hero gradient from gradient-colored UI/UX background pack.
  static const LinearGradient designHeroGradient = ColorTokens.heroGradient;

  /// Warm accent gradient (magenta → coral).
  static const LinearGradient warmAccentGradient = ColorTokens.warmGradient;

  /// Full-screen dark background gradient.
  static const LinearGradient screenDarkGradient =
      ColorTokens.darkScreenGradient;

  /// Full-screen light background gradient.
  static const LinearGradient screenLightGradient =
      ColorTokens.lightScreenGradient;

  static ThemeData darkTheme = _build(Brightness.dark);

  static ThemeData lightTheme = _build(Brightness.light);

  /// One theme for both brightnesses, so light and dark stay in step.
  /// Colours are the existing palette; this only sets how components use it.
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? primaryDark : primaryLight;
    final card = dark ? cardDark : surfaceLight;
    final raised = dark ? cardDarkSurface : surfaceLight;
    final fill = dark ? surfaceDark : cardLight;
    final text = dark ? textPrimary : textPrimaryLight;
    final text2 = dark ? textSecondary : textSecondaryLight;
    final hairline =
        dark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(8);
    final divider =
        dark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(8);

    const sm = Spacing.radiusSm;
    const md = Spacing.radiusMd;
    const lg = Spacing.radiusLg;
    final buttonText = GoogleFonts.poppins(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 14);
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(md));

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      primaryColor: accentPurple,
      colorScheme: dark
          ? const ColorScheme.dark(
              primary: accentPurple,
              secondary: accentTeal,
              surface: surfaceDark,
              error: expenseRed,
            )
          : const ColorScheme.light(
              primary: accentPurple,
              secondary: accentTeal,
              surface: surfaceLight,
              error: expenseRed,
            ),
      textTheme: GoogleFonts.poppinsTextTheme(
        TextTheme(
          headlineLarge: TextStyle(
            color: text,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.6,
          ),
          headlineMedium: TextStyle(
            color: text,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          headlineSmall: TextStyle(
            color: text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleLarge: TextStyle(
            color: text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: TextStyle(color: text, fontSize: 16),
          bodyMedium: TextStyle(color: text2, fontSize: 14),
          bodySmall: const TextStyle(color: textTertiary, fontSize: 12),
          labelLarge: TextStyle(
            color: text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(lg),
          side: dark
              ? BorderSide.none
              : BorderSide(color: Colors.black.withAlpha(8), width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: accentPurple,
        unselectedItemColor: textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(lg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(md),
          borderSide: BorderSide(color: hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(md),
          borderSide: const BorderSide(color: accentPurple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(md),
          borderSide: const BorderSide(color: expenseRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(md),
          borderSide: const BorderSide(color: expenseRed, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textTertiary),
        labelStyle: TextStyle(color: text2),
        floatingLabelStyle: const TextStyle(color: accentPurple),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentPurple,
          foregroundColor: Colors.white,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: buttonShape,
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentPurple,
          foregroundColor: Colors.white,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: buttonShape,
          side: BorderSide(color: hairline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentPurple,
          textStyle: buttonText.copyWith(fontSize: 14),
          shape: buttonShape,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: fill,
        selectedColor: accentPurple.withAlpha(dark ? 50 : 25),
        labelStyle: TextStyle(color: text2, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sm)),
        side: BorderSide(color: hairline),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : text2,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accentPurple : fill,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.transparent : hairline,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: text2,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 10,
        titleTextStyle: GoogleFonts.poppins(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: GoogleFonts.poppins(color: text2, fontSize: 13),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raised,
        modalBackgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: dark ? Colors.white24 : Colors.black26,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? cardDarkSurface : textPrimaryLight,
        contentTextStyle: GoogleFonts.poppins(
          color: dark ? textPrimary : Colors.white,
          fontSize: 14,
        ),
        actionTextColor: dark ? accentPurple : const Color(0xFFC4B5FD),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(md),
          side: dark ? BorderSide(color: hairline) : BorderSide.none,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(md),
          side: BorderSide(color: hairline),
        ),
        textStyle: GoogleFonts.poppins(color: text, fontSize: 14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentPurple,
        linearTrackColor: fill,
        circularTrackColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(lg)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? cardDarkSurface : textPrimaryLight,
          borderRadius: BorderRadius.circular(sm),
        ),
        textStyle: GoogleFonts.poppins(
          color: dark ? textPrimary : Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }
}
