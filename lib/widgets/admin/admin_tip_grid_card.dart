import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/finance_tip_bank_entry.dart';
import '../../theme/app_colors.dart';
import '../../utils/admin_financial_tip_utils.dart';

class AdminTipGridCard extends StatelessWidget {
  const AdminTipGridCard({
    super.key,
    required this.doc,
    required this.index,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onToggleHome,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int index;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleFavorite;
  final ValueChanged<bool> onToggleHome;

  static const _gradients = <List<Color>>[
    [Color(0xFF0B1B4B), Color(0xFF1E40AF)],
    [Color(0xFF0F766E), Color(0xFF14B8A6)],
    [Color(0xFF7C3AED), Color(0xFFA855F7)],
    [Color(0xFFEA580C), Color(0xFFF97316)],
    [Color(0xFFBE123C), Color(0xFFE11D48)],
    [Color(0xFF4338CA), Color(0xFF6366F1)],
    [Color(0xFF047857), Color(0xFF10B981)],
  ];

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final titulo = (d['titulo'] ?? doc.id).toString();
    final ref = (d['referenciaBiblica'] ?? d['versiculo'] ?? '').toString().trim();
    final verse = (d['textoVersiculo'] ?? d['versiculoTexto'] ?? '').toString().trim();
    final desc = (d['descricao'] ?? '').toString().trim();
    final colorKey = (d['cor'] ?? d['colorKey'] ?? 'primary').toString();
    final iconKey = (d['icone'] ?? d['iconKey'] ?? 'lightbulb').toString();
    final accent = kFinanceTipColorByKey[colorKey] ?? const Color(0xFF2D5BFF);
    final icon = kFinanceTipIconByKey[iconKey] ?? Icons.lightbulb_outline_rounded;
    final grad = _gradients[index % _gradients.length];
    final ativo = d['ativo'] != false;
    final favorita = d['favorita'] == true;
    final exibirNoInicio = d['exibirNoInicio'] == true;
    final biblical = AdminFinancialTipUtils.isBiblical(d);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (exibirNoInicio
                      ? const Color(0xFF0F766E).withValues(alpha: 0.5)
                      : Colors.grey.shade200),
              width: selected || exibirNoInicio ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: grad[0].withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(grad[0], accent, 0.35)!,
                          Color.lerp(grad[1], accent, 0.15)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (biblical)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'BÍBLICA',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              Text(
                                titulo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                  height: 1.2,
                                ),
                              ),
                              if (ref.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  ref,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            verse.isNotEmpty ? '"$verse"' : desc,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: verse.isNotEmpty ? FontStyle.italic : FontStyle.normal,
                              color: Colors.grey.shade800,
                              height: 1.35,
                            ),
                          ),
                          const Spacer(),
                          if (!ativo)
                            Text(
                              'Inativa',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade400,
                              ),
                            ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: favorita ? 'Remover favorita' : 'Favorita',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => onToggleFavorite(!favorita),
                                icon: Icon(
                                  favorita ? Icons.star_rounded : Icons.star_outline_rounded,
                                  color: favorita ? const Color(0xFFD97706) : Colors.grey.shade500,
                                  size: 22,
                                ),
                              ),
                              IconButton(
                                tooltip: exibirNoInicio ? 'No Início' : 'Marcar Início',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => onToggleHome(!exibirNoInicio),
                                icon: Icon(
                                  exibirNoInicio ? Icons.home_rounded : Icons.home_outlined,
                                  color: exibirNoInicio ? const Color(0xFF0F766E) : Colors.grey.shade500,
                                  size: 22,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Editar',
                                visualDensity: VisualDensity.compact,
                                onPressed: onEdit,
                                icon: Icon(Icons.edit_outlined, color: Colors.grey.shade700, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Excluir',
                                visualDensity: VisualDensity.compact,
                                onPressed: onDelete,
                                icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (selectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: selected ? AppColors.primary : Colors.white,
                    child: Icon(
                      selected ? Icons.check_rounded : Icons.circle_outlined,
                      size: 18,
                      color: selected ? Colors.white : Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
