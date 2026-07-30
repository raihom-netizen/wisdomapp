import 'package:flutter/material.dart';

import '../services/goal_deposit_service.dart';
import 'brl_amount_text_field.dart';

/// Verde destacado para ações de depósito (paridade com sheet 52 semanas).
class GoalDepositUi {
  GoalDepositUi._();

  static const Color green = Color(0xFF16A34A);
  static const Color greenDark = Color(0xFF15803D);
  static const List<Color> gradient = [
    Color(0xFF22C55E),
    Color(0xFF16A34A),
  ];

  static BoxDecoration gradientDecoration({double radius = 14}) =>
      BoxDecoration(
        gradient: const LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: greenDark.withValues(alpha: 0.38),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      );

  static Widget depositPrimaryButton({
    required VoidCallback? onPressed,
    required String label,
    IconData icon = Icons.savings_rounded,
    bool expand = true,
  }) {
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final box = DecoratedBox(
      decoration: gradientDecoration(),
      child: Opacity(opacity: onPressed == null ? 0.45 : 1, child: child),
    );
    if (expand) return SizedBox(width: double.infinity, child: box);
    return box;
  }
}

/// Campo de valor estilo lançamento financeiro (grande, moderno).
class GoalDepositAmountField extends StatelessWidget {
  const GoalDepositAmountField({
    super.key,
    required this.controller,
    this.label = 'Valor do depósito',
    this.hint,
    this.accent = GoalDepositUi.green,
    this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final Color accent;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.1), Colors.white],
            ),
            border:
                Border.all(color: accent.withValues(alpha: 0.28), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: BrlAmountTextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              hintText: hint ?? 'R\$ 0,00',
              hintStyle: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade400,
              ),
              prefixText: 'R\$ ',
              prefixStyle: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}

/// Faixa de aviso ao excluir — desmarca semanas na Meta (Projeto 52 semanas).
class GoalDepositWeeksUnmarkBanner extends StatelessWidget {
  const GoalDepositWeeksUnmarkBanner({
    super.key,
    required this.info,
  });

  final GoalLinkedTransactionInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_busy_rounded, size: 18, color: Color(0xFFEA580C)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              info.deleteImpactMessage(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9A3412),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
