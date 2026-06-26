import 'package:flutter/material.dart';

/// Atalho visual (ícone rápido antes do valor): preenche categoria + descrição sugerida.
@immutable
class FinanceQuickCategoryPreset {
  final String categoryName;
  final String suggestedDescription;
  final IconData icon;
  final Color color;

  const FinanceQuickCategoryPreset({
    required this.categoryName,
    required this.suggestedDescription,
    required this.icon,
    required this.color,
  });
}

/// Seis atalhos mais usados — nomes coincidem com [kDefaultExpenseCategories].
const List<FinanceQuickCategoryPreset> kFinanceExpenseQuickPresets = [
  FinanceQuickCategoryPreset(
    categoryName: 'Supermercado',
    suggestedDescription: 'Compras no mercado',
    icon: Icons.shopping_cart_rounded,
    color: Color(0xFF43A047),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Combustível',
    suggestedDescription: 'Abastecimento',
    icon: Icons.local_gas_station_rounded,
    color: Color(0xFFFB8C00),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Alimentação',
    suggestedDescription: 'Alimentação',
    icon: Icons.restaurant_rounded,
    color: Color(0xFFE53935),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Transporte',
    suggestedDescription: 'Transporte',
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF1E88E5),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Academia',
    suggestedDescription: 'Mensalidade / academia',
    icon: Icons.fitness_center_rounded,
    color: Color(0xFF6D4C41),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Cartão',
    suggestedDescription: 'Fatura / cartão',
    icon: Icons.credit_card_rounded,
    color: Color(0xFF3949AB),
  ),
];

/// Seis atalhos — nomes coincidem com [kDefaultIncomeCategories].
const List<FinanceQuickCategoryPreset> kFinanceIncomeQuickPresets = [
  FinanceQuickCategoryPreset(
    categoryName: 'Salários',
    suggestedDescription: 'Salário',
    icon: Icons.account_balance_wallet_rounded,
    color: Color(0xFF2E7D32),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Freelance',
    suggestedDescription: 'Serviço freelance',
    icon: Icons.work_outline_rounded,
    color: Color(0xFF1565C0),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Investimentos',
    suggestedDescription: 'Rendimento / investimento',
    icon: Icons.trending_up_rounded,
    color: Color(0xFF00897B),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Aluguel recebido',
    suggestedDescription: 'Aluguel recebido',
    icon: Icons.home_work_rounded,
    color: Color(0xFF6A1B9A),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Comissão',
    suggestedDescription: 'Comissão',
    icon: Icons.percent_rounded,
    color: Color(0xFFEF6C00),
  ),
  FinanceQuickCategoryPreset(
    categoryName: 'Bônus',
    suggestedDescription: 'Bônus / gratificação',
    icon: Icons.emoji_events_rounded,
    color: Color(0xFFF9A825),
  ),
];

/// Ícone + cor para lista premium (e fallback consistente).
@immutable
class FinanceCategoryVisual {
  final IconData icon;
  final Color color;

  const FinanceCategoryVisual({required this.icon, required this.color});
}

final Map<String, FinanceCategoryVisual> _kExpenseVisualByLower = {
  'energia': const FinanceCategoryVisual(icon: Icons.bolt_rounded, color: Color(0xFFFFC107)),
  'água': const FinanceCategoryVisual(icon: Icons.water_drop_rounded, color: Color(0xFF29B6F6)),
  'gás': const FinanceCategoryVisual(icon: Icons.local_fire_department_rounded, color: Color(0xFFFF7043)),
  'combustível': const FinanceCategoryVisual(icon: Icons.local_gas_station_rounded, color: Color(0xFFFB8C00)),
  'alimentação': const FinanceCategoryVisual(icon: Icons.restaurant_rounded, color: Color(0xFFE53935)),
  'farmácia': const FinanceCategoryVisual(icon: Icons.local_pharmacy_rounded, color: Color(0xFF43A047)),
  'internet': const FinanceCategoryVisual(icon: Icons.wifi_rounded, color: Color(0xFF5C6BC0)),
  'escola': const FinanceCategoryVisual(icon: Icons.school_rounded, color: Color(0xFF3949AB)),
  'academia': const FinanceCategoryVisual(icon: Icons.fitness_center_rounded, color: Color(0xFF6D4C41)),
  'dízimos': const FinanceCategoryVisual(icon: Icons.volunteer_activism_rounded, color: Color(0xFF7E57C2)),
  'ofertas': const FinanceCategoryVisual(icon: Icons.card_giftcard_rounded, color: Color(0xFFEC407A)),
  'doações': const FinanceCategoryVisual(icon: Icons.favorite_rounded, color: Color(0xFFE91E63)),
  'contribuições': const FinanceCategoryVisual(icon: Icons.groups_rounded, color: Color(0xFF5E35B1)),
  'juros': const FinanceCategoryVisual(icon: Icons.balance_rounded, color: Color(0xFF607D8B)),
  'supermercado': const FinanceCategoryVisual(icon: Icons.shopping_cart_rounded, color: Color(0xFF43A047)),
  'cartão': const FinanceCategoryVisual(icon: Icons.credit_card_rounded, color: Color(0xFF3949AB)),
  'empréstimo': const FinanceCategoryVisual(icon: Icons.account_balance_rounded, color: Color(0xFF455A64)),
  'consórcio': const FinanceCategoryVisual(icon: Icons.handshake_rounded, color: Color(0xFF546E7A)),
  'transporte': const FinanceCategoryVisual(icon: Icons.directions_bus_rounded, color: Color(0xFF1E88E5)),
  'lazer': const FinanceCategoryVisual(icon: Icons.theater_comedy_rounded, color: Color(0xFFAB47BC)),
  'seguros': const FinanceCategoryVisual(icon: Icons.security_rounded, color: Color(0xFF00897B)),
  'telefone': const FinanceCategoryVisual(icon: Icons.smartphone_rounded, color: Color(0xFF78909C)),
  'tv / streaming': const FinanceCategoryVisual(icon: Icons.live_tv_rounded, color: Color(0xFFE53935)),
  'cursos': const FinanceCategoryVisual(icon: Icons.menu_book_rounded, color: Color(0xFF5C6BC0)),
  'vestuário': const FinanceCategoryVisual(icon: Icons.checkroom_rounded, color: Color(0xFF8E24AA)),
  'manutenção': const FinanceCategoryVisual(icon: Icons.build_rounded, color: Color(0xFF757575)),
  'pet': const FinanceCategoryVisual(icon: Icons.pets_rounded, color: Color(0xFFFF9800)),
  'plano de saúde': const FinanceCategoryVisual(icon: Icons.health_and_safety_rounded, color: Color(0xFF26A69A)),
  'iptu / condomínio': const FinanceCategoryVisual(icon: Icons.apartment_rounded, color: Color(0xFF6D4C41)),
};

