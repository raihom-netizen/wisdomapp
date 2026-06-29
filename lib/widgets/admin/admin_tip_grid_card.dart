import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/finance_tip_bank_entry.dart';
import '../../theme/app_colors.dart';
import '../../utils/admin_financial_tip_utils.dart';

/// Card compacto — só cabeçalho colorido; detalhes via olho ou toque.
class AdminTipGridCard extends StatelessWidget {
  const AdminTipGridCard({
    super.key,
    required this.doc,
    required this.index,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onViewDetail,
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
  final VoidCallback onViewDetail;
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
    final colorKey = (d['cor'] ?? d['colorKey'] ?? 'primary').toString();
    final iconKey = (d['icone'] ?? d['iconKey'] ?? 'lightbulb').toString();
    final accent = kFinanceTipColorByKey[colorKey] ?? const Color(0xFF2D5BFF);
    final icon = kFinanceTipIconByKey[iconKey] ?? Icons.lightbulb_outline_rounded;
    final grad = _gradients[index % _gradients.length];
    final ativo = d['ativo'] != false;
    final favorita = d['favorita'] == true;
    final exibirNoInicio = d['exibirNoInicio'] == true;
    final biblical = AdminFinancialTipUtils.isBiblical(d);

    final c1 = Color.lerp(grad[0], accent, 0.35)!;
    final c2 = Color.lerp(grad[1], accent, 0.15)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [c1, c2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : (exibirNoInicio
                      ? Colors.white.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.12)),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: c1.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (biblical)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'BÍBLICA',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                if (!ativo)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'OFF',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                if (exibirNoInicio)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.home_rounded,
                                      size: 13,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              titulo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                height: 1.15,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (ref.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                ref,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            _ActionRow(
                              onViewDetail: onViewDetail,
                              onToggleFavorite: () => onToggleFavorite(!favorita),
                              onToggleHome: () => onToggleHome(!exibirNoInicio),
                              onEdit: onEdit,
                              onDelete: onDelete,
                              favorita: favorita,
                              exibirNoInicio: exibirNoInicio,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectionMode)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: selected ? Colors.white : Colors.black26,
                      child: Icon(
                        selected ? Icons.check_rounded : Icons.circle_outlined,
                        size: 14,
                        color: selected ? AppColors.primary : Colors.white70,
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                      child: const SizedBox(height: 6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onViewDetail,
    required this.onToggleFavorite,
    required this.onToggleHome,
    required this.onEdit,
    required this.onDelete,
    required this.favorita,
    required this.exibirNoInicio,
  });

  final VoidCallback onViewDetail;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleHome;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool favorita;
  final bool exibirNoInicio;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MiniBtn(
          icon: Icons.visibility_rounded,
          tooltip: 'Ver detalhes',
          onPressed: onViewDetail,
          highlight: true,
        ),
        _MiniBtn(
          icon: favorita ? Icons.star_rounded : Icons.star_outline_rounded,
          tooltip: favorita ? 'Remover favorita' : 'Favorita',
          onPressed: onToggleFavorite,
          color: favorita ? const Color(0xFFFFD54F) : Colors.white70,
        ),
        _MiniBtn(
          icon: exibirNoInicio ? Icons.home_rounded : Icons.home_outlined,
          tooltip: exibirNoInicio ? 'No Início' : 'Marcar Início',
          onPressed: onToggleHome,
          color: exibirNoInicio ? const Color(0xFF99F6E4) : Colors.white70,
        ),
        const Spacer(),
        _MiniBtn(
          icon: Icons.edit_outlined,
          tooltip: 'Editar',
          onPressed: onEdit,
        ),
        _MiniBtn(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Excluir',
          onPressed: onDelete,
          color: const Color(0xFFFCA5A5),
        ),
      ],
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.highlight = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlight
            ? Colors.white.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: highlight ? 17 : 15,
              color: color ?? Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ),
      ),
    );
  }
}
