import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/login_preferences.dart';
import '../services/push_notification_service.dart';
import '../services/version_check_service.dart';
import '../theme/app_colors.dart';

/// Tela exibida após cadastro manual — aguarda confirmação do e-mail (igual Controle Total).
/// Polling automático a cada 3s; ao detectar `emailVerified = true` navega para home.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  Timer? _pollTimer;
  bool _verified = false;
  bool _resending = false;
  bool _navigating = false;

  // Dados passados via arguments
  String _email = '';
  String _name = '';
  String? _pendingPromoId;
  String? _afterLoginRoute;
  bool _openMpCheckoutAfterPromoLoad = false;
  bool _fromLogin = false;
  String? _initialEmailSendError;
  bool _argsRead = false;

  static const _brandTeal = Color(0xFF2DD4BF);

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _scaleIn = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
          parent: _animCtrl,
          curve: const Interval(0.1, 0.7, curve: Curves.elasticOut)),
    );
    _animCtrl.forward();
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _email = (args['email'] as String?) ?? '';
      _name = (args['name'] as String?) ?? '';
      _pendingPromoId = args['promoId']?.toString().trim();
      _afterLoginRoute = args['afterLoginRoute']?.toString().trim();
      if (args['openMpCheckoutAfterPromoLoad'] == true) {
        _openMpCheckoutAfterPromoLoad = true;
      }
      _fromLogin = args['fromLogin'] == true;
      _initialEmailSendError = args['emailSendError']?.toString();
    }
    // Se veio do login (e-mail não verificado), verifica primeiro se já não
    // foi confirmado (Firebase pode ter atualizado o flag) e só então reenvia.
    if (_fromLogin && _email.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _checkVerified();
        if (mounted && !_verified) {
          await _resendEmail();
        }
      });
    }
    // Se o envio inicial falhou, mostra o erro após o primeiro frame.
    if (_initialEmailSendError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'E-mail não enviado: $_initialEmailSendError\nToque em REENVIAR para tentar novamente.'),
            backgroundColor: const Color(0xFFE53935),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkVerified());
  }

  Future<void> _checkVerified() async {
    if (_verified || _navigating || !mounted) return;
    try {
      final ok = await _auth.isEmailVerified();
      if (ok && mounted && !_navigating) {
        setState(() => _verified = true);
        _pollTimer?.cancel();
        _navigateToHome();
      }
    } catch (_) {
      // ignora erro de rede no polling
    }
  }

  void _navigateToHome() {
    if (_navigating) return;
    _navigating = true;
    PushNotificationService().inicializar().catchError((_) {});
    VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
    // Delay para exibir animação de sucesso
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final pid = _pendingPromoId;
      if (_afterLoginRoute == '/escolha-plano' &&
          pid != null &&
          pid.isNotEmpty) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/escolha-plano',
          (route) => false,
          arguments: {
            'promoId': pid,
            if (_openMpCheckoutAfterPromoLoad)
              'openMpCheckoutAfterPromoLoad': true,
          },
        );
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    });
  }

  Future<void> _resendEmail() async {
    if (_resending || _verified) return;
    // Evita reenvio se o e-mail já foi confirmado enquanto a tela estava aberta.
    await _checkVerified();
    if (!mounted || _verified) return;
    setState(() => _resending = true);
    try {
      await _auth.sendCustomVerificationEmail(email: _email, name: _name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'E-mail de confirmação reenviado! Verifique sua caixa.'),
          backgroundColor: const Color(0xFF0D9488),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } on FirebaseException catch (e) {
      // Se a Cloud Function indicar que o e-mail já está verificado ou o
      // usuário não existe mais, trata como sucesso e re-verifica o estado.
      final alreadyVerified = e.code == 'already-verified' ||
          (e.message?.toLowerCase().contains('already verified') ?? false) ||
          (e.message?.toLowerCase().contains('já verificado') ?? false);
      final userNotFound = e.code == 'not-found' ||
          (e.message?.toLowerCase().contains('user not found') ?? false);
      if (!mounted) return;
      if (alreadyVerified) {
        await _checkVerified();
      } else if (userNotFound) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Conta não encontrada. Volte ao login e tente novamente.'),
            backgroundColor: AppColors.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reenviar: ${e.message ?? e.code}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Erro ao reenviar: ${e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '')}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// «Voltar ao login»: encerra a sessão não verificada e volta à tela inicial
  /// com o e-mail salvo para preenchimento automático (app e web).
  Future<void> _backToLogin() async {
    if (_email.isNotEmpty) {
      await LoginPreferences.setLastLoginIdentifier(_email);
    }
    await LoginPreferences.setPreferEmailPassword(true);
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: mq.size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF030712), Color(0xFF0f172a), Color(0xFF134e4a)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: ScaleTransition(
              scale: _scaleIn,
              child: FadeTransition(
                opacity: _fadeIn,
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // Ícone animado
                    _verified ? _buildSuccessIcon() : _buildEmailIcon(),
                    const SizedBox(height: 32),
                    // Título
                    Text(
                      _verified ? 'E-mail confirmado!' : 'Confirme seu e-mail',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Subtítulo
                    Text(
                      _verified
                          ? 'Sua conta está ativa e pronta para uso.\nRedirecionando...'
                          : 'Enviamos um link de confirmação para:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    if (!_verified) ...[
                      const SizedBox(height: 12),
                      // E-mail destacado
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.email_rounded,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 20),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                _email,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Instruções
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            _instructionRow(Icons.inbox_rounded,
                                'Abra sua caixa de entrada'),
                            const SizedBox(height: 12),
                            _instructionRow(Icons.touch_app_rounded,
                                'Clique no botão "CONFIRMAR MEU E-MAIL"'),
                            const SizedBox(height: 12),
                            _instructionRow(Icons.check_circle_rounded,
                                'Volte aqui — atualizamos automaticamente'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Botão reenviar
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _resending ? null : _resendEmail,
                          icon: _resending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(
                            _resending ? 'Reenviando...' : 'REENVIAR E-MAIL',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Botão "Já confirmei"
                      TextButton(
                        onPressed: _checkVerified,
                        child: Text(
                          'Já confirmei meu e-mail',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Botão "Voltar ao login" — volta à tela inicial com o
                      // e-mail preenchido para digitar a senha após validação.
                      TextButton.icon(
                        onPressed: _backToLogin,
                        icon: Icon(Icons.arrow_back_rounded,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.7)),
                        label: Text(
                          'Voltar ao login',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user_rounded,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Seguro · Criptografado · Equipe Wisdom APP',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailIcon() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            _brandTeal.withValues(alpha: 0.25),
            Colors.white.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _brandTeal.withValues(alpha: 0.35), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.email_rounded, color: Colors.white, size: 52),
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessIcon() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
    );
  }

  Widget _instructionRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.3),
          ),
        ),
      ],
    );
  }
}
