import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/keyboard_form_scaffold.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;
  bool _obscurePass = true;
  String? _pendingPromoId;
  String? _afterLoginRoute;
  bool _openMpCheckoutAfterPromoLoad = false;
  bool _signupArgsRead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_signupArgsRead) return;
    _signupArgsRead = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final p = args['promoId']?.toString().trim();
      if (p != null && p.isNotEmpty) _pendingPromoId = p;
      final r = args['afterLoginRoute']?.toString().trim();
      if (r != null && r.isNotEmpty) _afterLoginRoute = r;
      if (args['openMpCheckoutAfterPromoLoad'] == true) {
        _openMpCheckoutAfterPromoLoad = true;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  String _friendlyError(dynamic e) {
    final s = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
    if (s.contains('email-already-in-use') ||
        s.toLowerCase().contains('email já')) {
      return 'Este e-mail já está em uso. Use outro ou faça login.';
    }
    if (s.contains('weak-password')) {
      return 'Senha muito fraca. Use no mínimo 6 caracteres.';
    }
    if (s.contains('invalid-email')) return 'E-mail inválido.';
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
      return 'Erro ao salvar dados. Tente novamente ou entre em contato.';
    }
    if (s.contains('network') || s.contains('unavailable')) {
      return 'Sem conexão. Verifique a internet e tente de novo.';
    }
    if (s.contains('Google') || s.contains('popup')) {
      return 'Erro ao criar conta. Tente novamente.';
    }
    return s.isEmpty ? 'Erro ao criar conta.' : s;
  }

  /// Cadastro manual: apenas createUserWithEmailAndPassword + updateDisplayName + Firestore.
  /// Separa totalmente do login social (Google); nenhum popup — evita popup-closed-by-user.
  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passController.text;
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Nome e e-mail são obrigatórios para identificação.')),
      );
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe um e-mail válido (ex.: nome@dominio.com).')),
      );
      return;
    }
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A senha deve ter no mínimo 6 caracteres.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.signUpSimple(name: name, email: email, password: pass);
      if (!mounted) return;
      // Envia e-mail profissional de confirmação (igual Controle Total).
      // Falha no envio NÃO bloqueia o cadastro — a tela de verificação mostra o erro e permite reenviar.
      String? emailSendError;
      try {
        await _auth.sendCustomVerificationEmail(email: email, name: name);
      } catch (e) {
        emailSendError =
            e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      }
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/email-verification',
        (route) => false,
        arguments: {
          'email': email,
          'name': name,
          if (emailSendError != null) 'emailSendError': emailSendError,
          if (_pendingPromoId != null && _pendingPromoId!.isNotEmpty)
            'promoId': _pendingPromoId,
          if (_afterLoginRoute != null && _afterLoginRoute!.isNotEmpty)
            'afterLoginRoute': _afterLoginRoute,
          if (_openMpCheckoutAfterPromoLoad)
            'openMpCheckoutAfterPromoLoad': true,
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String mensagem = 'Erro ao criar conta.';
      switch (e.code) {
        case 'weak-password':
          mensagem = 'Senha muito fraca. Use no mínimo 6 caracteres.';
          break;
        case 'email-already-in-use':
          mensagem = 'E-mail já cadastrado. Use outro ou faça login.';
          break;
        case 'invalid-email':
          mensagem = 'E-mail inválido.';
          break;
        case 'operation-not-allowed':
          mensagem = 'Cadastro por e-mail não está habilitado.';
          break;
        default:
          mensagem = e.message ?? mensagem;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagem), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_friendlyError(e)), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    const brandTeal = Color(0xFF2DD4BF);
    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
      backgroundColor: const Color(0xFF030712),
      body: keyboardScaffoldBody(
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF030712),
                Color(0xFF0f172a),
                Color(0xFF134e4a),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 28,
                right: 28,
                top: 20,
                bottom: viewPadding.bottom +
                    KeyboardFormInsets.scrollBottomExtra(context, extra: 24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          'Cadastro rápido',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nome completo e e-mail. Depois você pode completar seus dados no app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0f172a).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: brandTeal.withValues(alpha: 0.22), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: brandTeal.withValues(alpha: 0.15),
                          blurRadius: 36,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _field('Nome completo',
                                  Icons.person_outline_rounded, _nameController,
                                  autofillHints: const [AutofillHints.name],
                                  textInputAction: TextInputAction.next),
                              const SizedBox(height: 16),
                              _field('E-mail', Icons.email_outlined,
                                  _emailController,
                                  autofillHints: const [AutofillHints.email],
                                  textInputAction: TextInputAction.next),
                              const SizedBox(height: 16),
                              _field('Senha (mín. 6 caracteres)',
                                  Icons.lock_outline_rounded, _passController,
                                  isPass: true,
                                  autofillHints: const [
                                    AutofillHints.newPassword
                                  ],
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                if (!_loading) _signUp();
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // CRIAR CONTA — gradient button
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF14B8A6)
                                    .withValues(alpha: 0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: FilledButton(
                            onPressed: _loading ? null : _signUp,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                                _loading ? 'Criando conta...' : 'CRIAR CONTA',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    fontSize: 15)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Já tenho conta — outlined button
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Já tenho conta – Entrar',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: brandTeal,
                            side: BorderSide(
                                color: brandTeal.withValues(alpha: 0.4),
                                width: 1.3),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Footer badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user_rounded,
                          color: Colors.white.withValues(alpha: 0.35),
                          size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Seguro · Criptografado · Equipe Wisdom APP',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    IconData icon,
    TextEditingController ctrl, {
    bool isPass = false,
    List<String>? autofillHints,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return FastTextField(
      controller: ctrl,
      obscureText: isPass ? _obscurePass : false,
      autofillHints: autofillHints,
      textInputAction: textInputAction ??
          (isPass ? TextInputAction.done : TextInputAction.next),
      onSubmitted: onFieldSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 22),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                    _obscurePass
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 22,
                    color: const Color(0xFF94A3B8)),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              )
            : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.15))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.15))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF2DD4BF), width: 1.5)),
        filled: true,
        fillColor: const Color(0xFF1e293b),
      ),
    );
  }
}
