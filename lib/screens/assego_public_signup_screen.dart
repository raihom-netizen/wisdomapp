import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../services/functions_service.dart';
import '../theme/app_colors.dart';

class AssegoPublicSignupScreen extends StatefulWidget {
  const AssegoPublicSignupScreen({super.key, this.partnershipId});

  final String? partnershipId;

  @override
  State<AssegoPublicSignupScreen> createState() =>
      _AssegoPublicSignupScreenState();
}

class _AssegoPublicSignupScreenState extends State<AssegoPublicSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  bool _sent = false;
  String? _resultMessage;
  late final String _partnershipId;

  @override
  void initState() {
    super.initState();
    final fromParam = widget.partnershipId?.trim().toLowerCase();
    final fromQuery = Uri.base.queryParameters['id']?.trim().toLowerCase();
    _partnershipId =
        (fromParam != null && fromParam.isNotEmpty) ? fromParam : ((fromQuery != null && fromQuery.isNotEmpty) ? fromQuery : 'assego');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cpfCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _resultMessage = null;
    });
    try {
      final res = await FunctionsService().publicPartnershipSignup(
        partnershipId: _partnershipId,
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        phone: _phoneCtrl.text,
        cpf: _cpfCtrl.text,
        notes: _notesCtrl.text,
      );
      if (!mounted) return;
      final ok = res['ok'] == true;
      setState(() {
        _sent = ok;
        _resultMessage = ok
            ? 'Cadastro enviado com sucesso. A equipe do WISDOMAPP já foi notificada para conferência no painel ADM.'
            : 'Não foi possível concluir agora. Tente novamente.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultMessage =
            'Erro ao enviar cadastro: ${e.toString().split('\n').first}';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateName(String? value) {
    final v = (value ?? '').trim();
    if (v.length < 3) return 'Informe o nome completo';
    return null;
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
    if (!ok) return 'Informe um e-mail válido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 640;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 16 : 22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.handshake_rounded,
                                color: AppColors.deepBlue, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Pré-cadastro ${_partnershipId.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: compact ? 21 : 24,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A237E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Preencha os dados abaixo. O cadastro entra automaticamente no convênio ${_partnershipId.toUpperCase()}, gera CSV e notifica a administração no painel ADM.',
                          style: TextStyle(
                            height: 1.35,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FastTextField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          validator: _validateName,
                          decoration: const InputDecoration(
                            labelText: 'Nome completo *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FastTextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          validator: _validateEmail,
                          decoration: const InputDecoration(
                            labelText: 'E-mail *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FastTextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Telefone',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FastTextField(
                          controller: _cpfCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'CPF',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FastTextField(
                          controller: _notesCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Observações',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _saving || _sent ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(_saving
                              ? 'Enviando...'
                              : (_sent ? 'Cadastro enviado' : 'Enviar cadastro')),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            backgroundColor: AppColors.deepBlue,
                          ),
                        ),
                        if (_resultMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _sent
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _sent
                                    ? Colors.green.shade300
                                    : Colors.orange.shade300,
                              ),
                            ),
                            child: Text(
                              _resultMessage!,
                              style: TextStyle(
                                color: _sent
                                    ? Colors.green.shade900
                                    : Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
