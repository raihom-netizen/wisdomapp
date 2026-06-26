import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/ios_payments_gate.dart';
import '../services/push_notification_service.dart';
import '../services/version_check_service.dart';
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
    if (s.contains('email-already-in-use') || s.toLowerCase().contains('email já')) return 'Este e-mail já está em uso. Use outro ou faça login.';
    if (s.contains('weak-password')) return 'Senha muito fraca. Use no mínimo 6 caracteres.';
    if (s.contains('invalid-email')) return 'E-mail inválido.';
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) return 'Erro ao salvar dados. Tente novamente ou entre em contato.';
    if (s.contains('network') || s.contains('unavailable')) return 'Sem conexão. Verifique a internet e tente de novo.';
    if (s.contains('Google') || s.contains('popup')) return 'Erro ao criar conta. Tente novamente.';
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
        const SnackBar(content: Text('Nome e e-mail são obrigatórios para identificação.')),
      );
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um e-mail válido (ex.: nome@dominio.com).')),
      );
      return;
    }
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A senha deve ter no mínimo 6 caracteres.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.signUpSimple(name: name, email: email, password: pass);
      if (!mounted) return;
      PushNotificationService().inicializar().catchError((_) {});
      VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
      final pid = _pendingPromoId;
      if (_afterLoginRoute == '/escolha-plano' && pid != null && pid.isNotEmpty) {
        if (IosPaymentsGate.shouldHidePayments && IosPaymentsGate.isIosNative) {
          IosPaymentsGate.openReaderPlansInSafari(source: 'signup_promo');
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          return;
        }
        final m = <String, dynamic>{'promoId': pid};
        if (_openMpCheckoutAfterPromoLoad) {
          m['openMpCheckoutAfterPromoLoad'] = true;
        }
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/escolha-plano',
          (route) => false,
          arguments: m,
        );
        return;
      }
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
        SnackBar(content: Text(_friendlyError(e)), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
      body: keyboardScaffoldBody(
        SafeArea(
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE0EAFC), Color(0xFFCFDEF3)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              left: 28,
              right: 28,
              top: 20,
              bottom: viewPadding.bottom + KeyboardFormInsets.scrollBottomExtra(context, extra: 24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.deepBlue),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Cadastro rápido',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w800, fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Nome completo e e-mail. Depois você pode completar seus dados no app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 20,
                        spreadRadius: 4,
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
                            _field('Nome completo', Icons.person_outline_rounded, _nameController,
                                autofillHints: const [AutofillHints.name], textInputAction: TextInputAction.next),
                            const SizedBox(height: 16),
                            _field('E-mail', Icons.email_outlined, _emailController,
                                autofillHints: const [AutofillHints.email], textInputAction: TextInputAction.next),
                            const SizedBox(height: 16),
                            _field('Senha (mín. 6 caracteres)', Icons.lock_outline_rounded, _passController,
                                isPass: true,
                                autofillHints: const [AutofillHints.newPassword],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  if (!_loading) _signUp();
                                }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // CRIAR CONTA: apenas createUserWithEmailAndPassword (AuthService.signUpSimple).
                      // NÃO usar signInWithPopup nem qualquer método de popup do Google aqui — evita erro popup-closed-by-user.
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                            shadowColor: AppColors.accent.withOpacity(0.4),
                          ),
                          child: Text(_loading ? 'Criando conta...' : 'CRIAR CONTA', style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loading ? null : () => Navigator.of(context).pop(),
                        child: const Text('Já tenho conta – Entrar', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
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
      textInputAction: textInputAction ?? (isPass ? TextInputAction.done : TextInputAction.next),
      onSubmitted: onFieldSubmitted,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 22),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(_obscurePass ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 22, color: AppColors.textMuted),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }
}
