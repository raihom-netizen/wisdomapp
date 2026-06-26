import 'package:flutter/material.dart';

import '../constants/app_brand.dart';
import '../theme/app_colors.dart';

/// Termos de Uso do WISDOMAPP (Wisdom App).
class TermosScreen extends StatelessWidget {
  const TermosScreen({super.key});

  static List<_Section> _sectionsForApp() {
    const pagamentos =
        'Os planos pagos são processados via Mercado Pago (PIX ou cartão). As condições de reembolso seguem a política do Mercado Pago e podem ser solicitadas diretamente à plataforma.';
    return [
      _Section('1. Aceitação', [
        'Ao utilizar o ${AppBrand.name}, você concorda com estes Termos de Uso. Se não concordar, não utilize o serviço.',
      ]),
      _Section('2. Serviço', [
        'O ${AppBrand.legalName} oferece ferramentas de sabedoria financeira com princípios bíblicos: módulo financeiro (receitas, despesas, metas e relatórios), agenda com lembretes e cursos financeiros. Acesso pelo celular, computador ou notebook. Os planos e funcionalidades seguem o plano Premium contratado.',
      ]),
      const _Section('3. Conta e licença', [
        'Você é responsável por manter a confidencialidade do login. O acesso depende da licença ativa (trial, assinatura ou plano gratuito). A licença vencida restringe o uso conforme a política do app.',
      ]),
      const _Section('4. Uso adequado', [
        'Você se compromete a usar o app de forma lícita, sem prejudicar terceiros ou o serviço. É proibido o uso para atividades ilegais, envio de conteúdo ofensivo ou tentativas de acesso não autorizado.',
      ]),
      _Section('5. Propriedade intelectual', [
        'Todo o conteúdo e a tecnologia do ${AppBrand.name} são de propriedade do desenvolvedor. Você tem direito de usar o serviço conforme previsto nestes termos.',
      ]),
      const _Section('6. Pagamentos', [pagamentos]),
      const _Section('7. Limitação de responsabilidade', [
        'O app é fornecido "como está". Não nos responsabilizamos por decisões tomadas com base nos dados ou relatórios gerados. Recomendamos validação por profissionais quando necessário.',
      ]),
      const _Section('8. Alterações', [
        'Podemos alterar estes termos. Alterações significativas serão comunicadas no app. O uso continuado após as alterações indica aceitação.',
      ]),
      _Section('9. Contato', [
        'Dúvidas: ${AppBrand.supportEmail} ou WhatsApp 62 9 9671-3032.',
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Termos de Uso'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Termos de Uso',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '${AppBrand.name} — Última atualização: fevereiro de 2026',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Text(
                'Leia atentamente estes Termos de Uso antes de utilizar o ${AppBrand.name}.',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.6),
              ),
              const SizedBox(height: 28),
              ..._sectionsForApp().map((s) => _buildSection(s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(_Section s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          ...s.paragraphs.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(p,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                        height: 1.6)),
              )),
        ],
      ),
    );
  }
}

class _Section {
  final String title;
  final List<String> paragraphs;

  const _Section(this.title, this.paragraphs);
}
