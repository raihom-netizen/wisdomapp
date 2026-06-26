import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Padrão gráfico Gemini: moderno, premium, gráficos top.
/// Cores suaves, bordas 20–24, sombras sutis, tipografia clara.
class GeminiTheme {
  GeminiTheme._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color secondary = Color(0xFF7C3AED);
  static const Color accent = Color(0xFF0EA5E9);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8FAFC);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);

  static const double cardRadius = 24;
  static const double buttonRadius = 20;
  static const double inputRadius = 16;

  // Performance: o tema (com dezenas de estilos de texto) é construído UMA vez
  // e reaproveitado. Antes era recriado a cada build do MaterialApp.
  static ThemeData? _lightCache;
  static ThemeData? _darkCache;

  static ThemeData get light => _lightCache ??= ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.light(
          primary: primary,
          onPrimary: Colors.white,
          secondary: secondary,
          onSecondary: Colors.white,
          surface: surface,
          onSurface: textPrimary,
          surfaceContainerHighest: const Color(0xFFF1F5F9),
          error: error,
          onError: Colors.white,
        ),
        textTheme: GoogleFonts.interTextTheme().copyWith(
          displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
          displayMedium: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w700, color: textPrimary),
          headlineMedium: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
          titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
          titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
          bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
          bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: textSecondary),
          labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
        ),
        // Padrão Clean Premium: faixa azul no topo, letras brancas e fortes (todas as telas)
        appBarTheme: AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
          iconTheme: const IconThemeData(color: Colors.white, size: 24),
        ),
        /* iPhone 13/14 e todas versões: ícones com tamanho explícito para não falhar ao carregar */
        iconTheme: const IconThemeData(size: 24, opacity: 1),
        primaryIconTheme: const IconThemeData(size: 24, color: primary),
        cardTheme: CardThemeData(
          elevation: 0,
          color: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          labelStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: primary,
          unselectedItemColor: textMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedIconTheme: const IconThemeData(size: 24),
          unselectedIconTheme: IconThemeData(size: 24, color: textMuted),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0), thickness: 1),
        // Blindagem toque: iPhone 13/14/15, Android — alvo mínimo 48px (Material + Apple HIG)
        materialTapTargetSize: MaterialTapTargetSize.padded,
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        listTileTheme: const ListTileThemeData(
          minLeadingWidth: 40,
          minVerticalPadding: 12,
        ),
      );

  /// Tema claro com cor primária explícita (uso interno / telas específicas).
  static ThemeData lightWithPrimary(Color primaryColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: primaryColor.withOpacity(0.8),
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: const Color(0xFFF1F5F9),
        error: error,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary),
        displayMedium: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w700, color: textPrimary),
        headlineMedium: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
        titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: textSecondary),
        labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      ),
      // Padrão Clean Premium: faixa azul no topo, letras brancas e fortes (todas as telas)
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
      ),
      iconTheme: const IconThemeData(size: 24, opacity: 1),
      primaryIconTheme: IconThemeData(size: 24, color: primaryColor),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primaryColor,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedIconTheme: IconThemeData(size: 24, color: primaryColor),
        unselectedIconTheme: IconThemeData(size: 24, color: textMuted),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0), thickness: 1),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minLeadingWidth: 40,
        minVerticalPadding: 12,
      ),
    );
  }

  static const Color _darkSurface = Color(0xFF1E293B);
  static const Color _darkBackground = Color(0xFF0F172A);
  static const Color _darkTextPrimary = Color(0xFFF8FAFC);
  static const Color _darkTextSecondary = Color(0xFFCBD5E1);
  static const Color _darkTextMuted = Color(0xFF94A3B8);

  /// Tema escuro padrão (memoizado).
  static ThemeData get dark => _darkCache ??= darkWithPrimary(primary);

  /// Tema escuro com cor primária customizada.
  static ThemeData darkWithPrimary(Color primaryColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkBackground,
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: primaryColor.withOpacity(0.8),
        onSecondary: Colors.white,
        surface: _darkSurface,
        onSurface: _darkTextPrimary,
        surfaceContainerHighest: const Color(0xFF334155),
        error: error,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800, color: _darkTextPrimary),
        displayMedium: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w700, color: _darkTextPrimary),
        headlineMedium: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: _darkTextPrimary),
        titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: _darkTextPrimary),
        titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: _darkTextPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: _darkTextPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: _darkTextSecondary),
        labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _darkTextPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
      ),
      iconTheme: const IconThemeData(size: 24, opacity: 1),
      primaryIconTheme: IconThemeData(size: 24, color: primaryColor),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF334155),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: _darkTextSecondary, fontWeight: FontWeight.w500),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _darkSurface,
        selectedItemColor: primaryColor,
        unselectedItemColor: _darkTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedIconTheme: IconThemeData(size: 24, color: primaryColor),
        unselectedIconTheme: IconThemeData(size: 24, color: _darkTextMuted),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF475569), thickness: 1),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minLeadingWidth: 40,
        minVerticalPadding: 12,
      ),
    );
  }

  /// Card com sombra suave no padrão Gemini
  static BoxDecoration cardDecoration({Color? color, List<Color>? gradientColors}) {
    return BoxDecoration(
      color: gradientColors == null ? (color ?? surface) : null,
      gradient: gradientColors != null
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            )
          : null,
      borderRadius: BorderRadius.circular(cardRadius),
      boxShadow: [
        BoxShadow(
          color: primary.withOpacity(0.06),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Gradiente premium para cards de destaque
  static const List<Color> gradientPrimary = [Color(0xFF2563EB), Color(0xFF7C3AED)];
  static const List<Color> gradientSuccess = [Color(0xFF10B981), Color(0xFF059669)];
  static const List<Color> gradientChart = [Color(0xFF0EA5E9), Color(0xFF2563EB)];
}
