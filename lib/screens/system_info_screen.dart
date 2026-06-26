import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/app_verse.dart';
import '../constants/app_brand.dart';
import '../theme/app_colors.dart';
import '../services/user_feedback_service.dart';

/// Tela Informações do Sistema: resumo geral, créditos, sugestões/críticas.
class SystemInfoScreen extends StatefulWidget {
  final String uid;
  final String? userEmail;
  final String? userName;

  const SystemInfoScreen({
    super.key,
    required this.uid,
    this.userEmail,
    this.userName,
  });

  @override
  State<SystemInfoScreen> createState() => _SystemInfoScreenState();
}

class _SystemInfoScreenState extends State<SystemInfoScreen> {
  final _feedbackController = TextEditingController();
  final _feedbackService = UserFeedbackService();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback() async {
    final msg = _feedbackController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite sua sugestão ou crítica.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _feedbackService.sendFeedback(
        uid: widget.uid,
        email: widget.userEmail,
        name: widget.userName,
        message: msg,
      );
      if (mounted) {
        setState(() {
          _sending = false;
          _sent = true;
          _feedbackController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Obrigado! Sua mensagem foi enviada. Você receberá retorno no app quando respondermos.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informações do Sistema'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 32),
                        const SizedBox(width: 12),
                        const Text(
                          'Resumo do sistema',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'O WISDOMAPP App concentra-se em três módulos: Financeiro '
                      '(controle de gastos e relatórios), Agenda '
                      '(compromissos e lembretes) e Cursos '
                      '(conteúdos e formação). Inclui backup local, '
                      'sincronização na nuvem e dicas financeiras com base na Bíblia.',
                      style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agradecemos por usar o WISDOMAPP App. Sua confiança nos motiva a melhorar sempre.',
                      style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Idealizado por',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppBrand.idealizerName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Desenvolvido por',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppBrand.developerName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Sugestões ou críticas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
              ),
              child: Column(
                children: [
                  Text(
                    'Idealizado por ${AppBrand.idealizerName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Desenvolvido por ${AppBrand.developerName}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Envie sua opinião. Leio todas as mensagens e respondo pelo app.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: _feedbackController,
              maxLines: 4,
              enabled: !_sending && !_sent,
              decoration: InputDecoration(
                hintText: 'Digite sua sugestão ou crítica...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_sending || _sent) ? null : _sendFeedback,
                icon: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_sent ? Icons.check_rounded : Icons.send_rounded, size: 20),
                label: Text(_sending ? 'Enviando...' : _sent ? 'Enviado' : 'Enviar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => Text(
                snap.hasData ? 'Versão ${snap.data!.version}+${snap.data!.buildNumber}' : '',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppVerse.full,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.3,
                color: AppColors.textMuted.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
