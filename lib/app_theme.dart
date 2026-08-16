import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color darkGreen = Color(0xFF2E7D32);
  static const Color deepGreen = Color(0xFF1B5E20);
  static const Color lightGreen = Color(0xFFEAF7EC);
  static const Color paleGreen = Color(0xFFF3FAF3);

  static const Color textDark = Color(0xFF223322);
  static const Color textGrey = Color(0xFF7C8B7C);

  // Status colors
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA726);
  static const Color success = Color(0xFF43A047);
  static const Color info = Color(0xFF1976D2);

  // Gradients
  static const List<Color> splashGradient = [
    Color(0xFF66BB6A),
    Color(0xFF2E7D32),
  ];

  static const List<Color> headerGradient = [
    Color(0xFF66BB6A),
    Color(0xFF2E7D32),
  ];

  // Module accent colors
  static const Color tradingBlue = Color(0xFF64B5F6);
  static const Color breedingPurple = Color(0xFFBA68C8);
  static const Color stockTeal = Color(0xFF4DB6AC);

  // Generic surface colors
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE0E0E0);
}

/// Small helper functions for consistent typography and styling
/// across the application.
class AppTheme {
  static TextStyle heading({
    double size = 24,
    Color color = AppColors.textDark,
    FontWeight weight = FontWeight.w700,
  }) {
    return TextStyle(
      fontFamily: 'Baloo2',
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  static TextStyle brand({
    double size = 28,
    Color color = Colors.white,
    FontWeight weight = FontWeight.w700,
  }) {
    return TextStyle(
      fontFamily: 'Amaranth',
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  static TextStyle body({
    double size = 14,
    Color color = AppColors.textGrey,
    FontWeight weight = FontWeight.w400,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      color: color,
      fontWeight: weight,
    );
  }

  /// White rounded-corner card decoration with a soft shadow.
  ///
  /// Used by Home / Palai / Stock stat cards,
  /// module tiles and list rows.
  static BoxDecoration card({
    double radius = 16,
  }) {
    return BoxDecoration(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,

      // App colors
      scaffoldBackgroundColor: AppColors.paleGreen,
      primaryColor: AppColors.primaryGreen,

      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryGreen,
      ),

      // Default application font
      fontFamily: 'Baloo2',

      // AppBar
      //
      // NOTE: iconTheme is intentionally left unset here. AppBar resolves
      // its back-button color from (in order) the widget's own `iconTheme`,
      // then `appBarTheme.iconTheme`, and only falls back to a screen's
      // `foregroundColor` if neither of those is set. Every screen in this
      // app sets `foregroundColor: AppColors.textDark` on a pale background,
      // expecting a dark back arrow — but a hardcoded white `iconTheme` here
      // used to win every time, rendering the back button invisible against
      // the light background. Leaving it unset lets each screen's
      // `foregroundColor` take effect as intended.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      // Text fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,

        hintStyle: body(
          size: 14,
        ),

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),

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
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.5,
          ),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1.2,
          ),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}