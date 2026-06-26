import 'package:flutter/material.dart';

import '../models/finance_tip_bank_entry.dart';
import '../services/financial_tips_catalog_service.dart';

/// Card premium colorido para dicas financeiras (Início / Dicas).
class FinanceTipModernCard extends StatelessWidget {
  const FinanceTipModernCard({
    super.key,
    required this.tip,
    required this.index,
    this.isTipOfDay = false,
    this.showFullText = true,
    this.compact = false,
  });

  final FinancialTipDisplayItem tip;
  final int index;
  final bool isTipOfDay;
  final bool showFullText;
  final bool compact;

  static const _gradients = <List<Color>>[
    [Color(0xFF0B1B4B), Color(0xFF1E40AF)],
    [Color(0xFF0F766E), Color(0xFF14B8A6)],
    [Color(0xFF7C3AED), Color(0xFFA855F7)],
    [Color(0xFFEA580C), Color(0xFFF97316)],
    [Color(0xFFBE123C), Color(0xFFE11D48)],
    [Color(0xFF4338CA), Color(0xFF6366F1)],
    [Color(0xFF047857), Color(0xFF10B981)],
    [Color(0xFF0E7490), Color(0xFF06B6D4)],
  ];

  @override
  Widget build(BuildContext context) {
    final accent = kFinanceTipColorByKey[tip.colorKey] ?? tip.colorFromKey;
    final grad = _gradients[index % _gradients.length];
    final icon = kFinanceTipIconByKey[tip.iconKey] ?? Icons.menu_book_rounded;
    final ref = tip.referenciaBiblica.trim();
    final verse = tip.textoVersiculo.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetail(context, grad, accent, icon),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                Color.lerp(grad[0], accent, 0.35)!,
                Color.lerp(grad[1], accent, 0.2)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: isTipOfDay
                ? Border.all(color: Colors.amber.shade200, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: grad[0].withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 44 : 52,
                      height: compact ? 44 : 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      child: Icon(icon, color: Colors.white, size: compact ? 24 : 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (isTipOfDay)
                                _badge('DICA DO DIA', Colors.amber.shade700),
                              if (ref.isNotEmpty)
                                _badge(ref, Colors.white.withValues(alpha: 0.22)),
                            ],
                          ),
                          if (isTipOfDay || ref.isNotEmpty) const SizedBox(height: 8),
                          Text(
                            tip.titulo,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: compact ? 15 : 17,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (verse.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: Text(
                      '“$verse”',
                      style: TextStyle(
                        color: Colors.amber.shade50,
                        fontSize: compact ? 13 : 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  tip.descricao,
                  maxLines: showFullText ? null : 4,
                  overflow: showFullText ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.94),
                    fontSize: compact ? 13 : 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  void _openDetail(
    BuildContext context,
    List<Color> grad,
    Color accent,
    IconData icon,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [grad[0], Color.lerp(grad[1], accent, 0.3)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(icon, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          tip.titulo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (tip.referenciaBiblica.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      tip.referenciaBiblica,
                      style: TextStyle(
                        color: Colors.amber.shade100,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (tip.textoVersiculo.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '“${tip.textoVersiculo.trim()}”',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 16,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    tip.descricao,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 16,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

extension _TipColor on FinancialTipDisplayItem {
  Color get colorFromKey =>
      kFinanceTipColorByKey[colorKey] ?? const Color(0xFF2D5BFF);
}
