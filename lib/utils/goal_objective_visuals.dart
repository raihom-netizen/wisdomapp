import 'package:flutter/material.dart';

import '../models/financial_goal.dart';

class GoalObjectiveVisual {
  const GoalObjectiveVisual({
    required this.icon,
    required this.color,
    required this.emoji,
    required this.gradient,
  });

  final IconData icon;
  final Color color;
  final String emoji;
  final List<Color> gradient;
}

class GoalObjectivePreset {
  const GoalObjectivePreset({
    required this.label,
    required this.categoryId,
    required this.visual,
  });

  final String label;
  final String categoryId;
  final GoalObjectiveVisual visual;
}

const List<GoalObjectivePreset> kGoalObjectivePresets = [
  GoalObjectivePreset(
    label: 'Viagem',
    categoryId: 'viagem',
    visual: GoalObjectiveVisual(
      icon: Icons.flight_rounded,
      color: Color(0xFF2563EB),
      emoji: '✈️',
      gradient: [Color(0xFF2563EB), Color(0xFF06B6D4)],
    ),
  ),
  GoalObjectivePreset(
    label: 'Comprar carro',
    categoryId: 'veiculo',
    visual: GoalObjectiveVisual(
      icon: Icons.directions_car_rounded,
      color: Color(0xFFDC2626),
      emoji: '🚗',
      gradient: [Color(0xFFDC2626), Color(0xFFF97316)],
    ),
  ),
  GoalObjectivePreset(
    label: 'Comprar casa',
    categoryId: 'casa',
    visual: GoalObjectiveVisual(
      icon: Icons.home_rounded,
      color: Color(0xFF0D9488),
      emoji: '🏠',
      gradient: [Color(0xFF0D9488), Color(0xFF14B8A6)],
    ),
  ),
  GoalObjectivePreset(
    label: 'Reforma',
    categoryId: 'casa',
    visual: GoalObjectiveVisual(
      icon: Icons.build_rounded,
      color: Color(0xFFB45309),
      emoji: '🔨',
      gradient: [Color(0xFFB45309), Color(0xFFF59E0B)],
    ),
  ),
  GoalObjectivePreset(
    label: 'Quitar dívidas',
    categoryId: 'personalizada',
    visual: GoalObjectiveVisual(
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF7C3AED),
      emoji: '📋',
      gradient: [Color(0xFF7C3AED), Color(0xFFA855F7)],
    ),
  ),
  GoalObjectivePreset(
    label: 'Reserva de emergência',
    categoryId: 'reserva_emergencia',
    visual: GoalObjectiveVisual(
      icon: Icons.shield_rounded,
      color: Color(0xFF059669),
      emoji: '🛡️',
      gradient: [Color(0xFF059669), Color(0xFF10B981)],
    ),
  ),
  GoalObjectivePreset(
    label: 'Investimento',
    categoryId: 'investimento',
    visual: GoalObjectiveVisual(
      icon: Icons.trending_up_rounded,
      color: Color(0xFF1D4ED8),
      emoji: '📈',
      gradient: [Color(0xFF1D4ED8), Color(0xFF6366F1)],
    ),
  ),
  GoalObjectivePreset(
    label: 'Personalizado',
    categoryId: 'personalizada',
    visual: GoalObjectiveVisual(
      icon: Icons.flag_rounded,
      color: Color(0xFF64748B),
      emoji: '🎯',
      gradient: [Color(0xFF6366F1), Color(0xFFEC4899)],
    ),
  ),
];

GoalObjectiveVisual goalVisualForData(Map<String, dynamic> data) {
  final emoji = (data['emoji'] ?? '').toString();
  final cat = GoalCategory.fromId(data['category'] as String?);
  for (final p in kGoalObjectivePresets) {
    if (p.categoryId == cat.id) return p.visual;
  }
  if (emoji.isNotEmpty) {
    return const GoalObjectiveVisual(
      icon: Icons.flag_rounded,
      color: Color(0xFF6366F1),
      emoji: '🎯',
      gradient: [Color(0xFF6366F1), Color(0xFFEC4899)],
    );
  }
  return const GoalObjectiveVisual(
    icon: Icons.flag_rounded,
    color: Color(0xFF6366F1),
    emoji: '🎯',
    gradient: [Color(0xFF6366F1), Color(0xFFEC4899)],
  );
}

GoalObjectivePreset? presetForCategory(String? categoryId) {
  if (categoryId == null) return null;
  for (final p in kGoalObjectivePresets) {
    if (p.categoryId == categoryId) return p;
  }
  return null;
}
