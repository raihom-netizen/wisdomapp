import 'package:flutter/material.dart';

import '../constants/app_brand.dart';
import '../theme/app_colors.dart';

/// Política de Privacidade do WISDOMAPP (Wisdom App).
class PrivacidadeScreen extends StatelessWidget {
  const PrivacidadeScreen({super.key});

  static List<_Section> _sectionsForApp() {
    const compartilhamento =
        'Não vendemos seus dados. Podemos compartilhar informações apenas quando exigido por lei ou para processar pagamentos via Mercado Pago.';
    return [
      const _Section('1. Informações que coletamos', [
        'Coletamos os dados necessários para o funcionamento do app: nome, e-mail, CPF (opcional), dados financeiros (receitas, despesas, metas), compromissos de agenda, progresso em cursos e configurações que você informa. O login pode ser feito por e-mail e senha, conta Google ou, no iOS, Entrar com a Apple.',
      ]),
      _Section('2. Uso dos dados', [
        'O ${AppBrand.name} (${AppBrand.legalName}) oferece ${AppBrand.tagline} Utilizamos seus dados exclusivamente para: prestar os serviços do ${AppBrand.legalName}; personalizar sua experiência; enviar comunicações sobre a conta e planos; melhorar o app e a segurança.',
      ]),
      const _Section('3. Armazenamento e segurança', [
        'Os dados são armazenados em infraestrutura segura (Firebase/Google Cloud). Aplicamos medidas técnicas para proteger suas informações contra acesso não autorizado.',
      ]),
      const _Section('4. Compartilhamento', [compartilhamento]),
      const _Section('5. Seus direitos', [
        'Você pode solicitar acesso, correção ou exclusão dos seus dados. Para isso, entre em contato pelo e-mail ou WhatsApp indicados na página de Suporte.',
      ]),
      const _Section('6. Atualizações', [
        'Esta política pode ser atualizada. Alterações significativas serão comunicadas no app ou por e-mail. O uso continuado após alterações indica aceitação.',
      ]),
      _Section('7. Biometria e reconhecimento facial (Face ID)', [
        'O app não coleta, não armazena e não envia ao servidor imagens do rosto, mapas faciais ou templates biométricos.',
        'O uso de Face ID ou impressão digital é opcional e serve apenas para desbloquear uma sessão já autenticada neste aparelho, por meio da API LocalAuthentication do sistema operacional (Apple). O processamento biométrico ocorre no dispositivo (Secure Enclave); nós não recebemos esses dados.',
        'Não compartilhamos dados faciais com terceiros porque não temos acesso a eles. Podemos guardar apenas uma preferência sua (por exemplo, se o desbloqueio por biometria está ativado), sem dados biométricos.',
        'Não há retenção de dados faciais por parte do ${AppBrand.legalName}, pois esses dados não são transmitidos aos nossos sistemas.',
      ]),
      _Section('8. Contato', [
        'Dúvidas sobre privacidade: ${AppBrand.supportEmail} ou WhatsApp 62 9 9671-3032.',
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Política de Privacidade'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Política de Privacidade',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '${AppBrand.name} — Última atualização: março de 2026',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Text(
                'O ${AppBrand.name} ("nós", "nosso") respeita sua privacidade. Esta política descreve como tratamos seus dados pessoais.',
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
