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
  // WISDOMAPP: «Caixa pessoal» (dinheiro em mãos) — contas já cadastradas
  // usam este id; mantido no port do Controle Total (02/10/2026).
  FinanceBankPreset(
    id: 'caixa_pessoal',
    name: 'Caixa pessoal',
    initials: 'CP',
    color1: Color(0xFF059669),
    color2: Color(0xFF047857),
    icon: Icons.savings_rounded,
  ),
  // ── Bancos e fintechs que faltavam ────────────────────────────────────────
  FinanceBankPreset(id: 'banrisul', name: 'Banrisul', initials: 'BS', color1: Color(0xFF0072BC), color2: Color(0xFF004A80), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'safra', name: 'Safra', initials: 'SF', color1: Color(0xFF00447C), color2: Color(0xFF002A4D), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'banese', name: 'Banese', initials: 'BE', color1: Color(0xFF00833E), color2: Color(0xFF005C2B), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'bnb', name: 'Banco do Nordeste', initials: 'NB', color1: Color(0xFFD32F2F), color2: Color(0xFF9A0007), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'brb', name: 'BRB', initials: 'BB', color1: Color(0xFF0B5FA5), color2: Color(0xFF073E6D), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'daycoval', name: 'Daycoval', initials: 'DA', color1: Color(0xFF1B3A6B), color2: Color(0xFF0E2447), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'pan', name: 'Banco PAN', initials: 'PA', color1: Color(0xFF00A0DF), color2: Color(0xFF0073A8), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'agibank', name: 'Agibank', initials: 'AG', color1: Color(0xFF00B189), color2: Color(0xFF00785C), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'nuinvest', name: 'Banco Master', initials: 'MA', color1: Color(0xFF111827), color2: Color(0xFF374151), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'mercantil', name: 'Mercantil', initials: 'ME', color1: Color(0xFF0A6E4C), color2: Color(0xFF074F37), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'unicred', name: 'Unicred', initials: 'UC', color1: Color(0xFF00963F), color2: Color(0xFF006B2D), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'ailos', name: 'Ailos', initials: 'AI', color1: Color(0xFF00A6A0), color2: Color(0xFF007470), icon: Icons.account_balance_rounded),

  // ── Cartões de varejo e bandeira própria ──────────────────────────────────
  //
  // O cartão da loja quase nunca é do mesmo banco da conta corrente, e é ele
  // que junta as compras do mês do supermercado. Sem estar na lista, o usuário
  // cadastrava como «Outro cartão» e perdia a cor e a marca na hora de
  // reconhecer o lançamento.
  FinanceBankPreset(id: 'carrefour', name: 'Cartão Carrefour', initials: 'CF', color1: Color(0xFF004E9E), color2: Color(0xFFE30613), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'paodeacucar', name: 'Cartão Pão de Açúcar', initials: 'PA', color1: Color(0xFF00A650), color2: Color(0xFF007A3B), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'extra', name: 'Cartão Extra', initials: 'EX', color1: Color(0xFFE2001A), color2: Color(0xFFA80013), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'assai', name: 'Cartão Assaí', initials: 'AS', color1: Color(0xFFE30613), color2: Color(0xFF9E0410), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'atacadao', name: 'Cartão Atacadão', initials: 'AT', color1: Color(0xFF004E9E), color2: Color(0xFF00336B), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'magalu', name: 'Cartão Magalu', initials: 'MG', color1: Color(0xFF0086FF), color2: Color(0xFF0060B8), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'casasbahia', name: 'Cartão Casas Bahia', initials: 'CB', color1: Color(0xFF0033A0), color2: Color(0xFF00246E), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'riachuelo', name: 'Cartão Riachuelo', initials: 'RC', color1: Color(0xFF00A1E0), color2: Color(0xFF0072A0), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'renner', name: 'Cartão Renner', initials: 'RN', color1: Color(0xFF00843D), color2: Color(0xFF005C2A), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'marisa', name: 'Cartão Marisa', initials: 'MR', color1: Color(0xFFE6007E), color2: Color(0xFFA60059), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'pernambucanas', name: 'Cartão Pernambucanas', initials: 'PE', color1: Color(0xFF003C7D), color2: Color(0xFF002A57), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'havan', name: 'Cartão Havan', initials: 'HV', color1: Color(0xFF0057A6), color2: Color(0xFF003C75), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'americanas', name: 'Cartão Americanas', initials: 'AM', color1: Color(0xFFE60014), color2: Color(0xFFA3000E), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'ponto', name: 'Cartão Ponto', initials: 'PT', color1: Color(0xFFE2001A), color2: Color(0xFF9E0012), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'shopee', name: 'Cartão Shopee', initials: 'SH', color1: Color(0xFFEE4D2D), color2: Color(0xFFB8371D), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'amazon', name: 'Cartão Amazon', initials: 'AZ', color1: Color(0xFF232F3E), color2: Color(0xFFFF9900), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'samsclub', name: 'Cartão Sam\'s Club', initials: 'SM', color1: Color(0xFF0066B2), color2: Color(0xFF004884), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'ipiranga', name: 'Cartão Ipiranga', initials: 'IP', color1: Color(0xFFFFC72C), color2: Color(0xFF00529B), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'petrobras', name: 'Cartão Petrobras', initials: 'PB', color1: Color(0xFF008542), color2: Color(0xFFFFD100), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'shell', name: 'Cartão Shell Box', initials: 'SB', color1: Color(0xFFFBCE07), color2: Color(0xFFDD1D21), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'ale', name: 'Cartão Alelo', initials: 'AL', color1: Color(0xFF00A94F), color2: Color(0xFF007A39), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'sodexo', name: 'Cartão Sodexo / Pluxee', initials: 'SX', color1: Color(0xFF0C1B8C), color2: Color(0xFF071260), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'vr', name: 'Cartão VR', initials: 'VR', color1: Color(0xFF00A94F), color2: Color(0xFF00773A), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'ticket', name: 'Cartão Ticket', initials: 'TK', color1: Color(0xFFE2001A), color2: Color(0xFF9C0012), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'caju', name: 'Cartão Caju', initials: 'CJ', color1: Color(0xFFFF5000), color2: Color(0xFFC43D00), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'flash', name: 'Cartão Flash', initials: 'FL', color1: Color(0xFF1B1B1B), color2: Color(0xFF00E58A), icon: Icons.credit_card_rounded),

  FinanceBankPreset(id: 'outro_banco', name: 'Outro banco', initials: 'BK', color1: Color(0xFF475569), color2: Color(0xFF334155), icon: Icons.account_balance_rounded),
  FinanceBankPreset(id: 'outro_cartao', name: 'Outro cartão', initials: 'CR', color1: Color(0xFF64748B), color2: Color(0xFF475569), icon: Icons.credit_card_rounded),
  FinanceBankPreset(id: 'cofre_pessoal', name: 'Cofre pessoal', initials: 'CF', color1: Color(0xFF051937), color2: Color(0xFF1E3A5F), icon: Icons.lock_rounded),
];

