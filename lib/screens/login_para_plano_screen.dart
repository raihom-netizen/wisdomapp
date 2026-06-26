import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/ios_payments_gate.dart';
import '../services/login_preferences.dart';
import '../services/push_notification_service.dart';
import '../services/version_check_service.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/navigator_safe_pop.dart';
import '../widgets/oauth_login_buttons.dart';

/// Tela exibida quando o usuário tenta acessar plano/checkout sem estar logado.
class LoginParaPlanoScreen extends StatefulWidget {
  const LoginParaPlanoScreen({super.key, this.pendingPromoId});

  final String? pendingPromoId;

  @override
  State<LoginParaPlanoScreen> createState() => _LoginParaPlanoScreenState();
}

class _LoginParaPlanoScreenState extends State<LoginParaPlanoScreen> {
  final _auth = AuthService();
  bool _loading = false;

  Map<String, dynamic> _escolhaPlanoArgs() {
    final m = <String, dynamic>{};
    final p = widget.pendingPromoId?.trim();
    if (p != null && p.isNotEmpty) m['promoId'] = p;
    return m;
  }

  Future<void> _persistOAuthHints(String provider) async {
    final e = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    if (e.isNotEmpty) await LoginPreferences.setLastLoginIdentifier(e);
    await LoginPreferences.setLastOAuthProvider(provider);
    await LoginPreferences.markSuccessfulLogin();
  }

  Future<void> _goAfterLogin() async {
    PushNotificationService().salvarTokenNoBanco().catchError((_) {});
    VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
    if (!mounted) return;
    if (IosPaymentsGate.shouldHidePayments && IosPaymentsGate.isIosNative) {
      await IosPaymentsGate.openReaderPlansInSafari(source: 'login_para_plano');
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/escolha-plano',
      (route) => false,
      arguments: _escolhaPlanoArgs().isEmpty ? null : _escolhaPlanoArgs(),
    );
  }

  Future<void> _loginWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final cred = await _auth.signInWithGoogle();
      if (!mounted) return;
      if (cred != null) {
        await _persistOAuthHints('google');
        await _goAfterLogin();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao entrar com Google: ${AuthService.friendlyGoogleSignInError(e)}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithApple() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final cred = await _auth.signInWithApple();
      if (!mounted) return;
      if (cred != null) {
        await _persistOAuthHints('apple');
        await _goAfterLogin();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao entrar com a Apple: ${AuthService.friendlyAppleSignInError(e)}',
          ),
          duration: const Duration(seconds: 5),
        ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minH = (constraints.maxHeight > 0
                        ? constraints.maxHeight
                        : 500.0) -
                    viewPadding.vertical;
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 28,
                    right: 28,
                    top: 24,
                    bottom: viewPadding.bottom +
                        KeyboardFormInsets.scrollBottomExtra(context, extra: 24),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minH.clamp(400.0, 1e4)),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF4F46E5), Color(0xFF2962FF)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2962FF)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 26,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.lock_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'Login obrigatório',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF2962FF).withValues(alpha: 0.12),
                              ),
                            ),
                            child: const Text(
                              'Para assinar um plano, entre com Google'
                              ' (Android e web) ou com Google/Apple no iPhone. '
                              'Depois você escolhe o plano e paga com PIX ou cartão.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          OAuthLoginButtons(
                            loading: _loading,
                            onGoogle: _loginWithGoogle,
                            onApple: AuthService.isSignInWithAppleAvailable
                                ? _loginWithApple
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => popOrGoHome(context),
                            child: const Text(
                              'Voltar',
                              style: TextStyle(
                                color: Color(0xFF2962FF),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
