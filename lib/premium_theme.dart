import 'package:flutter/material.dart';

/* * VERSÃO: 1.0.0
 * PADRÃO: PREMIUM VISUAL - RAIHOM BARBOSA
 * DESCRIÇÃO: Tema centralizado para Controle Total, Gestão Yahweh e Caser.
 */

class PremiumTheme {
  // Cores principais (Paleta Moderna e Sóbria)
  static const Color primaryBlue = Color(0xFF0052CC); // Azul Premium
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color backgroundDark = Color(0xFF0F172A); // Slate dark
  static const Color surfaceDark = Color(0xFF1E293B);
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: backgroundLight,
      
      // Estilo de Cards (Moderno com bordas de 20px)
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
          side: BorderSide(color: Colors.grey.withOpacity(0.1), width: 1),
        ),
      ),

      // Estilo de Inputs (Clean e Arredondado)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
      ),

      // Botões Premium
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 2,
        ),
      ),

      // Tipografia
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
          letterSpacing: -0.5,
        ),
        bodyLarge: TextStyle(color: Color(0xFF475569)),
      ),
    );
  }

  // Versão Dark para um visual Enterprise
  static ThemeData get darkTheme {
    return lightTheme.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      cardTheme: lightTheme.cardTheme.copyWith(
        color: surfaceDark,
      ),
      inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
        fillColor: surfaceDark,
      ),
    );
  }
}