/// Prefixo do banco/cartão que o próprio usuário cadastrou.
///
/// Formato: `custom:<b|c>:<Nome>` — `b` banco, `c` cartão.
///
/// Fica dentro do `presetId` de propósito, sem coleção nova: todo lugar que já
/// lê o preset pelo id (lista, extrato, PDF, notificação do banco) passa a
/// funcionar com o cartão personalizado sem precisar saber que ele existe.
const String kFinancePresetCustomPrefix = 'custom:';

/// Paleta dos personalizados — escolhida pelo nome, então o mesmo cartão tem
/// sempre a mesma cor, sem precisar guardar isso em lugar nenhum.
const List<List<Color>> _kCoresCustom = [
  [Color(0xFF0E7490), Color(0xFF155E75)],
  [Color(0xFF7C3AED), Color(0xFF5B21B6)],
  [Color(0xFFDC2626), Color(0xFF991B1B)],
  [Color(0xFF059669), Color(0xFF065F46)],
  [Color(0xFFD97706), Color(0xFF92400E)],
  [Color(0xFF2563EB), Color(0xFF1E40AF)],
  [Color(0xFFDB2777), Color(0xFF9D174D)],
  [Color(0xFF475569), Color(0xFF1E293B)],
];

/// Monta o id de um banco/cartão personalizado.
String financePresetCustomId(String nome, {required bool cartao}) {
  final limpo = nome.trim().replaceAll(':', ' ').replaceAll(RegExp(r'\s+'), ' ');
  return '$kFinancePresetCustomPrefix${cartao ? 'c' : 'b'}:$limpo';
}

/// Sigla de duas letras a partir do nome («Cartão do Posto» → «CP»).
String _siglaDoNome(String nome) {
  final partes = nome
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && p.length > 2)
      .toList();
  if (partes.isEmpty) {
    final s = nome.trim();
    return (s.isEmpty ? '??' : s.padRight(2).substring(0, 2)).toUpperCase();
  }
  if (partes.length == 1) {
    return partes.first.padRight(2).substring(0, 2).toUpperCase();
  }
  return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
}

/// Reconstrói o preset de um id `custom:`. `null` se não for um.
FinanceBankPreset? financeBankPresetCustom(String id) {
  if (!id.startsWith(kFinancePresetCustomPrefix)) return null;
  final resto = id.substring(kFinancePresetCustomPrefix.length);
  final sep = resto.indexOf(':');
  if (sep < 1) return null;
  final tipo = resto.substring(0, sep);
  final nome = resto.substring(sep + 1).trim();
  if (nome.isEmpty) return null;
  final cartao = tipo == 'c';
  // Cor estável pelo nome: o mesmo cartão nunca troca de cor entre telas.
  final cores = _kCoresCustom[nome.hashCode.abs() % _kCoresCustom.length];
  return FinanceBankPreset(
    id: id,
    name: nome,
    initials: _siglaDoNome(nome),
    color1: cores[0],
    color2: cores[1],
    icon: cartao ? Icons.credit_card_rounded : Icons.account_balance_rounded,
  );
}

FinanceBankPreset? financeBankPresetById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final p in kFinanceBankPresets) {
    if (p.id == id) return p;
  }
  // Banco/cartão que o usuário cadastrou na mão.
  return financeBankPresetCustom(id);
}

/// Cor do nome da conta em listas claras (ex.: «Saldo por contas» no painel).
const Color _kFinanceAccountTitleDefault = Color(0xFF1A237E);

Color financeAccountListTitleColor(FinanceBankPreset? p) {
  if (p == null) return _kFinanceAccountTitleDefault;
  if (p.id == 'bradesco') return const Color(0xFFCC092F);
  return _kFinanceAccountTitleDefault;
}
