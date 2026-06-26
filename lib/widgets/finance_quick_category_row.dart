import 'package:flutter/material.dart';

import '../constants/finance_category_visuals.dart';
import '../theme/app_colors.dart';

/// Linha de ícones rápidos (estilo Compromissos): um toque preenche categoria + descrição sugerida.
class FinanceQuickCategoryRow extends StatelessWidget {
  final bool isIncome;
  final String currentCategory;
  final ValueChanged<FinanceQuickCategoryPreset> onPick;
  final bool enabled;

  const FinanceQuickCategoryRow({
    super.key,
    required this.isIncome,
    required this.currentCategory,
    required this.onPick,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final presets = isIncome ? kFinanceIncomeQuickPresets : kFinanceExpenseQuickPresets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Atalhos',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in presets)
              _QuickChip(
                preset: p,
                selected: currentCategory.trim().toLowerCase() == p.categoryName.toLowerCase(),
                onTap: enabled ? () => onPick(p) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  final FinanceQuickCategoryPreset preset;
  final bool selected;
  final VoidCallback? onTap;

  const _QuickChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  String get _shortLabel {
    final n = preset.categoryName;
    if (n.length <= 11) return n;
    return '${n.substring(0, 10)}…';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? preset.color.withValues(alpha: 0.18)
                : preset.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? preset.color.withValues(alpha: 0.85) : preset.color.withValues(alpha: 0.25),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: preset.color,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: preset.color.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(preset.icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                _shortLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
