import 'package:flutter/material.dart';

class AppTheme {
  static const Color creamBg = Color(0xFFFDFCFB);
  static const Color primaryBlue = Color(0xFF0B5FFF); // Azul da sua Logo
  static const Color accentGreen = Color(0xFF10B981); // Verde Lucro
  static const Color cardWhite = Color(0xFFFFFFFF);

  static ThemeData get premiumTheme => ThemeData(
    scaffoldBackgroundColor: creamBg,
    primaryColor: primaryBlue,
    cardTheme: CardThemeData(
      color: cardWhite,
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  );
}
