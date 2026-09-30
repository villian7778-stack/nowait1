import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF1F4CDD);
  static const secondary = Color(0xFF5B3CDD);
  static const tertiary = Color(0xFF006B2D);
  static const error = Color(0xFFBA1A1A);

  static const surface = Color(0xFFFAF8FF);
  static const surfaceBright = Color(0xFFFAF8FF);
  static const surfaceDim = Color(0xFFD2D9F4);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF2F3FF);
  static const surfaceContainer = Color(0xFFEAEDFF);
  static const surfaceContainerHigh = Color(0xFFE2E7FF);
  static const surfaceContainerHighest = Color(0xFFDAE2FD);
  static const surfaceVariant = Color(0xFFDAE2FD);

  static const onSurface = Color(0xFF131B2E);
  static const onSurfaceVariant = Color(0xFF444655);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onSecondary = Color(0xFFFFFFFF);
  static const onTertiary = Color(0xFFFFFFFF);
  static const onError = Color(0xFFFFFFFF);

  static const primaryContainer = Color(0xFF4167F7);
  static const secondaryContainer = Color(0xFF7459F7);
  static const tertiaryContainer = Color(0xFF00873B);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  static const tertiaryFixed = Color(0xFF6BFF8F);
  static const onTertiaryFixed = Color(0xFF002109);

  static const outline = Color(0xFF747687);
  static const inverseSurface = Color(0xFF283044);
  static const inverseOnSurface = Color(0xFFEEF0FF);

  static const background = Color(0xFFFAF8FF);
  static const onBackground = Color(0xFF131B2E);

  static const shadowPrimary = Color(0x141F4CDD); // rgba(31,76,221,0.08)

  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get primaryGradient135 => const LinearGradient(
        colors: [primary, secondary],
        transform: GradientRotation(2.356), // 135 degrees
      );
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        error: AppColors.error,
        onError: AppColors.onError,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        surfaceContainerHighest: AppColors.surfaceContainerHighest,
        outline: AppColors.outline,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: _buildTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface.withValues(alpha: 0.85),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return TextTheme(
      displayLarge: GoogleFonts.plusJakartaSans(
        fontSize: 56, fontWeight: FontWeight.w700, letterSpacing: -0.02 * 56,
        color: AppColors.onSurface,
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        fontSize: 45, fontWeight: FontWeight.w700, letterSpacing: -0.02 * 45,
        color: AppColors.onSurface,
      ),
      displaySmall: GoogleFonts.plusJakartaSans(
        fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.02 * 36,
        color: AppColors.onSurface,
      ),
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.01 * 32,
        color: AppColors.onSurface,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.01 * 28,
        color: AppColors.onSurface,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.01 * 24,
        color: AppColors.onSurface,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 18, fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400,
        color: AppColors.onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.02 * 14,
        color: AppColors.onSurface,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.02 * 12,
        color: AppColors.onSurface,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.02 * 11,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}
