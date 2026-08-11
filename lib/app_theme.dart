import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-wide color palette. Kept here (not inside a screen file) because
/// colors are shared visual constants, not screen-specific logic.
class AppColors {
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color darkGreen = Color(0xFF2E7D32);
  static const Color deepGreen = Color(0xFF1B5E20);
  static const Color lightGreen = Color(0xFFEAF7EC);
  static const Color paleGreen = Color(0xFFF3FAF3);

  static const Color textDark = Color(0xFF223322);
  static const Color textGrey = Color(0xFF7C8B7C);

  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA726);
  static const Color success = Color(0xFF43A047);

  static const List<Color> splashGradient = [Color(0xFF66BB6A), Color(0xFF2E7D32)];
  static const List<Color> headerGradient = [Color(0xFF66BB6A), Color(0xFF2E7D32)];
}

/// Small helper functions for consistent typography across screens.
class AppTheme {
  static TextStyle heading({
    double size = 24,
    Color color = AppColors.textDark,
    FontWeight weight = FontWeight.w700,
  }) {
    return TextStyle(fontFamily: 'Baloo2', fontSize: size, fontWeight: weight, color: color);
  }

  static TextStyle brand({
    double size = 28,
    Color color = Colors.white,
    FontWeight weight = FontWeight.w700,
  }) {
    return TextStyle(fontFamily: 'Amaranth', fontSize: size, fontWeight: weight, color: color);
  }

  static TextStyle body({
    double size = 14,
    Color color = AppColors.textGrey,
    FontWeight weight = FontWeight.w400,
  }) {
    return GoogleFonts.poppins(fontSize: size, color: color, fontWeight: weight);
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.paleGreen,
      primaryColor: AppColors.primaryGreen,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryGreen),
      fontFamily: 'Baloo2',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: body(size: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }
}