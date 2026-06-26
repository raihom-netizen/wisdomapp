import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Termo de contratação / responsabilidade na mudança de plano (paywall).
Future<void> showPlanChangeContractBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.gavel_rounded, color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Termo de contratação e responsabilidade',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: const [
                    _TermSection(
                      title: '1. Aceite',
                      body:
                          'Ao assinar ou renovar um plano pago, você declara ter lido e compreendido este termo, '
                          'bem como os Termos de Uso e a Política de Privacidade do WISDOMAPP disponíveis no app e no site.',
                    ),
                    _TermSection(
                      title: '2. Responsabilidade pela escolha do plano',
                      body:
                          'A escolha do plano (mensal, anual, promoções ou upgrades), a forma de pagamento e a confirmação '
                          'da compra são de sua exclusiva responsabilidade. O aplicativo apresenta informações para apoiar '
                          'sua decisão, mas não substitui sua análise do valor, do período de licença e das condições exibidas '
                          'no checkout (Mercado Pago ou outro meio indicado).',
                    ),
                    _TermSection(
                      title: '3. Pagamento e licença',
                      body:
                          'O processamento do pagamento é realizado por provedor terceiro (ex.: Mercado Pago). A liberação '
                          'ou extensão da licença ocorre após confirmação desse provedor. Atrasos, estornos ou contestações '
                          'seguem as regras do provedor de pagamento e da legislação aplicável.',
                    ),
                    _TermSection(
                      title: '4. Uso consciente',
                      body:
                          'Você é responsável por manter seus dados de cadastro corretos, proteger sua conta e revisar '
                          'periódicamente seu plano e vencimento da licença nas Configurações do app.',
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Última atualização: documento orientativo integrado ao fluxo de planos. Em caso de dúvida, use o canal de Suporte no app.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendi'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _TermSection extends StatelessWidget {
  final String title;
  final String body;

  const _TermSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A))),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF334155)),
          ),
        ],
      ),
    );
  }
}
