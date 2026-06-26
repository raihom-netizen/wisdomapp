import 'package:flutter/material.dart';

/// Volta à rota anterior se existir; senão vai ao painel (`/`).
/// Evita utilizador preso após login com [pushNamedAndRemoveUntil] só para plano/checkout.
void popOrGoHome(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  nav.pushNamedAndRemoveUntil('/', (route) => false);
}
