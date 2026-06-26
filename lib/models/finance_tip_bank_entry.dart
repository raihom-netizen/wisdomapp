import 'package:flutter/material.dart';

/// Entrada do banco de dicas financeiras (fixas / educação).
///
/// [iconKey] e [colorKey] são strings para persistir no Firestore e reconstruir na UI.
class FinanceTipBankEntry {
  const FinanceTipBankEntry({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.categoriaSlug,
    required this.iconKey,
    required this.colorKey,
  });

  final String id;
  final String titulo;
  final String descricao;

  /// Slug estável: `educacao`, `comportamento`, `alimentacao`, `cartao`, etc.
  final String categoriaSlug;
  final String iconKey;
  final String colorKey;

  IconData get icon => kFinanceTipIconByKey[iconKey] ?? Icons.menu_book_rounded;

  Color get color => kFinanceTipColorByKey[colorKey] ?? const Color(0xFF2D5BFF);

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'descricao': descricao,
        'categoria': categoriaSlug,
        'iconKey': iconKey,
        'colorKey': colorKey,
      };

  factory FinanceTipBankEntry.fromJson(Map<String, dynamic> m) {
    return FinanceTipBankEntry(
      id: (m['id'] ?? '').toString(),
      titulo: (m['titulo'] ?? '').toString(),
      descricao: (m['descricao'] ?? '').toString(),
      categoriaSlug: (m['categoria'] ?? m['categoriaSlug'] ?? '').toString(),
      iconKey: (m['iconKey'] ?? 'menu_book').toString(),
      colorKey: (m['colorKey'] ?? 'blue').toString(),
    );
  }
}

/// Ícones referenciados pelo banco estático e por documentos Firestore.
const Map<String, IconData> kFinanceTipIconByKey = {
  'account_balance': Icons.account_balance_rounded,
  'timer': Icons.timer_outlined,
  'savings': Icons.savings_outlined,
  'fastfood': Icons.fastfood_rounded,
  'money_off': Icons.money_off_csred_rounded,
  'directions_car': Icons.directions_car_rounded,
  'credit_card': Icons.credit_card_rounded,
  'warning': Icons.warning_amber_rounded,
  'trending_up': Icons.trending_up_rounded,
  'shield': Icons.shield_moon_outlined,
  'bar_chart': Icons.bar_chart_rounded,
  'search': Icons.manage_search_rounded,
  'menu_book': Icons.menu_book_rounded,
  'lightbulb': Icons.lightbulb_outline_rounded,
  'percent': Icons.percent_rounded,
  'subscriptions': Icons.subscriptions_rounded,
};

/// Cores nomeadas (Material + brand) para JSON/Firestore.
const Map<String, Color> kFinanceTipColorByKey = {
  'blue': Color(0xFF2563EB),
  'orange': Color(0xFFEA580C),
  'green': Color(0xFF16A34A),
  'red': Color(0xFFDC2626),
  'deepOrange': Color(0xFFEA580C),
  'blueGrey': Color(0xFF546E7A),
  'purple': Color(0xFF7C3AED),
  'teal': Color(0xFF0D9488),
  'indigo': Color(0xFF4F46E5),
  'primary': Color(0xFF2D5BFF),
};
