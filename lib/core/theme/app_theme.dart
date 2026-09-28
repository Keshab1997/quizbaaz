import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

class AppTheme {
  /// Kept for callers that do not care about language (tests, previews).
  static ThemeData get darkTheme => darkThemeFor('en');

  /// Builds the theme with a text theme whose font actually contains the
  /// glyphs of [languageCode].
  ///
  /// This matters more than it looks: Poppins ships no Bengali glyphs, so a
  /// Bangla UI on Poppins renders as tofu boxes (or an ugly system fallback)
  /// on a lot of Android builds. Hind Siliguri covers Bengali *and* Latin, and
  /// Poppins covers Devanagari, so two families cover all three languages.
  static ThemeData darkThemeFor(String languageCode) {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme =
        languageCode == 'bn'
            ? GoogleFonts.hindSiliguriTextTheme(base.textTheme)
            : GoogleFonts.poppinsTextTheme(base.textTheme);
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      primaryColor: AppColors.neonPurple,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.neonPurple,
        secondary: AppColors.neonCyan,
        surface: AppColors.bgCard,
        error: AppColors.neonRed,
      ),
      textTheme: textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgNavy,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.neonCyan,
        linearTrackColor: Color(0x263C4B78),
      ),
    );
  }
}
