import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../theme/agenda_modern_ui.dart';
import '../utils/agenda_finance_pending_utils.dart';

/// Cartão azul (receita) ou laranja (despesa) pendente — integrado à grid da Agenda.
class AgendaFinancePendingItemCard extends StatelessWidget {
  const AgendaFinancePendingItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  final AgendaFinancePendingItem item;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _incomeGradient = [
    Color(0xFF0EA5E9),
    Color(0xFF0284C7),
  ];
  static const _expenseGradient = [
    Color(0xFFF97316),
    Color(0xFFEA580C),
  ];

  @override
  Widget build(BuildContext context) {
    final isIncome = item.isIncome;
    final gradient = isIncome ? _incomeGradient : _expenseGradient;
    final data = item.data;
    final cat = (data['category'] ?? '').toString().trim();
    final desc = (data['description'] ?? data['descricao'] ?? '').toString().trim();
    final title = desc.isNotEmpty
        ? desc
        : (cat.isNotEmpty ? cat : (isIncome ? 'Receita pendente' : 'Despesa pendente'));
    final amount = ((data['amount'] ?? 0) as num).toDouble().abs();
    final day = agendaFinanceEffectiveDay(data);
    final dateLine = day != null
        ? DateFormat('dd/MM/yyyy', 'pt_BR').format(day)
        : '';

    return AgendaModernFadeIn(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              gradient.first.withValues(alpha: 0.14),
              gradient.last.withValues(alpha: 0.08),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: gradient.first.withValues(alpha: 0.45), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradient),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Color(0xFF1A237E),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: gradient),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isIncome ? 'RECEITA' : 'DESPESA',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (dateLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            dateLine,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: gradient.last,
                            ),
                          ),
                        ],
                        if (cat.isNotEmpty && desc.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Categoria: $cat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormats.formatBRL(amount),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: gradient.last,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: gradient.first.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: gradient.first.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: gradient.last,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Pendente · Financeiro',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: gradient.last,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Excluir',
                    icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    padding: EdgeInsets.zero,
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text(
                  'Editar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: gradient.first,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 42),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa resumo azul ou laranja (totais do dia selecionado).
class AgendaFinancePendingDayBand extends StatelessWidget {
  const AgendaFinancePendingDayBand({
    super.key,
    required this.isIncome,
    required this.count,
    required this.total,
  });

  final bool isIncome;
  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final gradient = isIncome
        ? AgendaFinancePendingItemCard._incomeGradient
        : AgendaFinancePendingItemCard._expenseGradient;
    final label = isIncome ? 'Receitas pendentes' : 'Despesas pendentes';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.98),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count lançamento${count == 1 ? '' : 's'} neste dia',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormats.formatBRL(total),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
