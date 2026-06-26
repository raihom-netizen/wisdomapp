import 'package:flutter/material.dart';

/// Instituições usuais no ecossistema Open Finance (Brasil) — vitrine para o usuário conferir antes de assinar.
/// A conexão real depende do agregador (Pluggy) e da disponibilidade do conector no momento.
class SupportedBankCategory {
  const SupportedBankCategory({
    required this.title,
    required this.icon,
    required this.institutions,
  });

  final String title;
  final IconData icon;
  final List<String> institutions;
}

/// Lista organizada por categorias (copy comercial + FAQ).
const List<SupportedBankCategory> kSupportedOpenFinanceCategories = [
  SupportedBankCategory(
    title: 'Principais bancos (tradicionais)',
    icon: Icons.account_balance_rounded,
    institutions: [
      'Itaú / Itaú Unibanco',
      'Bradesco',
      'Banco do Brasil',
      'Santander',
      'Caixa Econômica Federal (incluindo Caixa Tem)',
    ],
  ),
  SupportedBankCategory(
    title: 'Bancos digitais e fintechs',
    icon: Icons.rocket_launch_outlined,
    institutions: [
      'Nubank',
      'Banco Inter',
      'C6 Bank',
      'Banco Neon',
      'BTG Pactual (banking e investimentos)',
      'Banco Original',
      'Banco Next',
      'Digio',
    ],
  ),
  SupportedBankCategory(
    title: 'Cartões, benefícios e pagamentos',
    icon: Icons.credit_card_rounded,
    institutions: [
      'Mercado Pago',
      'PicPay',
      'PagBank (PagSeguro)',
      'Stone',
      'RecargaPay',
      'Alelo (cartões de benefício)',
      'Ticket / Sodexo (via agregador certificado)',
    ],
  ),
  SupportedBankCategory(
    title: 'Cooperativas e regionais',
    icon: Icons.groups_2_outlined,
    institutions: [
      'Sicredi',
      'Sicoob',
      'Banrisul',
      'Unicred',
    ],
  ),
];

String _normalizeForSearch(String s) {
  var t = s.toLowerCase().trim();
  const pairs = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  pairs.forEach((k, v) => t = t.replaceAll(k, v));
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

/// Filtra categorias mantendo só instituições que casam com [query] (nome contém).
List<SupportedBankCategory> filterSupportedBankCategories(String query) {
  final q = _normalizeForSearch(query);
  if (q.isEmpty) return List<SupportedBankCategory>.from(kSupportedOpenFinanceCategories);

  final out = <SupportedBankCategory>[];
  for (final c in kSupportedOpenFinanceCategories) {
    final titleHit = _normalizeForSearch(c.title).contains(q);
    final names = c.institutions.where((n) => _normalizeForSearch(n).contains(q)).toList();
    if (titleHit && names.isEmpty) {
      out.add(SupportedBankCategory(title: c.title, icon: c.icon, institutions: List<String>.from(c.institutions)));
    } else if (names.isNotEmpty) {
      out.add(SupportedBankCategory(title: c.title, icon: c.icon, institutions: names));
    }
  }
  return out;
}

int countSupportedInstitutions() {
  var n = 0;
  for (final c in kSupportedOpenFinanceCategories) {
    n += c.institutions.length;
  }
  return n;
}
