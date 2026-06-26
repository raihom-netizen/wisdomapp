import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Alerta clicável no Resumo — navega para Usuários com filtro aplicado.
class AdminAlertItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int count;

  const AdminAlertItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.count,
  });
}

typedef AdminAlertNavigate = void Function(String alertId);

/// Centro de alertas no Resumo (licenças, inativos, etc.).
class AdminAlertCenterPanel extends StatelessWidget {
  final List<AdminAlertItem> items;
  final AdminAlertNavigate onNavigate;

  const AdminAlertCenterPanel({
    super.key,
    required this.items,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final visible = items.where((e) => e.count > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.notifications_active_rounded,
                size: 22, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Text(
              'Centro de alertas',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...visible.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => onNavigate(item.id),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: item.color.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.icon, color: item.color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Badge(
                        label: Text('${item.count}'),
                        backgroundColor: item.color,
                        child: Icon(Icons.chevron_right_rounded,
                            color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Atalhos de filtro rápido na aba Usuários.
class AdminUserFilterPresetsBar extends StatelessWidget {
  final String? activePresetId;
  final ValueChanged<String> onPresetSelected;

  const AdminUserFilterPresetsBar({
    super.key,
    required this.activePresetId,
    required this.onPresetSelected,
  });

  static const presets = <({String id, String label, IconData icon})>[
    (id: 'vencidos', label: 'Vencidos', icon: Icons.event_busy_rounded),
    (id: 'vencendo_7', label: 'Vence 7d', icon: Icons.schedule_rounded),
    (id: 'premium', label: 'Premium', icon: Icons.star_rounded),
    (id: 'ultimos_10', label: 'Últimos 10', icon: Icons.person_add_rounded),
    (id: 'removidos', label: 'Removidos', icon: Icons.person_off_rounded),
    (id: 'convenio', label: 'Convênio', icon: Icons.handshake_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: activePresetId == p.id,
                showCheckmark: false,
                avatar: Icon(p.icon, size: 18),
                label: Text(p.label),
                onSelected: (_) => onPresetSelected(p.id),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
        ],
      ),
    );
  }
}
