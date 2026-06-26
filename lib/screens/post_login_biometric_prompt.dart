import 'package:flutter/material.dart';
import '../services/biometric_auth_service.dart';

/// Tela exibida após o primeiro login: pergunta se o usuário deseja ativar biometria.
class PostLoginBiometricPrompt extends StatelessWidget {
  final VoidCallback onDone;

  const PostLoginBiometricPrompt({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE0EAFC), Color(0xFFCFDEF3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fingerprint_rounded,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Deseja ativar acesso por digital ou facial?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Você escolhe: ao ativar, no próximo acesso o app abrirá com digital ou reconhecimento facial, sem precisar digitar. Se não ativar, continuará entrando com Google ou e-mail e senha.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 15),
                ),
                const SizedBox(height: 40),
                FilledButton(
                  onPressed: () => _onYes(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2962FF),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Sim, ativar'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => _onNo(context),
                  child: const Text('Não, obrigado'),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _onYes(BuildContext context) async {
    try {
      final ok = await authenticateWithBiometric();
      if (!context.mounted) return;
      if (ok) {
        await BiometricPreferences.setEnabled(true);
        await BiometricPreferences.setAsked();
      } else {
        await BiometricPreferences.setAsked();
      }
    } catch (_) {
      if (context.mounted) {
        await BiometricPreferences.setAsked();
      }
    }
    if (context.mounted) onDone();
  }

  Future<void> _onNo(BuildContext context) async {
    await BiometricPreferences.setAsked();
    if (context.mounted) onDone();
  }
}
