import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_session_cache.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/ios_payments_gate.dart';
import '../services/login_preferences.dart';
import '../services/native_login_security_hooks.dart';
import '../services/push_notification_service.dart';
import '../services/session_restore_service.dart';
import '../services/version_check_service.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../widgets/oauth_login_buttons.dart';
import 'landing_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.switchAccount = false,
  });

  /// Após «Trocar conta» nas Configurações: novo login OAuth, sem sessão automática.
  final bool switchAccount;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  bool _loading = false;
  bool _biometricEnabled = false;
  bool _bioHardwareAvailable = false;

  /// Após login: ir a escolha de plano com promo (fluxo site divulgação).
  String? _pendingPromoId;
  String? _afterLoginRoute;

  /// Abre folha PIX/cartão assim que a promo carregar em [EscolhaPlanoPage].
  bool _openMpCheckoutAfterPromoLoad = false;
  bool _routeArgsRead = false;
  /// Após «Entrar com outra conta» nas Configurações: força picker Google e não preenche e-mail antigo.
  bool _switchAccountMode = false;
  bool _returningLoginOnDevice = false;

  @override
  void initState() {
    super.initState();
    _consumeWebLoginDeepLink();
    _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLoginScreenReady());
    if (!kIsWeb) {
      BiometricPreferences.isEnabled().then((v) {
        if (mounted) setState(() => _biometricEnabled = v);
      });
      isBiometricAvailable().then((v) {
        if (mounted) setState(() => _bioHardwareAvailable = v);
      });
    }
  }

  bool _isSwitchAccountFlow() {
    if (widget.switchAccount || _switchAccountMode) return true;
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is Map && args['switchAccount'] == true;
  }

  /// Reabertura: só restaura se o Firebase já tiver sessão no disco (igual Controle Total).
  /// Re-login com senha/Google silencioso fica no botão «Continuar com digital» — não automático.
  Future<void> _onLoginScreenReady() async {
    if (!mounted || kIsWeb) return;
    if (_isSwitchAccountFlow()) return;
    if (await LoginPreferences.isAccountSwitchPending()) return;

    final existingUser = FirebaseAuth.instance.currentUser;
    if (existingUser != null) {
      await _tryReturningUserAutoAccess();
      return;
    }

    final last = await LoginPreferences.getLastOAuthProvider();
    if (last == 'google') {
      await _tryExpressGoogleReconnect();
    }
  }

  Future<void> _tryReturningUserAutoAccess() async {
    if (!mounted || _loading) return;

    final existingUser = FirebaseAuth.instance.currentUser;
    if (existingUser == null) return;

    final bioEnabled = await BiometricPreferences.isEnabled();
    final bioHardware = await isBiometricHardwareAvailable();
    if (bioEnabled && bioHardware) {
      await _continueWithSavedSessionBiometric();
    } else if (mounted) {
      _goToRootAfterAuth();
    }
  }

  /// Digital/rosto + credenciais guardadas ou Google silencioso (ação explícita do usuário).
  Future<void> _unlockWithBiometricAndStoredCredentials() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final ok = await authenticateWithBiometric();
      if (!mounted) return;
      if (!ok) return;

      if (FirebaseAuth.instance.currentUser != null) {
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        _goToRootAfterAuth();
        return;
      }

      final cred = await _auth.signInWithGoogleSilently();
      if (!mounted) return;
      if (cred != null) {
        final signedEmail =
            FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
        if (signedEmail.isNotEmpty) {
          await LoginPreferences.setLastLoginIdentifier(signedEmail);
        }
        await LoginPreferences.setLastOAuthProvider('google');
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        _goToRootAfterAuth();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Não foi possível restaurar o acesso: ${AuthService.friendlyGoogleSignInError(e)}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      // Mantém tela de login para escolha manual.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeArgsRead) return;
    _routeArgsRead = true;
    final routeName = ModalRoute.of(context)?.settings.name;
    if (routeName == '/admin') {
      _afterLoginRoute = '/admin';
    }
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['switchAccount'] == true) {
      _switchAccountMode = true;
    }
    if (args is Map) {
      final p = args['promoId']?.toString().trim();
      if (p != null && p.isNotEmpty) _pendingPromoId = p;
      final r = args['afterLoginRoute']?.toString().trim();
      if (r != null && r.isNotEmpty) _afterLoginRoute = r;
      if (args['openMpCheckoutAfterPromoLoad'] == true) {
        _openMpCheckoutAfterPromoLoad = true;
      }
    } else if (args is String && args.startsWith('/')) {
      _afterLoginRoute = args;
    }
  }

  /// Web: `/#/login?after=…` ou `/#/admin` — destino após autenticação.
  void _consumeWebLoginDeepLink() {
    if (!kIsWeb) return;
    final frag = Uri.base.fragment.trim();
    final pathOnly = frag.isNotEmpty
        ? (frag.startsWith('/') ? frag : '/$frag').split('?').first
        : Uri.base.path;
    if (pathOnly == '/admin' || pathOnly.endsWith('/admin')) {
      _afterLoginRoute = '/admin';
      return;
    }
    Map<String, String> qp = {};
    if (frag.isNotEmpty) {
      var pathAndQuery = frag.startsWith('/') ? frag : '/$frag';
      if (!pathAndQuery.contains('?')) {
        if (pathAndQuery.startsWith('/login')) {
          pathAndQuery = '$pathAndQuery?';
        } else {
          return;
        }
      }
      final qIdx = pathAndQuery.indexOf('?');
      final path = pathAndQuery.substring(0, qIdx);
      if (path != '/login' && !path.endsWith('/login')) return;
      final query = pathAndQuery.substring(qIdx + 1);
      qp = Uri.splitQueryString(query);
    } else if (Uri.base.path.contains('login')) {
      qp = Uri.base.queryParameters;
    } else {
      return;
    }
    final after = (qp['after'] ?? '').trim();
    if (after.isEmpty) return;
    final afterPath = after.split('?').first;
    if (afterPath == '/admin') {
      _afterLoginRoute = '/admin';
      return;
    }
    if (afterPath != '/escolha-plano') return;
    _afterLoginRoute = '/escolha-plano';
  }

  Future<void> _loadPreferences() async {
    final accountSwitchPending =
        await LoginPreferences.consumeAccountSwitchPending();
    if (!mounted) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    final switchFromRoute = widget.switchAccount ||
        (args is Map && args['switchAccount'] == true);
    final switchAccount = accountSwitchPending || switchFromRoute;
    if (switchAccount) {
      await LoginPreferences.setPreferEmailPassword(false);
    }
    final returning = await LoginPreferences.hasReturningLoginOnDevice();
    if (!mounted) return;
    setState(() {
      _returningLoginOnDevice = returning && !switchAccount;
      _switchAccountMode = switchAccount;
    });
  }

  /// Sessão Firebase já persistida no aparelho — só confirma digital/rosto (funciona sem internet).
  Future<void> _continueWithSavedSessionBiometric() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final ok = await authenticateWithBiometric();
      if (!mounted) return;
      if (ok) {
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        _goToRootAfterAuth();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _sessionUnlockBanner(bool nativePremium) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _loading
            ? null
            : () {
                if (FirebaseAuth.instance.currentUser != null) {
                  _continueWithSavedSessionBiometric();
                } else {
                  _unlockWithBiometricAndStoredCredentials();
                }
              },
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: nativePremium
                  ? const [Color(0xFF134e4a), Color(0xFF0f766e)]
                  : const [Color(0xFF1A237E), Color(0xFF0D9488)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.fingerprint_rounded,
                  color: Colors.white.withValues(alpha: 0.96), size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continuar com digital / rosto',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.97),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sessão guardada neste aparelho — também sem internet.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }

  /// Volta ao [AuthWrapper] em `/`. Não usar só `popUntil(isFirst)`: se a pilha for só `/login`
  /// (ex.: `pushNamedAndRemoveUntil('/login')` da licença expirada ou da biometria), o primeiro
  /// route já é o login e nada é desempilhado — o utilizador fica preso com sessão já aberta (2.1).
  void _goToRootAfterAuth() {
    LoginPreferences.markSuccessfulLogin();
    SessionRestoreService.resetAttemptFlag();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      AppSessionCache.markShellReady(uid).catchError((_) {});
      final dn = FirebaseAuth.instance.currentUser?.displayName?.trim();
      if (dn != null && dn.isNotEmpty) {
        LoginPreferences.setLastDisplayName(dn).catchError((_) {});
      }
    }
    if (!mounted) return;
    if (_afterLoginRoute == '/escolha-plano') {
      if (IosPaymentsGate.shouldHidePayments && IosPaymentsGate.isIosNative) {
        IosPaymentsGate.openReaderPlansInSafari(source: 'login_after_auth');
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }
      final m = <String, dynamic>{};
      final p = _pendingPromoId;
      if (p != null && p.isNotEmpty) m['promoId'] = p;
      if (_openMpCheckoutAfterPromoLoad) {
        m['openMpCheckoutAfterPromoLoad'] = true;
      }
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/escolha-plano',
        (route) => false,
        arguments: m.isEmpty ? null : m,
      );
      return;
    }
    if (_afterLoginRoute == '/admin') {
      Navigator.of(context).pushNamedAndRemoveUntil('/admin', (route) => false);
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Se o último login foi Google no aparelho, tenta reconectar sem abrir o picker (rápido).
  Future<void> _tryExpressGoogleReconnect() async {
    if (kIsWeb) return;
    if (_isSwitchAccountFlow()) return;
    final last = await LoginPreferences.getLastOAuthProvider();
    if (last != 'google') return;
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final cred = await _auth.signInWithGoogleSilently();
      if (!mounted) return;
      if (cred != null) {
        final signedEmail =
            FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
        if (signedEmail.isNotEmpty) {
          await LoginPreferences.setLastLoginIdentifier(signedEmail);
        }
        if (!kIsWeb) unawaited(enableBiometricAfterSuccessfulNativeLogin());
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        _goToRootAfterAuth();
      }
    } catch (_) {
      // Mantém a tela de login — usuário escolhe Google ou outro método.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);
    try {
      final forcePicker = _isSwitchAccountFlow();
      if (!forcePicker) {
        final silentCred = await _auth.signInWithGoogleSilently();
        if (silentCred != null) {
          final signedEmail =
              FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
          if (signedEmail.isNotEmpty) {
            await LoginPreferences.setLastLoginIdentifier(signedEmail);
          }
          await LoginPreferences.setLastOAuthProvider('google');
          if (!kIsWeb) unawaited(enableBiometricAfterSuccessfulNativeLogin());
          PushNotificationService().salvarTokenNoBanco().catchError((_) {});
          VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
          _goToRootAfterAuth();
          return;
        }
      }
      final cred = await _auth.signInWithGoogle(
        forceAccountPicker: forcePicker,
      );
      if (!mounted) return;
      if (cred != null) {
        final signedEmail =
            FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
        if (signedEmail.isNotEmpty) {
          await LoginPreferences.setLastLoginIdentifier(signedEmail);
        }
        await LoginPreferences.setLastOAuthProvider('google');
        if (!kIsWeb) unawaited(enableBiometricAfterSuccessfulNativeLogin());
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        _goToRootAfterAuth();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Erro ao entrar com Google: ${AuthService.friendlyGoogleSignInError(e)}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithApple() async {
    setState(() => _loading = true);
    try {
      final cred = await _auth.signInWithApple();
      if (!mounted) return;
      if (cred != null) {
        final signedEmail =
            FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
        if (signedEmail.isNotEmpty) {
          await LoginPreferences.setLastLoginIdentifier(signedEmail);
        }
        await LoginPreferences.setLastOAuthProvider('apple');
        if (!kIsWeb) unawaited(enableBiometricAfterSuccessfulNativeLogin());
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        _goToRootAfterAuth();
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

  /// Fundo sólido (Android: evita tela branca se gradiente não pintar).
  static const Color _scaffoldBg = Color(0xFFE0EAFC);

  @override
  Widget build(BuildContext context) {
    // iOS/Android: só login expresso na landing (Google / Apple).
    if (!kIsWeb) {
      return const LandingScreen();
    }
    // APK/AAB, IPA e demais builds nativos: mesmo visual premium da landing; PWA/web mantém tema claro.
    final nativePremium = !kIsWeb;
    // Android 15+: Window#setStatusBarColor / setNavigationBarColor estão descontinuadas — não enviar cores de barra;
    // ícones claros + edge-to-edge (main.dart) + gradiente/SafeArea cobrem o visual.
    final isAndroidNative =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: nativePremium
          ? (isAndroidNative
              ? const SystemUiOverlayStyle(
                  statusBarIconBrightness: Brightness.light,
                  statusBarBrightness: Brightness.dark,
                  systemNavigationBarIconBrightness: Brightness.light,
                  systemNavigationBarContrastEnforced: false,
                  systemStatusBarContrastEnforced: false,
                )
              : const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  statusBarBrightness: Brightness.dark,
                  systemNavigationBarColor: Color(0xFF0f172a),
                  systemNavigationBarIconBrightness: Brightness.light,
                ))
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
      child: Scaffold(
        resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
        backgroundColor: nativePremium ? const Color(0xFF030712) : _scaffoldBg,
        body: keyboardScaffoldBody(
          Container(
          width: double.infinity,
          height: double.infinity,
          color: nativePremium ? const Color(0xFF030712) : _scaffoldBg,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: nativePremium
                    ? const [
                        Color(0xFF030712),
                        Color(0xFF0f172a),
                        Color(0xFF134e4a),
                      ]
                    : const [Color(0xFFE0EAFC), Color(0xFFCFDEF3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              top: true,
              bottom: true,
              left: true,
              right: true,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    30, 0, 30, MediaQuery.paddingOf(context).bottom + 16),
                child: Column(
                  children: [
                    const SizedBox(height: 48),
                    Hero(
                      tag: 'logo',
                      child: Container(
                        decoration: nativePremium
                            ? BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2DD4BF)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              )
                            : null,
                        child: Image.asset(
                          'assets/images/logo_simples_controletotalapp.png',
                          height: nativePremium ? 108 : 100,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 80,
                            color: nativePremium
                                ? const Color(0xFF2DD4BF)
                                : const Color(0xFF1A237E),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      "Bem-vindo ao\nWISDOMAPP",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: nativePremium ? 30 : 28,
                        fontWeight: FontWeight.w800,
                        color: nativePremium
                            ? Colors.white
                            : const Color(0xFF1A237E),
                        letterSpacing: nativePremium ? 0.5 : 1.2,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Sua gestão financeira e de escalas de forma simples e profissional.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: nativePremium
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF37474F),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: nativePremium ? 44 : 60),
                    if (!kIsWeb &&
                        !_switchAccountMode &&
                        _returningLoginOnDevice &&
                        _biometricEnabled &&
                        _bioHardwareAvailable) ...[
                      _sessionUnlockBanner(nativePremium),
                      SizedBox(height: nativePremium ? 16 : 20),
                    ],
                    // Card de login: iOS = premium escuro; demais = glass clássico
                    Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        color: nativePremium
                            ? const Color(0xFF0f172a).withValues(alpha: 0.92)
                            : Colors.white.withValues(alpha: 0.8),
                        borderRadius:
                            BorderRadius.circular(nativePremium ? 28 : 30),
                        border: nativePremium
                            ? Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                                width: 1)
                            : null,
                        boxShadow: [
                          if (nativePremium)
                            BoxShadow(
                              color: const Color(0xFF2DD4BF)
                                  .withValues(alpha: 0.12),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            )
                          else
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            "Acesse sua conta",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: nativePremium
                                  ? Colors.white
                                  : const Color(0xFF1A237E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AuthService.isSignInWithAppleAvailable
                                ? 'Entre com Google ou Apple para acessar sua conta.'
                                : 'Entre com Google para acessar sua conta.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: nativePremium
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF546E7A),
                            ),
                          ),
                          const SizedBox(height: 20),
                          OAuthLoginButtons(
                            loading: _loading,
                            onGoogle: _loginWithGoogle,
                            onApple: AuthService.isSignInWithAppleAvailable
                                ? _loginWithApple
                                : null,
                            googleForeground: nativePremium ? Colors.white : null,
                            googleBackground: nativePremium
                                ? const Color(0xFF1e293b)
                                : Colors.white,
                            googleBorderColor: nativePremium
                                ? Colors.white.withValues(alpha: 0.35)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () {
                        final m = <String, dynamic>{};
                        final pid = _pendingPromoId;
                        if (pid != null && pid.isNotEmpty) {
                          m['promoId'] = pid;
                          m['afterLoginRoute'] = '/escolha-plano';
                          if (_openMpCheckoutAfterPromoLoad) {
                            m['openMpCheckoutAfterPromoLoad'] = true;
                          }
                        }
                        Navigator.pushNamed(
                          context,
                          '/signup',
                          arguments: m.isEmpty ? null : m,
                        );
                      },
                      style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          tapTargetSize: MaterialTapTargetSize.padded),
                      child: Text(
                        "Cadastro rápido (nome + e-mail)",
                        style: TextStyle(
                          color: nativePremium
                              ? const Color(0xFF2DD4BF)
                              : const Color(0xFF2962FF),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: nativePremium
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: nativePremium
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.12))
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.fingerprint_rounded,
                                    size: 20,
                                    color: nativePremium
                                        ? const Color(0xFF94A3B8)
                                        : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'Acesso por digital/facial no próximo login',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: nativePremium
                                            ? const Color(0xFFE2E8F0)
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _biometricEnabled,
                              onChanged: (v) async {
                                await BiometricPreferences.setEnabled(v);
                                if (mounted) {
                                  setState(() => _biometricEnabled = v);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    Text(
                      "Ao entrar, você concorda com nossos\nTermos de Uso e Privacidade.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: nativePremium
                            ? const Color(0xFF64748B)
                            : const Color(0xFF455A64),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
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
