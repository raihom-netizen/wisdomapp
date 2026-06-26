import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_verse.dart';
import '../utils/url_launcher_helper.dart';
import '../utils/pwa_install_helper.dart';
import '../services/auth_service.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import '../services/version_check_service.dart';
import '../models/landing_public_content.dart';
import '../models/user_profile.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../services/ios_payments_gate.dart';
import '../services/login_preferences.dart';
import '../services/push_notification_service.dart';
import '../widgets/divulgacao_public_promo_card.dart';
import '../widgets/oauth_login_buttons.dart';
import '../widgets/official_social_top_buttons.dart';
import '../widgets/wisdomapp_hero_brand.dart';
import '../utils/keyboard_form_scaffold.dart';

/// Página de divulgação do WISDOMAPP (hero, módulos, planos e rodapé).
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _loginLoading = false;
  final _auth = AuthService();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _landingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mpCheckoutSub;
  Map<String, dynamic>? _landingMainData;
  Map<String, dynamic>? _mpCheckoutData;
  LandingPublicContent _landing = LandingPublicContent.fromMap(null);

  /// Site aberto pelo app iOS (Gerenciamento de licença) ou PWA Safari — query [from_app]=1 & [source].
  bool _webFromIosAppLicense = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      final q = Uri.base.queryParameters;
      if (q['from_app'] == '1' &&
          (q['source'] == 'ios_native' || q['source'] == 'pwa_safari')) {
        _webFromIosAppLicense = true;
      }
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _animController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        if (FirebaseAuth.instance.currentUser != null) return;
        _bindPublicFirestoreListeners();
      });
    });
    if (!kIsWeb) {
      _tryInstantSessionRedirect();
    }
  }

  /// Sessão no disco → painel na hora (sem passar pela landing).
  void _tryInstantSessionRedirect() {
    if (LoginPreferences.startupAccountSwitchPending == true) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    });
  }

  /// Sessão Firebase no aparelho → painel (biometria no [BiometricGateScreen]), sem passar por «Entrar».
  /// Após «Sair» / «Entrar com outra conta», fica na landing para login expresso manual.
  Future<void> _redirectIfSessionPersisted() async {
    if (await LoginPreferences.isAccountSwitchPending()) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  /// Quem veio do app iOS: após login vai direto a [escolha-plano] para renovar ou adquirir (mensal/anual).
  Future<void> _persistOAuthHints(String provider) async {
    final u = FirebaseAuth.instance.currentUser;
    final e = u?.email?.trim() ?? '';
    if (e.isNotEmpty) await LoginPreferences.setLastLoginIdentifier(e);
    await LoginPreferences.setLastOAuthProvider(provider);
    await LoginPreferences.markSuccessfulLogin();
  }

  Future<void> _finishExpressLogin(String provider) async {
    await _persistOAuthHints(provider);
    PushNotificationService().salvarTokenNoBanco().catchError((_) {});
    VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
    if (!mounted) return;
    if (_webFromIosAppLicense) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/escolha-plano', (route) => false);
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Future<void> _openExpressLoginFromFaixa() async {
    if (_loginLoading) return;
    if (kIsWeb) _pausePublicFirestoreListeners();
    setState(() => _loginLoading = true);
    try {
      if (_auth.currentUser != null) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }

      final forcePicker = await LoginPreferences.isAccountSwitchPending();

      if (!forcePicker) {
        final silentCred = await _auth.signInWithGoogleSilently();
        if (silentCred != null) {
          await _finishExpressLogin('google');
          return;
        }
      }

      if (!kIsWeb && AuthService.isSignInWithAppleAvailable) {
        final appleCred = await _auth.signInWithApple();
        if (appleCred != null) {
          if (forcePicker) await LoginPreferences.consumeAccountSwitchPending();
          await _finishExpressLogin('apple');
          return;
        }
      }

      final googleCred = await _auth.signInWithGoogle(
        forceAccountPicker: forcePicker,
      );
      if (googleCred != null) {
        if (forcePicker) await LoginPreferences.consumeAccountSwitchPending();
        await _finishExpressLogin('google');
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login expresso cancelado ou indisponível no momento.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível concluir o login expresso.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loginLoading = false);
        _resumePublicFirestoreListenersIfNeeded();
      }
    }
  }

  Widget _buildFaixaSuspensaLoginExpresso(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF061428), Color(0xFF0A1F56), Color(0xFF132D6B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _lpGold.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(color: _lpGold.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _openExpressLoginFromFaixa,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.flash_on_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Login expresso',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Clique aqui para entrar com Google ou Apple',
                            style: TextStyle(
                              color: _lpGoldLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: _openExpressLoginFromFaixa,
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text('Entrar'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 40),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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

  void _bindPublicFirestoreListeners() {
    void mergeLanding() {
      if (!mounted) return;
      final base = LandingPublicContent.fromMap(_landingMainData);
      final snap = MpCheckoutPricingSnapshot.fromFirestore(_mpCheckoutData);
      setState(() => _landing = base.applyPremiumTextsFromCheckoutPricing(snap));
    }

    _landingSub?.cancel();
    _mpCheckoutSub?.cancel();
    _landingSub = FirebaseFirestore.instance
        .collection('landing_content')
        .doc('main')
        .snapshots()
        .listen((doc) {
      _landingMainData = doc.data();
      mergeLanding();
    });
    _mpCheckoutSub = FirebaseFirestore.instance
        .collection('app_config')
        .doc('mp_checkout_prices')
        .snapshots()
        .listen((doc) {
      _mpCheckoutData = doc.data();
      mergeLanding();
    });
  }

  /// Web: pausa listeners enquanto login Google ou tela /login está aberta (evita assert Firestore).
  void _pausePublicFirestoreListeners() {
    _landingSub?.cancel();
    _landingSub = null;
    _mpCheckoutSub?.cancel();
    _mpCheckoutSub = null;
  }

  void _resumePublicFirestoreListenersIfNeeded() {
    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser != null) return;
    if (_landingSub != null || _mpCheckoutSub != null) return;
    _bindPublicFirestoreListeners();
  }

  @override
  void dispose() {
    _pausePublicFirestoreListeners();
    _animController.dispose();
    super.dispose();
  }

  /// Botão Google Play só na web fora do Safari iPhone/iPad e no Android; no iOS (Safari ou app) só TestFlight.
  bool get _showApkDownloadOnLanding {
    if (kIsWeb) return !isPwaIos;
    return defaultTargetPlatform != TargetPlatform.iOS;
  }

  /// App **Android** instalado: na secção «Baixar o app» mostra só a loja Google Play (sem TestFlight/iPhone).
  bool get _hideIosDownloadOnNativeAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _launch(Uri url) async {
    final scheme = url.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      try {
        await openUrlPreferChrome(url.toString());
      } catch (_) {}
      return;
    }
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _loginWithGoogle() async {
    if (_loginLoading) return;
    if (kIsWeb) _pausePublicFirestoreListeners();
    setState(() => _loginLoading = true);
    try {
      final forcePicker = await LoginPreferences.isAccountSwitchPending();
      final cred = await _auth.signInWithGoogle(forceAccountPicker: forcePicker);
      if (!mounted) return;
      if (cred != null) {
        if (forcePicker) await LoginPreferences.consumeAccountSwitchPending();
        await _finishExpressLogin('google');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao entrar com Google: ${AuthService.friendlyGoogleSignInError(e)}'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loginLoading = false);
        _resumePublicFirestoreListenersIfNeeded();
      }
    }
  }

  Future<void> _loginWithApple() async {
    if (_loginLoading) return;
    setState(() => _loginLoading = true);
    try {
      final forcePicker = await LoginPreferences.isAccountSwitchPending();
      final cred = await _auth.signInWithApple();
      if (!mounted) return;
      if (cred != null) {
        if (forcePicker) await LoginPreferences.consumeAccountSwitchPending();
        await _finishExpressLogin('apple');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao entrar com a Apple: ${AuthService.friendlyAppleSignInError(e)}',
          ),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  /// Cor de fundo garantida (Android: evita tela branca se tema atrasar).
  static const Color _scaffoldBg = Color(0xFFF4F6FB);

  /// Paleta WISDOMAPP — azul marinho e dourado (identidade da marca).
  static const Color _lpNavy = Color(0xFF0A1F56);
  static const Color _lpNavyDark = Color(0xFF061428);
  static const Color _lpNavyMid = Color(0xFF132D6B);
  static const Color _lpGold = Color(0xFFD4AF37);
  static const Color _lpGoldLight = Color(0xFFF0D878);
  static const Color _lpDeep = _lpNavy;
  static const Color _lpSlate = Color(0xFF1E293B);
  static const Color _lpViolet = Color(0xFF6366F1);
  static const Color _lpCyan = Color(0xFF22D3EE);
  static const Color _lpRose = Color(0xFFF43F5E);

  static const String _versionJsonUrl = 'https://wisdomapp-b9e98.web.app/version.json';
  /// Link público TestFlight (beta no iPhone sem publicar na App Store). Sobrescrito por version.json / Firestore.
  static const String _defaultTestFlightPublicLink = 'https://testflight.apple.com/join/pugVHQ6C';

  String? _resolvePlayStoreUrl(String? fallback) {
    final fromLanding = _landing.divPlayStoreUrl.trim();
    if (fromLanding.isNotEmpty &&
        (fromLanding.startsWith('http://') || fromLanding.startsWith('https://'))) {
      return fromLanding;
    }
    return fallback;
  }

  /// Fallback imediato na landing — rede atualiza depois sem spinner.
  static ({String? apkUrl, String? iosUrl, String? testFlightUrl, String? version})
      get _downloadUrlsFallback => (
            apkUrl: kDefaultPlayStoreUrl,
            iosUrl: null,
            testFlightUrl: _defaultTestFlightPublicLink,
            version: null,
          );

  /// Busca link Android (loja) / testFlight do version.json e do Firestore.
  static Future<({String? apkUrl, String? iosUrl, String? testFlightUrl, String? version})> _fetchDownloadUrls() async {
    String? apkUrl = kDefaultPlayStoreUrl;
    String? iosUrl;
    String? testFlightUrl = _defaultTestFlightPublicLink;
    String? version;
    try {
      final uri = Uri.parse('$_versionJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final apk = decoded['apkDownloadUrl']?.toString().trim();
          final tf = decoded['testFlightUrl']?.toString().trim();
          final v = decoded['version']?.toString().trim();
          if (apk != null && apk.isNotEmpty && (apk.startsWith('http://') || apk.startsWith('https://'))) {
            final lower = apk.toLowerCase();
            apkUrl = (lower.endsWith('.apk') || lower.contains('/apk/'))
                ? kDefaultPlayStoreUrl
                : apk;
          }
          if (tf != null && tf.isNotEmpty && (tf.startsWith('http://') || tf.startsWith('https://'))) testFlightUrl = tf;
          if (v != null && v.isNotEmpty) version = v;
        }
      }
    } catch (_) {}
    try {
      final snap = await FirebaseFirestore.instance.collection('app_config').doc('version').get().timeout(const Duration(seconds: 3));
      final data = snap.data();
      if (data != null) {
        final apk = data['apkDownloadUrl']?.toString().trim();
        if (apk != null &&
            apk.isNotEmpty &&
            (apk.startsWith('http://') || apk.startsWith('https://'))) {
          final lower = apk.toLowerCase();
          apkUrl = (lower.endsWith('.apk') || lower.contains('/apk/'))
              ? kDefaultPlayStoreUrl
              : apk;
        }
        final tf = data['testFlightUrl']?.toString().trim();
        if (tf != null && tf.isNotEmpty && (tf.startsWith('http://') || tf.startsWith('https://'))) testFlightUrl = tf;
        if (version == null && data['version'] != null) version = data['version']?.toString().trim();
      }
    } catch (_) {}
    return (apkUrl: apkUrl, iosUrl: iosUrl, testFlightUrl: testFlightUrl, version: version);
  }

  /// Seção no início do site: Baixar o app (Google Play / iOS). Links vêm do version.json e atualizam ao subir nova versão.
  /// Dica para iPhone: abrir no Safari e "Adicionar à Tela de Início" (melhor toque e experiência).
  Widget _buildIosSafariHint(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        MediaQuery.of(context).padding.left + 16,
        12 + MediaQuery.of(context).padding.top,
        MediaQuery.of(context).padding.right + 16,
        8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2962FF).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 22, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Melhor no iPhone: abra no Safari e toque em Compartilhar → "Adicionar à Tela de Início".',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadAppSection(BuildContext context) {
    return FutureBuilder<({String? apkUrl, String? iosUrl, String? testFlightUrl, String? version})>(
      initialData: _downloadUrlsFallback,
      future: _fetchDownloadUrls(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? _downloadUrlsFallback;
        final apkUrl = _resolvePlayStoreUrl(data.apkUrl);
        final playLabel = _landing.divPlayStoreLabel.trim().isNotEmpty
            ? _landing.divPlayStoreLabel.trim()
            : 'Google Play';
        final testFlightUrl = data.testFlightUrl;
        final version = data.version;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            20 + MediaQuery.of(context).padding.left,
            16 + MediaQuery.of(context).padding.top,
            20 + MediaQuery.of(context).padding.right,
            16,
          ),
          decoration: BoxDecoration(
            color: _lpNavy.withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            children: [
              Text(
                'Baixar o app',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.72),
                  letterSpacing: 0.4,
                ),
              ),
              if (version != null && version.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Versão $version',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: [
                    if (_showApkDownloadOnLanding && apkUrl != null)
                      OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await openUrlPreferChrome(apkUrl);
                            } catch (_) {}
                          },
                          icon: Icon(Icons.shop_rounded, size: 16, color: Colors.white.withValues(alpha: 0.85)),
                          label: Text(
                            playLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white.withValues(alpha: 0.9),
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: const Size(0, 38),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                    if (!_hideIosDownloadOnNativeAndroid)
                    Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final tf = testFlightUrl;
                                final url = (tf != null && tf.isNotEmpty) ? tf : _defaultTestFlightPublicLink;
                                await openUrlPreferChrome(url);
                              } catch (_) {}
                            },
                            icon: Icon(
                              _showApkDownloadOnLanding ? Icons.apple_rounded : Icons.download_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                            label: Text(
                              _showApkDownloadOnLanding ? 'iPhone (TestFlight)' : 'Baixar',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.9),
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              minimumSize: const Size(0, 38),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          if (_showApkDownloadOnLanding)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'TestFlight na App Store, depois abra este link.',
                                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55)),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Instale o TestFlight e abra o link da beta.',
                                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                ],
              ),
              const SizedBox(height: 14),
              OfficialSocialTopButtons.fromLanding(_landing),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: _scaffoldBg,
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(),
      body: keyboardScaffoldBody(
        Stack(
        children: [
          SafeArea(
            top: true,
            bottom: true,
            left: true,
            right: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight > 0 ? constraints.maxHeight : 700.0;
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(bottom: padding.bottom + 104),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: h),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    if (kIsWeb && isPwaIos && !isPwaStandalone) _buildIosSafariHint(context),
                    _buildDownloadAppSection(context),
                    if (kIsWeb)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: DivulgacaoPublicPromoCard(),
                      ),
                    _buildHeroSection(context),
                    _buildFeaturesSection(),
                    _buildInspirationalQuote(),
                    _buildPricingSection(context),
                    _buildFooter(context),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFaixaSuspensaLoginExpresso(context),
          ),
        ],
      ),
      ),
    );
  }

  // --- Header / Hero Section ---
  Widget _buildHeroSection(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF061428),
            Color(0xFF0A1F56),
            Color(0xFF132D6B),
            Color(0xFFF4F6FB),
          ],
          stops: [0.0, 0.35, 0.72, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20 + MediaQuery.of(context).padding.left,
        12 + MediaQuery.of(context).padding.top,
        20 + MediaQuery.of(context).padding.right,
        44,
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, _) {
              final h = MediaQuery.sizeOf(context).height;
              return WisdomappHeroBrand(
                showMicroTagline: true,
                showIdealizer: true,
                compact: h < 760,
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            _landing.heroSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              height: 1.4,
              color: _lpGoldLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _landing.heroTealLine,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.92)),
          ),
          const SizedBox(height: 6),
          Text(
            _landing.heroSlateLine,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.78)),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => unawaited(_loginWithGoogle()),
            icon: Icon(Icons.rocket_launch_rounded, color: _lpGoldLight.withValues(alpha: 0.95), size: 18),
            label: Text(
              'Começar ${UserProfile.newUserTrialDays} dias grátis',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.94),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              side: BorderSide(color: _lpGold.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: [_lpViolet, _lpCyan, _lpGold],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: _lpViolet.withValues(alpha: 0.2), blurRadius: 32, offset: const Offset(0, 14)),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                children: [
                  if (isPwaStandalone) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: _lpViolet.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _lpViolet.withValues(alpha: 0.28)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'App instalado: seu login será mantido ao fechar e abrir.',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: _lpGold,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _webFromIosAppLicense
                              ? 'Renove ou adquira sua licença'
                              : 'Gerencie sua Licença',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _lpDeep, letterSpacing: -0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _webFromIosAppLicense
                        ? 'Você abriu o site pelo app iPhone/iPad. Entre com Google ou Apple. Depois escolha mensal ou anual — PIX ou cartão.'
                        : 'Entre com Google (Android e web) ou com Google/Apple no iPhone. Depois do login você compra ou renova a licença — PIX ou cartão.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 18),
                  OAuthLoginButtons(
                    loading: _loginLoading,
                    onGoogle: _loginWithGoogle,
                    onApple: AuthService.isSignInWithAppleAvailable
                        ? _loginWithApple
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                      children: [
                        TextSpan(
                          text: 'Teste grátis por ${UserProfile.newUserTrialDays} dias – acesso livre total pelo celular, computador ou notebook. Use no app ou no navegador em ',
                        ),
                        TextSpan(
                          text: 'wisdomapp-b9e98.web.app',
                          style: TextStyle(
                            color: _lpGold,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () async {
                              try {
                                await openUrlPreferChrome('https://wisdomapp-b9e98.web.app/');
                              } catch (_) {}
                            },
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspirationalQuote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [_lpNavy.withValues(alpha: 0.06), _lpGold.withValues(alpha: 0.08)],
          ),
          border: Border.all(color: _lpGold.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              '"O homem que consegue organizar sua vida financeira, conseguirá organizar todas as áreas da sua vida."',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                fontStyle: FontStyle.italic,
                color: _lpNavy.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '— Billy Graham',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _lpGold),
            ),
          ],
        ),
      ),
    );
  }

  // --- Módulos / Features (todas as funções do app) ---
  Widget _buildFeaturesSection() {
    const features = [
      (Icons.account_balance_wallet_rounded, 'Módulo Financeiro', 'Receitas, despesas, orçamentos, metas e relatórios.'),
      (Icons.event_note_rounded, 'Módulo Agenda', 'Compromissos, lembretes e planejamento no dia a dia.'),
      (Icons.menu_book_rounded, 'Módulo Cursos Financeiros', 'Educação financeira com princípios bíblicos.'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
      child: Column(
        children: [
          Text(
            'Módulos do WISDOMAPP',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _lpNavy, letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Financeiro, agenda e cursos financeiros com princípios bíblicos — tudo integrado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < features.length; i++)
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    final delay = i * 0.06;
                    final anim = Tween<double>(begin: 0, end: 1).animate(
                      CurvedAnimation(
                        parent: _animController,
                        curve: Interval(delay.clamp(0.0, 0.9), (delay + 0.2).clamp(0.0, 1.0),
                            curve: Curves.easeOut),
                      ),
                    );
                    return Opacity(opacity: anim.value, child: Transform.translate(offset: Offset(0, 20 * (1 - anim.value)), child: child));
                  },
                  child: _featureCard(features[i].$1, features[i].$2, features[i].$3),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, String desc) {
    return Container(
      width: 268,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: _lpViolet.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 10)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [_lpViolet.withValues(alpha: 0.12), _lpCyan.withValues(alpha: 0.1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(icon, size: 36, color: _lpViolet),
          ),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _lpDeep)),
          const SizedBox(height: 10),
          Text(desc, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.35, fontSize: 13.5)),
        ],
      ),
    );
  }

  // --- Planos Premium e PRO: landing_content + app_config/mp_checkout_prices ---
  Widget _buildPricingSection(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final twoCols = w >= 720;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFF1F5F9), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
      child: Column(
        children: [
          Text(
            _landing.plansTitle,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _lpDeep, letterSpacing: -0.6),
          ),
          const SizedBox(height: 10),
          Text(
            _landing.homePremiumCombinedPriceLine,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _lpSlate),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _landing.landingPremiumDetail,
              style: TextStyle(fontSize: 15, height: 1.45, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          if (twoCols)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _priceCard(
                    context,
                    title: _landing.divPremiumTitulo,
                    price: _landing.homePremiumCombinedPriceLine,
                    period: _landing.landingPremiumCardPeriod,
                    features: _landing.landingPremiumFeaturesList,
                    isPremium: true,
                    ctaLabel: _webFromIosAppLicense ? 'Renove ou adquira — ver planos' : _landing.planCtaText,
                  ),
                ),
              ],
            )
          else ...[
            Center(
              child: _priceCard(
                context,
                title: _landing.divPremiumTitulo,
                price: _landing.homePremiumCombinedPriceLine,
                period: _landing.landingPremiumCardPeriod,
                features: _landing.landingPremiumFeaturesList,
                isPremium: true,
                ctaLabel: _webFromIosAppLicense ? 'Renove ou adquira — ver planos' : _landing.planCtaText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceCard(
    BuildContext context, {
    required String title,
    required String price,
    required String period,
    required List<String> features,
    required bool isPremium,
    bool isProTier = false,
    String ctaLabel = 'Assinar agora',
  }) {
    final borderGradient = isPremium
        ? (isProTier
            ? LinearGradient(colors: [_lpRose, _lpViolet, _lpCyan], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : LinearGradient(colors: [_lpViolet, _lpCyan, _lpGold], begin: Alignment.topLeft, end: Alignment.bottomRight))
        : null;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: borderGradient,
        color: isPremium ? null : Colors.grey.shade300,
        boxShadow: [
          BoxShadow(color: _lpDeep.withValues(alpha: isPremium ? 0.25 : 0.08), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isPremium ? _lpDeep : Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          children: [
            if (isPremium)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: _lpGold, size: 26),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.4),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _lpDeep)),
              const SizedBox(height: 16),
            ],
            if (isPremium) const SizedBox(height: 12),
            Text(
              price,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: isPremium ? _lpCyan : _lpViolet, height: 1.2),
            ),
            const SizedBox(height: 6),
            Text(period, textAlign: TextAlign.center, style: TextStyle(color: isPremium ? Colors.white70 : Colors.grey.shade600, fontSize: 13)),
            Divider(height: 36, color: isPremium ? Colors.white24 : Colors.grey.shade300),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 20, color: isPremium ? _lpGold : Colors.green.shade600),
                      const SizedBox(width: 10),
                      Expanded(child: Text(f, style: TextStyle(color: isPremium ? Colors.white.withValues(alpha: 0.92) : Colors.black87, height: 1.35))),
                    ],
                  ),
                )),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: isPremium ? LinearGradient(colors: [_lpViolet, Color.lerp(_lpViolet, _lpRose, 0.35)!]) : null,
                  color: isPremium ? null : _lpViolet,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      if (FirebaseAuth.instance.currentUser != null) {
                        IosPaymentsGate.pushEscolhaPlano(context);
                      } else {
                        Navigator.pushNamed(context, '/login-para-plano');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          ctaLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    const email = 'raihom@gmail.com';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          const Text("Sistema sem propagandas indesejáveis, limpo e seguro.", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
          const SizedBox(height: 4),
          const Text("Acesso pelo celular, computador ou notebook. Acesso livre total.", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
          const SizedBox(height: 6),
          Builder(
            builder: (context) {
              final pwaIos = kIsWeb && isPwaIos;
              final String paymentFooter = pwaIos
                  ? "No Safari no iPhone/iPad, contrate o plano pelo app instalado (TestFlight) ou pelo site no computador."
                  : "Pagamento seguro via Mercado Pago (PIX ou Cartão)";
              return Text(
                paymentFooter,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              );
            },
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _FooterLink(label: 'Política de Privacidade', onTap: () => Navigator.of(context).pushNamed('/privacidade')),
              Text('•', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              _FooterLink(label: 'Termos de Uso', onTap: () => Navigator.of(context).pushNamed('/termos')),
              Text('•', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              _FooterLink(label: 'Suporte', onTap: () => Navigator.of(context).pushNamed('/suporte')),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _FooterLink(label: email, onTap: () => _launch(Uri.parse('mailto:$email'))),
            ],
          ),
          const SizedBox(height: 20),
          Text(AppVerse.full, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          Text('Desenvolvido por Raihom Barbosa', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text('© 2026 WISDOMAPP', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(label, style: const TextStyle(color: Color(0xFF2962FF), fontSize: 13, decoration: TextDecoration.underline, decorationColor: Color(0xFF2962FF))),
    );
  }
}
