import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SunTheme {
  static const Color red = Color(0xFF8B0000);
  static const Color redDark = Color(0xFF5C0000);
  static const Color redLight = Color(0xFFB22222);
  static const Color gold = Color(0xFFDAA520);
  static const Color goldLight = Color(0xFFFFD700);
  static const Color black = Color(0xFF1A1A1A);
  static const Color green = Color(0xFF2E8B57);

  /// Gold border + red glow — เหมือนปุ่ม home
  static BoxDecoration cardDecoration({
    double radius = 14,
    Color bgColor = const Color(0xFF2A0A0A),
  }) => BoxDecoration(
    color: bgColor,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: const Color(0xFFFFD700).withOpacity(0.55),
      width: 1.5,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFCC2222).withOpacity(0.4),
        blurRadius: 12,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: const Color(0xFFFFD700).withOpacity(0.12),
        blurRadius: 18,
      ),
      BoxShadow(
        color: Colors.black.withOpacity(0.4),
        blurRadius: 6,
        offset: const Offset(0, 3),
      ),
    ],
  );

  /// Font family name — Prompt supports Thai + English
  static String get fontFamily => GoogleFonts.prompt().fontFamily ?? 'Prompt';

  static ThemeData get theme {
    // Use Prompt for all text — supports Thai + English in same font
    final textTheme = GoogleFonts.promptTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      scaffoldBackgroundColor: redDark,
      primaryColor: red,
      fontFamily: fontFamily,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: goldLight,
        surface: redDark,
        error: Colors.red,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: black,
        foregroundColor: goldLight,
        elevation: 0,
        titleTextStyle: GoogleFonts.prompt(
          color: goldLight,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gold.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: goldLight),
        ),
        hintStyle: GoogleFonts.prompt(color: Colors.white.withOpacity(0.5)),
        labelStyle: GoogleFonts.prompt(color: gold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: redDark,
          foregroundColor: goldLight,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.prompt(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      textTheme: textTheme.apply(bodyColor: gold, displayColor: goldLight),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: GoogleFonts.prompt(color: Colors.white, fontSize: 13),
      ),
    );
  }
}
