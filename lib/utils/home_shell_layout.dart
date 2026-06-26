import 'package:flutter/material.dart';

/// Módulo aberto dentro do [HomeShell] (rodapé fixo: ícones + versículo).
bool isHomeShellEmbeddedModule({
  ScrollController? shellScrollController,
  Object? onNavigateTo,
}) =>
    shellScrollController != null || onNavigateTo != null;

/// [SafeArea] inferior: no shell o rodapé já reserva o inset do dispositivo.
bool homeShellSafeAreaBottom({required bool embeddedInHomeShell}) =>
    !embeddedInHomeShell;

/// Padding inferior de scroll/lista — **não** somar [MediaQuery.padding.bottom] no shell.
double homeShellScrollBottomPadding(
  BuildContext context, {
  required bool embeddedInHomeShell,
  double tail = 8,
}) {
  if (embeddedInHomeShell) return tail;
  return tail + MediaQuery.paddingOf(context).bottom;
}

/// Espaço para FAB acima do rodapé do shell (sem safe area duplicada).
double homeShellFabScrollTail(
  BuildContext context, {
  required bool embeddedInHomeShell,
  double fabClearance = 72,
}) {
  if (embeddedInHomeShell) return fabClearance;
  return fabClearance + MediaQuery.paddingOf(context).bottom;
}
