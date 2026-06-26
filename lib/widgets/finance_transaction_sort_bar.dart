import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/finance_fatura_transaction_sort.dart';

/// Seletor de ordenação compartilhado nas grids de lançamentos do Financeiro.
class FinanceTransactionSortBar extends StatelessWidget {
  const FinanceTransactionSortBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final FinanceFaturaTxSortMode value;
  final ValueChanged<FinanceFaturaTxSortMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sort_rounded, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          if (!compact)
            const Text(
              'Ordenar',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          if (!compact) const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FinanceFaturaTxSortMode>(
                value: value,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final m in FinanceFaturaTxSortMode.values)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.label, style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
