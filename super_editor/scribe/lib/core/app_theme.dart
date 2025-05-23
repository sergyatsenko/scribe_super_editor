import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E3440),
        brightness: Brightness.light,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          fontFamily: 'SF Pro Text',
          fontSize: 16,
          height: 1.6,
          letterSpacing: 0.0,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'SF Pro Text',
          fontSize: 14,
          height: 1.5,
          letterSpacing: 0.0,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5E81AC),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF2E3440),
        onSurface: const Color(0xFFECEFF4),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          fontFamily: 'SF Pro Text',
          fontSize: 16,
          height: 1.6,
          letterSpacing: 0.0,
          color: Color(0xFFECEFF4),
        ),
        bodyMedium: TextStyle(
          fontFamily: 'SF Pro Text',
          fontSize: 14,
          height: 1.5,
          letterSpacing: 0.0,
          color: Color(0xFFECEFF4),
        ),
        headlineLarge: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: Color(0xFFECEFF4),
        ),
        headlineMedium: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: Color(0xFFECEFF4),
        ),
        headlineSmall: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: Color(0xFFECEFF4),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Color(0xFF2E3440),
        foregroundColor: Color(0xFFECEFF4),
      ),
    );
  }
}
