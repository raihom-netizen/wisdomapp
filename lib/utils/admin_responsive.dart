import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Layout do painel Admin: web no celular usa drawer (não menu lateral fixo estreito).
class AdminResponsive {
  AdminResponsive._();

  static const double _mobileBreakpointNative = 720;
  static const double _mobileBreakpointWeb = 960;

  static bool useMobileLayout(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    if (kIsWeb) {
      return size.width < _mobileBreakpointWeb || shortest < 600;
    }
    return size.width < _mobileBreakpointNative;
  }

  static bool isNarrowContent(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 380;

  static double horizontalPadding(BuildContext context) =>
      isNarrowContent(context) ? 12.0 : 16.0;

  /// Raio padrão de cards no painel admin.
  static const double cardRadius = 16;

  /// Altura mínima de alvos de toque (iOS HIG / Material).
  static const double minTouchTarget = 48;

  /// Padding inferior seguro para listas (gestos / home indicator).
  static double bottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;
}
