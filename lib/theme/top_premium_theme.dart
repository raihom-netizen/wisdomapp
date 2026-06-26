import 'package:flutter/material.dart';

class TopPremiumTheme {
  static LinearGradient headerGradient() {
    return const LinearGradient(
      colors: [Color(0xFF0B5FFF), Color(0xFF4FA3FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFDFCFB),
      primaryColor: const Color(0xFF0B5FFF),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B5FFF), foregroundColor: Colors.white),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
