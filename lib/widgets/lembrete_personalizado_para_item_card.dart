import 'package:flutter/material.dart';

import '../constants/reminder_lead_chip_presets.dart';
import '../theme/app_colors.dart';

/// Lembrete específico do item — quando ativo, substitui o padrão global
/// (`settings/notifications`) só para este lançamento (plantão, pré-cadastro ou agenda).
class LembretePersonalizadoParaItemCard extends StatelessWidget {
  const LembretePersonalizadoParaItemCard({
    super.key,
    required this.useCustom,
    required this.selectedMinutes,
    required this.onCustomChanged,
    required this.onMinutesChanged,
    required this.itemLabel,
    this.dense = false,
  });

  final bool useCustom;
  final List<int> selectedMinutes;
  final ValueChanged<bool> onCustomChanged;
  final ValueChanged<List<int>> onMinutesChanged;
  /// Ex.: «plantão», «compromisso», «audiência»
  final String itemLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, dense ? 8 : 10, 12, dense ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: AppColors.primary, size: dense ? 20 : 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lembretes',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: dense ? 13 : 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: dense ? 4 : 6),
            Text(
              useCustom
                  ? 'Personalizado para este $itemLabel'
                  : 'Usa o padrão global (Configurações → Notificações)',
              style: TextStyle(
                fontSize: dense ? 11 : 11.5,
                color: AppColors.textMuted,
                height: 1.25,
              ),
            ),
            SizedBox(height: dense ? 6 : 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: dense,
              value: useCustom,
              onChanged: onCustomChanged,
              title: Text(
                'Lembrete personalizado',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: dense ? 13 : 13.5,
                ),
              ),
              subtitle: Text(
                'Quando ligado, ignora as antecedências gerais só para este $itemLabel.',
                style: TextStyle(
                  fontSize: dense ? 10.5 : 11,
                  color: AppColors.textMuted,
                ),
              ),
              activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
              activeThumbColor: Colors.white,
            ),
            if (useCustom) ...[
              SizedBox(height: dense ? 4 : 6),
              Wrap(
                spacing: dense ? 6 : 8,
                runSpacing: dense ? 6 : 8,
                children: [
                  for (final opt in kReminderLeadChipPresets)
                    FilterChip(
                      label: Text(opt.label),
                      selected: selectedMinutes.contains(opt.minutes),
                      onSelected: (v) {
                        final next = List<int>.from(selectedMinutes);
                        if (v) {
                          if (!next.contains(opt.minutes)) next.add(opt.minutes);
                        } else {
                          next.remove(opt.minutes);
                        }
                        onMinutesChanged(next);
                      },
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontSize: dense ? 11.5 : 12.5,
                        fontWeight: FontWeight.w700,
                        color: selectedMinutes.contains(opt.minutes)
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.06),
                      side: BorderSide(
                        color: selectedMinutes.contains(opt.minutes)
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.2),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
              if (selectedMinutes.isEmpty) ...[
                SizedBox(height: dense ? 6 : 8),
                Text(
                  'Selecione pelo menos uma antecedência ou desligue o personalizado.',
                  style: TextStyle(
                    fontSize: dense ? 11 : 11.5,
                    color: const Color(0xFFB45309),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
