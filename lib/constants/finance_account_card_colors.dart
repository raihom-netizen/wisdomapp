import 'package:flutter/material.dart';

/// Tema de cor do mini-card no módulo Financeiro (independente da marca do banco).
class FinanceAccountCardColor {
  const FinanceAccountCardColor({
    required this.id,
    required this.label,
    this.color1,
    this.color2,
    this.icon = Icons.palette_rounded,
  });

  final String id;
  final String label;
  final Color? color1;
  final Color? color2;
  final IconData icon;

  bool get isAuto => id == kFinanceAccountCardColorAuto;

  List<Color> get gradient {
    if (color1 == null || color2 == null) return const [Color(0xFF64748B), Color(0xFF475569)];
    return [color1!, color2!];
  }
}

/// Usar cor derivada do banco / tipo de produto (comportamento anterior).
const String kFinanceAccountCardColorAuto = 'auto';

/// Paleta moderna — o usuário escolhe ao cadastrar ou editar conta/cartão.
const List<FinanceAccountCardColor> kFinanceAccountCardColors = [
  FinanceAccountCardColor(
    id: kFinanceAccountCardColorAuto,
    label: 'Automática',
    icon: Icons.auto_awesome_rounded,
  ),
  FinanceAccountCardColor(
    id: 'ocean',
    label: 'Oceano',
    color1: Color(0xFF0EA5E9),
    color2: Color(0xFF0369A1),
    icon: Icons.water_rounded,
  ),
  FinanceAccountCardColor(
    id: 'emerald',
    label: 'Esmeralda',
    color1: Color(0xFF10B981),
    color2: Color(0xFF047857),
    icon: Icons.eco_rounded,
  ),
  FinanceAccountCardColor(
    id: 'violet',
    label: 'Violeta',
    color1: Color(0xFF8B5CF6),
    color2: Color(0xFF5B21B6),
    icon: Icons.bubble_chart_rounded,
  ),
  FinanceAccountCardColor(
    id: 'sunset',
    label: 'Pôr do sol',
    color1: Color(0xFFF97316),
    color2: Color(0xFFEA580C),
    icon: Icons.wb_twilight_rounded,
  ),
  FinanceAccountCardColor(
    id: 'rose',
    label: 'Rosa',
    color1: Color(0xFFEC4899),
    color2: Color(0xFFBE185D),
    icon: Icons.favorite_rounded,
  ),
  FinanceAccountCardColor(
    id: 'midnight',
    label: 'Meia-noite',
    color1: Color(0xFF1E293B),
    color2: Color(0xFF0F172A),
    icon: Icons.nightlight_round,
  ),
  FinanceAccountCardColor(
    id: 'teal',
    label: 'Teal',
    color1: Color(0xFF14B8A6),
    color2: Color(0xFF0F766E),
    icon: Icons.waves_rounded,
  ),
  FinanceAccountCardColor(
    id: 'indigo',
    label: 'Índigo',
    color1: Color(0xFF6366F1),
    color2: Color(0xFF4338CA),
    icon: Icons.diamond_rounded,
  ),
  FinanceAccountCardColor(
    id: 'amber',
    label: 'Âmbar',
    color1: Color(0xFFFBBF24),
    color2: Color(0xFFD97706),
    icon: Icons.light_mode_rounded,
  ),
  FinanceAccountCardColor(
    id: 'ruby',
    label: 'Rubí',
    color1: Color(0xFFEF4444),
    color2: Color(0xFFB91C1C),
    icon: Icons.local_fire_department_rounded,
  ),
  FinanceAccountCardColor(
    id: 'slate',
    label: 'Grafite',
    color1: Color(0xFF64748B),
    color2: Color(0xFF334155),
    icon: Icons.texture_rounded,
  ),
];

FinanceAccountCardColor? financeAccountCardColorById(String? id) {
  if (id == null || id.isEmpty || id == kFinanceAccountCardColorAuto) return null;
  for (final c in kFinanceAccountCardColors) {
    if (c.id == id) return c;
  }
  return null;
}

FinanceAccountCardColor financeAccountCardColorOrAuto(String? id) {
  for (final c in kFinanceAccountCardColors) {
    if (c.id == id) return c;
  }
  return kFinanceAccountCardColors.first;
}

/// Cor do card para persistência (null = automática).
String? financeAccountCardColorIdForSave(String selectedId) {
  if (selectedId.isEmpty || selectedId == kFinanceAccountCardColorAuto) return null;
  return selectedId;
}

String financeAccountCardColorIdForUi(String? stored) {
  if (stored == null || stored.isEmpty) return kFinanceAccountCardColorAuto;
  return financeAccountCardColorById(stored) != null ? stored : kFinanceAccountCardColorAuto;
}
