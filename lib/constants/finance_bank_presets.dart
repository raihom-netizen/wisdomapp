import 'package:flutter/material.dart';

/// Instituições brasileiras comuns — cores + sigla; miniatura embutida em assets (ver `finance_bank_brand_thumb.dart`).
class FinanceBankPreset {
  final String id;
  final String name;
  final String initials;
  final Color color1;
  final Color color2;
  final IconData icon;

  const FinanceBankPreset({
    required this.id,
    required this.name,
    required this.initials,
    required this.color1,
    required this.color2,
    required this.icon,
  });
}

/// Lista fixa para o usuário escolher ao cadastrar conta/cartão.
const List<FinanceBankPreset> kFinanceBankPresets = [
  FinanceBankPreset(id: 'bradesco', name: 'Bradesco', initials: 'BR', color1: Color(0xFF5C1848), color2: Color(0xFFE3061A), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'itau', name: 'Itaú', initials: 'IT', color1: Color(0xFFFF8C00), color2: Color(0xFFEC7000), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'caixa', name: 'Caixa Econômica', initials: 'CX', color1: Color(0xFF003366), color2: Color(0xFF0066B3), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'nubank', name: 'Nubank', initials: 'NU', color1: Color(0xFF820AD1), color2: Color(0xFF4A0072), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'c6', name: 'C6 Bank', initials: 'C6', color1: Color(0xFF1A1A1A), color2: Color(0xFF505050), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'santander', name: 'Santander', initials: 'ST', color1: Color(0xFFEC0000), color2: Color(0xFFAA0000), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'bb', name: 'Banco do Brasil', initials: 'BB', color1: Color(0xFFFFCC00), color2: Color(0xFFF5A623), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'mercadopago', name: 'Mercado Pago', initials: 'MP', color1: Color(0xFF009EE3), color2: Color(0xFF0568D4), icon: Icons.payment_rounded),
  FinanceBankPreset(id: 'inter', name: 'Inter', initials: 'IN', color1: Color(0xFFFF7A00), color2: Color(0xFFE65100), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'sicoob', name: 'Sicoob', initials: 'SC', color1: Color(0xFF006633), color2: Color(0xFF004D26), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'sicredi', name: 'Sicredi', initials: 'SI', color1: Color(0xFF00A859), color2: Color(0xFF007A42), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'original', name: 'Banco Original', initials: 'OR', color1: Color(0xFFFFC107), color2: Color(0xFFFF9800), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'btg', name: 'BTG Pactual', initials: 'BT', color1: Color(0xFF001A57), color2: Color(0xFF003B7A), icon: Icons.trending_up_rounded),
  FinanceBankPreset(id: 'xp', name: 'XP Investimentos', initials: 'XP', color1: Color(0xFF111111), color2: Color(0xFF444444), icon: Icons.show_chart_rounded),
  FinanceBankPreset(id: 'picpay', name: 'PicPay', initials: 'PP', color1: Color(0xFF21C25E), color2: Color(0xFF119E4A), icon: Icons.smartphone_rounded),
  FinanceBankPreset(id: 'stone', name: 'Stone', initials: 'SO', color1: Color(0xFF00A868), color2: Color(0xFF007A4A), icon: Icons.point_of_sale_rounded),
  FinanceBankPreset(id: 'cielo', name: 'Cielo', initials: 'CI', color1: Color(0xFF00AEEF), color2: Color(0xFF0077B6), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'pagbank', name: 'PagBank / PagSeguro', initials: 'PG', color1: Color(0xFFFFC107), color2: Color(0xFFFF9800), icon: Icons.account_balance_wallet_rounded),
  FinanceBankPreset(id: 'neon', name: 'Neon', initials: 'NE', color1: Color(0xFF00E5FF), color2: Color(0xFF00B4D8), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'will', name: 'Will Bank', initials: 'WL', color1: Color(0xFF7C4DFF), color2: Color(0xFF5E35B1), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'outro_banco', name: 'Outro banco', initials: 'BK', color1: Color(0xFF475569), color2: Color(0xFF334155), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'outro_cartao', name: 'Outro cartão', initials: 'CR', color1: Color(0xFF64748B), color2: Color(0xFF475569), icon: Icons.credit_card_rounded),
];

FinanceBankPreset? financeBankPresetById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final p in kFinanceBankPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// Cor do nome da conta em listas claras (ex.: «Saldo por contas» no painel).
const Color _kFinanceAccountTitleDefault = Color(0xFF1A237E);

Color financeAccountListTitleColor(FinanceBankPreset? p) {
  if (p == null) return _kFinanceAccountTitleDefault;
  if (p.id == 'bradesco') return const Color(0xFFCC092F);
  return _kFinanceAccountTitleDefault;
}
