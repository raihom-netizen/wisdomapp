import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Tela para o usuário que fez cadastro rápido completar seus dados (ex.: CPF) e poder usar login por CPF depois.
class CompleteProfileScreen extends StatefulWidget {
  final String uid;
  final String currentEmail;
  final String currentName;

  const CompleteProfileScreen({
    super.key,
    required this.uid,
    required this.currentEmail,
    required this.currentName,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _cpfController = TextEditingController();
  final _auth = AuthService();
  bool _saving = false;

  @override
  void dispose() {
    _cpfController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _auth.completeProfile(
        widget.uid,
        cpf: _cpfController.text.trim().isEmpty ? null : _cpfController.text.trim(),
        email: widget.currentEmail,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado. Você pode usar CPF para login quando quiser.'), backgroundColor: AppColors.success),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: ${e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '')}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        title: const Text('Completar meus dados'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Se quiser, informe seu CPF para poder entrar também com CPF e senha depois.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 24),
            FastTextField(
              controller: _cpfController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'CPF (opcional)',
                hintText: '000.000.000-00',
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Salvando...' : 'Concluir'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Deixar para depois'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
