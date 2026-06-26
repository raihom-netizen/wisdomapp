import 'package:flutter/material.dart';

import 'escolha_plano_page.dart';

/// Rota legada e links antigos: o único plano comercial à venda é o **Premium** (mensal/anual).
class PremiumProPaywallScreen extends StatelessWidget {
  const PremiumProPaywallScreen({super.key});

  @override
  Widget build(BuildContext context) => const EscolhaPlanoPage();
}
