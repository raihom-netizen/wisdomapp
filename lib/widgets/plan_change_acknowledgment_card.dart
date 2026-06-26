import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'plan_change_contract_sheet.dart';

/// Aviso antes do pagamento: responsabilidade do usuário + termo completo.
class PlanChangeAcknowledgmentCard extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onAcceptedChanged;

  const PlanChangeAcknowledgmentCard({
    super.key,
    required this.accepted,
    required this.onAcceptedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            const Color(0xFF0D9488).withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
                    ],
                  ),
                  child: Icon(Icons.policy_rounded, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Antes de mudar de plano',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A contratação e a escolha do plano são de sua responsabilidade. Revise valor, período (mensal ou anual) e '
              'benefícios do plano Premium antes de concluir o pagamento.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Colors.blueGrey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => showPlanChangeContractBottomSheet(context),
              icon: Icon(Icons.article_outlined, size: 20, color: AppColors.primary.withValues(alpha: 0.9)),
              label: Text(
                'Ler termo completo de contratação',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary.withValues(alpha: 0.95),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Material(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
              child: CheckboxListTile(
                value: accepted,
                onChanged: (v) => onAcceptedChanged(v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                title: const Text(
                  'Confirmo que li o aviso acima e aceito o termo de contratação e responsabilidade pela escolha do plano.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