final Map<String, FinanceCategoryVisual> _kIncomeVisualByLower = {
  'salários': const FinanceCategoryVisual(icon: Icons.payments_rounded, color: Color(0xFF2E7D32)),
  'horas extras': const FinanceCategoryVisual(icon: Icons.more_time_rounded, color: Color(0xFF388E3C)),
  'bônus': const FinanceCategoryVisual(icon: Icons.emoji_events_rounded, color: Color(0xFFF9A825)),
  'investimentos': const FinanceCategoryVisual(icon: Icons.show_chart_rounded, color: Color(0xFF00897B)),
  'freelance': const FinanceCategoryVisual(icon: Icons.work_outline_rounded, color: Color(0xFF1565C0)),
  'aluguel recebido': const FinanceCategoryVisual(icon: Icons.home_work_rounded, color: Color(0xFF6A1B9A)),
  'venda': const FinanceCategoryVisual(icon: Icons.point_of_sale_rounded, color: Color(0xFFEF6C00)),
  'rendimentos': const FinanceCategoryVisual(icon: Icons.savings_rounded, color: Color(0xFF00838F)),
  'comissão': const FinanceCategoryVisual(icon: Icons.percent_rounded, color: Color(0xFFFB8C00)),
};

FinanceCategoryVisual financeCategoryVisualFor(String name, {required bool isIncome}) {
  final k = name.trim().toLowerCase();
  final fromMap = isIncome ? _kIncomeVisualByLower[k] : _kExpenseVisualByLower[k];
  if (fromMap != null) return fromMap;
  // Fallback estável por hash do nome (custom categories).
  var h = 0;
  for (final c in k.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  const palette = <Color>[
    Color(0xFF3949AB),
    Color(0xFF00897B),
    Color(0xFF6D4C41),
    Color(0xFFC62828),
    Color(0xFF6A1B9A),
    Color(0xFF1565C0),
  ];
  const icons = <IconData>[
    Icons.category_rounded,
    Icons.label_rounded,
    Icons.bookmark_rounded,
    Icons.folder_rounded,
    Icons.brightness_1_rounded,
    Icons.star_rounded,
  ];
  return FinanceCategoryVisual(icon: icons[h % icons.length], color: palette[h % palette.length]);
}

/// Quadrado com gradiente (listas: despesas/receitas fixas, etc.). Opção «Incluir nova» = ícone +.
Widget financeCategoryLeadingTile(
  String name, {
  required bool isIncome,
  bool isIncluirNovaOption = false,
  double size = 48,
}) {
  if (isIncluirNovaOption) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF3949AB), Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3949AB).withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(Icons.add_rounded, color: Colors.white, size: size * 0.48),
    );
  }
  final vis = financeCategoryVisualFor(name, isIncome: isIncome);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(
        colors: [vis.color, Color.lerp(vis.color, Colors.black, 0.12)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: vis.color.withValues(alpha: 0.35),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Icon(vis.icon, color: Colors.white, size: size * 0.46),
  );
}

/// Linha para [DropdownMenuItem] (atalho visual + texto).
Widget financeCategoryDropdownMenuRow(
  String categoryName, {
  required bool isIncome,
  required bool isIncluirNovaOption,
}) {
  final mini = financeCategoryLeadingTile(
    categoryName,
    isIncome: isIncome,
    isIncluirNovaOption: isIncluirNovaOption,
    size: 36,
  );
  return Row(
    children: [
      mini,
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          categoryName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    ],
  );
}
