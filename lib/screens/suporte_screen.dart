import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../theme/app_colors.dart';
import '../services/user_feedback_service.dart';

/// Página de Suporte — igual à página de sugestões: usuário envia mensagem, admin responde no painel.
/// Não exibe telefone nem e-mail; todo atendimento via Admin > Sugestões.
class SuporteScreen extends StatefulWidget {
  const SuporteScreen({super.key});

  @override
  State<SuporteScreen> createState() => _SuporteScreenState();
}

class _SuporteScreenState extends State<SuporteScreen> {
  final _messageController = TextEditingController();
  final _feedbackService = UserFeedbackService();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite sua mensagem.')),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login para enviar.')),
      );
      return;
    }

    String? name;
    String? email = user.email;
    try {
      final userDoc = await FirebaseFirestore.instance.doc('users/${user.uid}').get();
      if (userDoc.exists) {
        final d = userDoc.data() ?? {};
        name = (d['name'] ?? '').toString();
        if ((email ?? '').isEmpty) email = (d['email'] ?? '').toString();
      }
    } catch (_) {}

    setState(() => _sending = true);
    try {
      await _feedbackService.sendFeedback(
        uid: user.uid,
        email: email,
        name: name,
        message: msg,
      );
      if (mounted) {
        setState(() {
          _sending = false;
          _sent = true;
          _messageController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mensagem enviada. Você receberá retorno no app quando respondermos.'),
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
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suporte'),
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
              'Central de Suporte',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Envie sua dúvida ou problema. Atendemos pelo painel do app e você receberá a resposta aqui.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.6),
            ),
            const SizedBox(height: 28),
            if (isLoggedIn) ...[
              const Text(
                'Sua mensagem',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FastTextField(
                controller: _messageController,
                maxLines: 5,
                enabled: !_sending && !_sent,
                decoration: InputDecoration(
                  hintText: 'Digite sua dúvida, problema ou sugestão...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_sending || _sent) ? null : _sendMessage,
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
            ] else ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: AppColors.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.login_rounded, size: 48, color: AppColors.primary),
                      const SizedBox(height: 16),
                      const Text(
                        'Faça login para enviar',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Entre na sua conta para enviar sua mensagem de suporte. Você receberá a resposta no próprio app.',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                          icon: const Icon(Icons.login_rounded, size: 20),
                          label: const Text('Entrar'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
