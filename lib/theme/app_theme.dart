import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg0 = Color(0xFFF8F9FC);
  static const bg1 = Color(0xFFFFFFFF);
  static const bg2 = Color(0xFFF1F3F9);
  static const bg3 = Color(0xFFE4E7F0);
  static const bgCard = Color(0xFFFFFFFF);
  static const border = Color(0xFFDDE0EA);
  static const borderSubtle = Color(0xFFEBEDF5);

  static const text0 = Color(0xFF0F172A);
  static const text1 = Color(0xFF334155);
  static const text2 = Color(0xFF64748B);
  static const text3 = Color(0xFF94A3B8);

  static const accent = Color(0xFF6366F1);
  static const accentLight = Color(0xFF818CF8);
  static const accentGlow = Color(0x186366F1);
  static const accentSurface = Color(0xFFEEF2FF);

  static const green = Color(0xFF10B981);
  static const greenSoft = Color(0xFFD1FAE5);
  static const yellow = Color(0xFFF59E0B);
  static const yellowSoft = Color(0xFFFEF3C7);
  static const red = Color(0xFFEF4444);
  static const redSoft = Color(0xFFFEE2E2);
  static const blue = Color(0xFF3B82F6);
  static const blueSoft = Color(0xFFDBEAFE);
  static const orange = Color(0xFFF97316);
  static const orangeSoft = Color(0xFFFFF7ED);
  static const pink = Color(0xFFEC4899);
  static const pinkSoft = Color(0xFFFCE7F3);
  static const purple = Color(0xFF8B5CF6);
  static const purpleSoft = Color(0xFFF3E8FF);
  static const indigo = Color(0xFF6366F1);
  static const indigoSoft = Color(0xFFEEF2FF);
  static const cyan = Color(0xFF06B6D4);
  static const cyanSoft = Color(0xFFCFFAFE);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg0,
      canvasColor: AppColors.bg1,
      primaryColor: AppColors.accent,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        secondary: AppColors.accentLight,
        surface: AppColors.bgCard,
        error: AppColors.red,
      ),
      dividerColor: AppColors.borderSubtle,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.text0, letterSpacing: -1),
        headlineMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text0, letterSpacing: -0.5),
        titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text0),
        titleMedium: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text1),
        bodyLarge: GoogleFonts.inter(fontSize: 15, color: AppColors.text1),
        bodyMedium: GoogleFonts.inter(fontSize: 13, color: AppColors.text2),
        labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.text3),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg1,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.text3),
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text2),
        floatingLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text1,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.text3,
        indicatorColor: AppColors.accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        dividerHeight: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.bg1, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
      dialogTheme: DialogThemeData(backgroundColor: AppColors.bg1, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 16),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.text3),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.green : AppColors.bg3),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
