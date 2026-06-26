import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/landing_public_content.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/ios_payments_gate.dart';
import '../services/login_preferences.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../services/push_notification_service.dart';
import '../services/version_check_service.dart';
import '../utils/url_launcher_helper.dart';
import '../widgets/divulgacao_public_promo_card.dart';
import '../widgets/oauth_login_buttons.dart';
import '../widgets/official_channels_card.dart';
import '../widgets/wisdomapp_hero_brand.dart';

/// Página de divulgação (rota `/divulgacao`) — visual alinhado à landing super premium.
class TelaDivulgacaoPage extends StatefulWidget {
  const TelaDivulgacaoPage({super.key});

  @override
  State<TelaDivulgacaoPage> createState() => _TelaDivulgacaoPageState();
}

class _TelaDivulgacaoPageState extends State<TelaDivulgacaoPage>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  bool _loginLoading = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _landingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mpCheckoutSub;
  Map<String, dynamic>? _landingMainData;
  Map<String, dynamic>? _mpCheckoutData;
  LandingPublicContent _landing = LandingPublicContent.fromMap(null);

  late final AnimationController _intro;
  late final Animation<double> _fade;

  /// Paleta WISDOMAPP — azul marinho e dourado.
  static const Color _scaffoldBg = Color(0xFFF4F6FB);
  static const Color _lpDeep = Color(0xFF0A1F56);
  static const Color _lpNavyDark = Color(0xFF061428);
  static const Color _lpSlate = Color(0xFF1E293B);
  static const Color _lpViolet = Color(0xFF6366F1);
  static const Color _lpCyan = Color(0xFF22D3EE);
  static const Color _lpGold = Color(0xFFD4AF37);
  static const Color _lpGoldLight = Color(0xFFF0D878);
  static const Color _lpRose = Color(0xFFF43F5E);
  static const Color _lpIndigoDeep = Color(0xFF312E81);

  Color _parseHexColor(String? raw, Color fallback) {
    if (raw == null) return fallback;
    final cleaned = raw.trim().replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return fallback;
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    if (value == null) return fallback;
    return Color(value);
  }

  Color get _divThemePrimary => _parseHexColor(
      _landingMainData?['divThemePrimaryColor']?.toString(), _lpDeep);

  Color get _divThemeAccent => _parseHexColor(
      _landingMainData?['divThemeAccentColor']?.toString(), _lpGold);

  String _divField(String key) =>
      LandingPublicContent.pickDivEditor(_landingMainData, key);

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    _intro.forward();
    _bindPublicFirestoreListeners();
    if (!kIsWeb) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _redirectIfSessionPersisted());
    }
  }

  /// Após «trocar conta» → landing com login expresso (Google / Apple).
  Future<void> _redirectIfSessionPersisted() async {
    if (await LoginPreferences.isAccountSwitchPending()) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }
    if (FirebaseAuth.instance.currentUser == null) return;
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _bindPublicFirestoreListeners() {
    void mergeLanding() {
      if (!mounted) return;
      final base = LandingPublicContent.fromMap(_landingMainData);
      final snap = MpCheckoutPricingSnapshot.fromFirestore(_mpCheckoutData);
      setState(
          () => _landing = base.applyPremiumTextsFromCheckoutPricing(snap));
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

  void _resumePublicFirestoreListenersIfNeeded() {
    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser != null) return;
    if (_landingSub != null || _mpCheckoutSub != null) return;
    _bindPublicFirestoreListeners();
  }

  @override
  void dispose() {
    _pausePublicFirestoreListeners();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _persistOAuthHints(String provider) async {
    final u = FirebaseAuth.instance.currentUser;
    final e = u?.email?.trim() ?? '';
    if (e.isNotEmpty) await LoginPreferences.setLastLoginIdentifier(e);
    await LoginPreferences.setLastOAuthProvider(provider);
  }

  void _pausePublicFirestoreListeners() {
    _landingSub?.cancel();
    _landingSub = null;
    _mpCheckoutSub?.cancel();
    _mpCheckoutSub = null;
  }

  Future<void> _navigateAfterOAuthLogin() async {
    if (IosPaymentsGate.shouldHidePayments && IosPaymentsGate.isIosNative) {
      await IosPaymentsGate.openReaderPlansInSafari(source: 'divulgacao_oauth');
    } else if (context.mounted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/escolha-plano', (route) => false);
    }
  }

  Future<void> _loginWithGoogle() async {
    if (kIsWeb) _pausePublicFirestoreListeners();
    setState(() => _loginLoading = true);
    try {
      final cred = await _auth.signInWithGoogle();
      if (!mounted) return;
      if (cred != null) {
        await _persistOAuthHints('google');
        if (!mounted) return;
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        await _navigateAfterOAuthLogin();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Erro ao entrar com Google: ${AuthService.friendlyGoogleSignInError(e)}'),
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
    if (kIsWeb) _pausePublicFirestoreListeners();
    setState(() => _loginLoading = true);
    try {
      final cred = await _auth.signInWithApple();
      if (!mounted) return;
      if (cred != null) {
        await _persistOAuthHints('apple');
        if (!mounted) return;
        PushNotificationService().salvarTokenNoBanco().catchError((_) {});
        VersionCheckService.checkAndReloadIfNeeded().catchError((_) {});
        await _navigateAfterOAuthLogin();
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
      if (mounted) {
        setState(() => _loginLoading = false);
        _resumePublicFirestoreListenersIfNeeded();
      }
    }
  }

  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Future<void> _openExpressLogin() async {
    if (_loginLoading) return;
    setState(() => _loginLoading = true);
    try {
      if (_auth.currentUser != null) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }

      final silentCred = await _auth.signInWithGoogleSilently();
      if (silentCred != null) {
        await _persistOAuthHints('google');
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }

      if (!kIsWeb && AuthService.isSignInWithAppleAvailable) {
        final appleCred = await _auth.signInWithApple();
        if (appleCred != null) {
          await _persistOAuthHints('apple');
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          return;
        }
      }

      final googleCred = await _auth.signInWithGoogle();
      if (googleCred != null) {
        await _persistOAuthHints('google');
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Login expresso cancelado ou indisponível no momento.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não foi possível concluir o login expresso.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loginLoading = false);
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
              colors: [Color(0xFF111827), Color(0xFF1F2937), Color(0xFF0F766E)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _lpViolet.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _openExpressLogin,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.flash_on_rounded,
                          color: Colors.white),
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
                              color: Color(0xFFD1FAE5),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: _openExpressLogin,
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text(
                        'Entrar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final w = MediaQuery.sizeOf(context).width;
    final maxContent = kIsWeb
        ? (w > 900 ? 720.0 : (w > 600 ? 560.0 : double.infinity))
        : double.infinity;

    return Scaffold(
      backgroundColor: Color.lerp(_scaffoldBg, _divThemePrimary, 0.04),
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(const Color(0xFFF8FAFF), _divThemeAccent, 0.08) ??
                      const Color(0xFFF8FAFF),
                  Color.lerp(const Color(0xFFF4F6FB), _divThemePrimary, 0.06) ??
                      const Color(0xFFF4F6FB),
                  Color.lerp(const Color(0xFFF0F4FF), _divThemePrimary, 0.12) ??
                      const Color(0xFFF0F4FF),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            child: FadeTransition(
              opacity: _fade,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: _buildHero(context, _landing)),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: maxContent == double.infinity
                                ? 560
                                : maxContent),
                        child: Padding(
                          padding:
                              EdgeInsets.fromLTRB(20, 8, 20, pad.bottom + 104),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              if (kIsWeb)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: DivulgacaoPublicPromoCard(),
                                ),
                              OfficialChannelsCard(
                                title: _landing.divChannelsTitle,
                                subtitle: _landing.divChannelsSubtitle,
                                youtubeUrl: _landing.divYoutubeUrl,
                                instagramUrl: _landing.divInstagramUrl,
                                whatsappUrl: _landing.divWhatsappUrl,
                                youtubeLabel: _landing.divYoutubeLabel,
                                instagramLabel: _landing.divInstagramLabel,
                                whatsappLabel: _landing.divWhatsappLabel,
                              ),
                              const SizedBox(height: 14),
                              _buildLivroMentorSection(),
                              const SizedBox(height: 22),
                              _buildSectionLabel(_landing.divLabelComoFunciona),
                              const SizedBox(height: 10),
                              _buildComoFuncionaSteps(_landing),
                              const SizedBox(height: 28),
                              _buildSectionLabel(_landing.divLabelComece),
                              const SizedBox(height: 10),
                              Text(
                                _landing.divComeceParagraph,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  height: 1.45,
                                  fontWeight: FontWeight.w700,
                                  color: _lpDeep,
                                  letterSpacing: -0.25,
                                ),
                              ),
                              const SizedBox(height: 28),
                              _buildGerencieLicencaCard(context, _landing),
                              const SizedBox(height: 28),
                              _buildTrialCard(context, _landing),
                              const SizedBox(height: 36),
                              _buildSectionLabel(_landing.divLabelPlanos),
                              const SizedBox(height: 8),
                              Text(
                                _landing.divPlanosSubtitle,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (kIsWeb && w >= 820)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _buildPlanoCard(
                                        context,
                                        c: _landing,
                                        titulo: _landing.divBasicoTitulo,
                                        mensal: _landing.divBasicoMensal,
                                        anual: _landing.divBasicoAnual,
                                        beneficios:
                                            _landing.divBasicoBeneficiosList,
                                        isPremium: false,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildPlanoCard(
                                        context,
                                        c: _landing,
                                        titulo: _landing.divPremiumTitulo,
                                        mensal: _landing.divPremiumMensal,
                                        anual: _landing.divPremiumAnual,
                                        beneficios:
                                            _landing.divPremiumBeneficiosList,
                                        isPremium: true,
                                        cardSubtitle:
                                            _landing.divPremiumCardSubtitle,
                                        ribbonText: _landing.divPremiumRibbon,
                                      ),
                                    ),
                                  ],
                                )
                              else if (kIsWeb && w >= 640)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _buildPlanoCard(
                                        context,
                                        c: _landing,
                                        titulo: _landing.divBasicoTitulo,
                                        mensal: _landing.divBasicoMensal,
                                        anual: _landing.divBasicoAnual,
                                        beneficios:
                                            _landing.divBasicoBeneficiosList,
                                        isPremium: false,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildPlanoCard(
                                        context,
                                        c: _landing,
                                        titulo: _landing.divPremiumTitulo,
                                        mensal: _landing.divPremiumMensal,
                                        anual: _landing.divPremiumAnual,
                                        beneficios:
                                            _landing.divPremiumBeneficiosList,
                                        isPremium: true,
                                        cardSubtitle:
                                            _landing.divPremiumCardSubtitle,
                                        ribbonText: _landing.divPremiumRibbon,
                                      ),
                                    ),
                                  ],
                                )
                              else ...[
                                _buildPlanoCard(
                                  context,
                                  c: _landing,
                                  titulo: _landing.divBasicoTitulo,
                                  mensal: _landing.divBasicoMensal,
                                  anual: _landing.divBasicoAnual,
                                  beneficios: _landing.divBasicoBeneficiosList,
                                  isPremium: false,
                                ),
                                const SizedBox(height: 16),
                                _buildPlanoCard(
                                  context,
                                  c: _landing,
                                  titulo: _landing.divPremiumTitulo,
                                  mensal: _landing.divPremiumMensal,
                                  anual: _landing.divPremiumAnual,
                                  beneficios: _landing.divPremiumBeneficiosList,
                                  isPremium: true,
                                  cardSubtitle: _landing.divPremiumCardSubtitle,
                                  ribbonText: _landing.divPremiumRibbon,
                                ),
                              ],
                              const SizedBox(height: 36),
                              OAuthLoginButtons(
                                loading: _loginLoading,
                                onGoogle: _loginWithGoogle,
                                onApple: AuthService.isSignInWithAppleAvailable
                                    ? _loginWithApple
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              _buildActionButton(
                                context,
                                _landing.divBtnAreaAdmin,
                                () => Navigator.pushNamed(context, '/admin'),
                                isPrimary: false,
                              ),
                              if (kIsWeb) ...[
                                const SizedBox(height: 20),
                                _buildFooterStrip(context, _landing),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    );
  }

  Widget _buildLivroMentorSection() {
    final badge = _divField('divBookBadge');
    final title = _divField('divBookTitle');
    final author = _divField('divBookAuthor');
    final subtitle = _divField('divBookSubtitle');
    final launchText = _divField('divBookLaunchText');
    final imageUrl = _divField('divBookImageUrl').trim();
    final mentorName = _divField('divMentorName');
    final mentorRole = _divField('divMentorRole');
    final instaUrl = _divField('divMentorInstagramUrl').trim();
    final whatsUrl = _divField('divMentorWhatsappUrl').trim();
    final ytUrl = _divField('divMentorYoutubeUrl').trim();
    final instaLabel = _divField('divMentorInstagramLabel');
    final whatsLabel = _divField('divMentorWhatsappLabel');
    final ytLabel = _divField('divMentorYoutubeLabel');

    Widget linkButton({
      required Widget icon,
      required String label,
      required String url,
      required Color color,
    }) {
      final enabled = url.isNotEmpty &&
          (url.startsWith('http://') || url.startsWith('https://'));
      return Expanded(
        child: FilledButton.icon(
          onPressed: enabled ? () => unawaited(openUrlPreferChrome(url)) : null,
          icon: icon,
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade600,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    final imageWidget = imageUrl.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              height: 220,
              width: double.infinity,
              errorBuilder: (_, __, ___) => _fallbackBookCover(),
            ),
          )
        : _fallbackBookCover();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            Color.lerp(_divThemePrimary, Colors.black, 0.08) ??
                _divThemePrimary,
            Color.lerp(_divThemePrimary, _divThemeAccent, 0.25) ??
                _divThemePrimary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _divThemePrimary.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _divThemeAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: _divThemeAccent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.menu_book_rounded, color: _divThemeAccent, size: 22),
            ],
          ),
          const SizedBox(height: 10),
          imageWidget,
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Autor: $author',
            style: GoogleFonts.inter(
              color: _divThemeAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            launchText,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mentorName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mentorRole,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    linkButton(
                      icon: const FaIcon(FontAwesomeIcons.instagram, size: 18),
                      label: instaLabel,
                      url: instaUrl,
                      color: const Color(0xFFBE185D),
                    ),
                    const SizedBox(width: 8),
                    linkButton(
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                      label: whatsLabel,
                      url: whatsUrl,
                      color: const Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 8),
                    linkButton(
                      icon: const FaIcon(FontAwesomeIcons.youtube, size: 18),
                      label: ytLabel,
                      url: ytUrl,
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackBookCover() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 220,
        width: double.infinity,
        child: Image.asset(
          'assets/images/livro_um_degrau_abaixo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(_divThemePrimary, Colors.black, 0.12) ??
                        _divThemePrimary,
                    Color.lerp(_divThemePrimary, _divThemeAccent, 0.22) ??
                        _divThemePrimary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, LandingPublicContent c) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _divThemePrimary,
            Color.lerp(_lpSlate, _divThemePrimary, 0.5) ?? _lpSlate,
            Color.lerp(_lpIndigoDeep, _divThemeAccent, 0.2) ?? _lpIndigoDeep,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
              color: _divThemePrimary.withValues(alpha: 0.32),
              blurRadius: 40,
              offset: const Offset(0, 18)),
          BoxShadow(
              color: _divThemeAccent.withValues(alpha: 0.16),
              blurRadius: 48,
              offset: const Offset(0, 24)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Column(
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _goHome,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.arrow_back_rounded,
                            color: Colors.white.withValues(alpha: 0.95),
                            size: 22),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (kIsWeb)
                    TextButton.icon(
                      onPressed: _goHome,
                      icon: Icon(Icons.home_rounded,
                          size: 18, color: Colors.white.withValues(alpha: 0.9)),
                      label: Text(
                        c.divNavInicio,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const WisdomappHeroBrand(showMicroTagline: true, showIdealizer: true, compact: true),
              const SizedBox(height: 12),
              Text(
                c.divHeroTagline,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _lpCyan.withValues(alpha: 0.95),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      _lpViolet.withValues(alpha: 0.35),
                      _lpRose.withValues(alpha: 0.28),
                      _lpGold.withValues(alpha: 0.4),
                    ],
                  ),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  boxShadow: [
                    BoxShadow(
                        color: _lpGold.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Text(
                  c.divHeroBadge,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.25,
                    color: Colors.white.withValues(alpha: 0.96),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                c.divHeroHeadline,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(height: 22),
              Semantics(
                label: 'Entrar na conta ou ver planos',
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OAuthLoginButtons(
                      loading: _loginLoading,
                      onGoogle: _loginWithGoogle,
                      onApple: AuthService.isSignInWithAppleAvailable
                          ? _loginWithApple
                          : null,
                      googleForeground: _lpDeep,
                      googleBackground: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.9),
                            width: 1.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, '/login-para-plano');
                      },
                      child: Text(
                        c.divHeroBtnPlanos,
                        style: GoogleFonts.inter(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _heroChip(Icons.shield_rounded, c.divHeroChip1),
                  _heroChip(Icons.cloud_done_rounded, c.divHeroChip2),
                  _heroChip(Icons.payments_rounded, c.divHeroChip3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComoFuncionaSteps(LandingPublicContent c) {
    Widget step(int n, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _lpViolet.withValues(alpha: 0.15),
              child: Text(
                '$n',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: _lpViolet,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _lpDeep,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: 'Como funciona em três passos',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          step(
            1,
            c.divStep1Title,
            c.divStep1Body,
          ),
          step(
            2,
            c.divStep2Title,
            c.divStep2Body,
          ),
          step(
            3,
            c.divStep3Title,
            c.divStep3Body,
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.88)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
                colors: [_lpViolet, _lpCyan, _lpRose.withValues(alpha: 0.85)]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: _lpDeep,
            ),
          ),
        ),
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
                colors: [_lpCyan, _lpGold, _lpViolet.withValues(alpha: 0.9)]),
          ),
        ),
      ],
    );
  }

  Widget _buildGerencieLicencaCard(
      BuildContext context, LandingPublicContent c) {
    final titleStyle = GoogleFonts.inter(
      fontSize: 24,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.6,
      color: Colors.white,
      height: 1.1,
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: _lpViolet.withValues(alpha: 0.28),
              blurRadius: 36,
              offset: const Offset(0, 16)),
          BoxShadow(
              color: _lpGold.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 22)),
          BoxShadow(
              color: _lpCyan.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(-4, 8)),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_lpViolet, _lpCyan, _lpGold, _lpRose],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                const Color(0xFFF8FAFF),
                Colors.white.withValues(alpha: 0.97),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [_lpDeep, _lpViolet, const Color(0xFF4F46E5)],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: _lpViolet.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          color: _lpGold, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        c.divGerencieTopBadge,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          _lpViolet.withValues(alpha: 0.2),
                          _lpCyan.withValues(alpha: 0.14),
                          _lpRose.withValues(alpha: 0.1),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: _lpViolet.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Icon(Icons.workspace_premium_rounded,
                        color: _lpDeep, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [_lpDeep, _lpViolet, _lpCyan],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ).createShader(
                              Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
                          child: Text(c.divGerencieTitle, style: titleStyle),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          c.divGerencieSubtitle,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _lpSlate.withValues(alpha: 0.85),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      _lpViolet.withValues(alpha: 0),
                      _lpViolet.withValues(alpha: 0.35),
                      _lpCyan.withValues(alpha: 0.45),
                      _lpGold.withValues(alpha: 0.35),
                      _lpRose.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                c.divGerencieParagraph,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: _lpSlate.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 20),
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
    );
  }

  Widget _buildTrialCard(BuildContext context, LandingPublicContent c) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            _lpViolet.withValues(alpha: 0.35),
            const Color(0xFF34D399).withValues(alpha: 0.55),
            _lpCyan.withValues(alpha: 0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.14),
              blurRadius: 26,
              offset: const Offset(0, 12)),
        ],
      ),
      padding: const EdgeInsets.all(1.5),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22.5),
          gradient: LinearGradient(
            colors: [
              const Color(0xFFECFDF5),
              const Color(0xFFD1FAE5).withValues(alpha: 0.65),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
              color: const Color(0xFF34D399).withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  color: Colors.teal.shade700, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              c.divTrialTitleWithDays(UserProfile.newUserTrialDays),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF065F46),
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              c.divTrialBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanoCard(
    BuildContext context, {
    required LandingPublicContent c,
    required String titulo,
    required String mensal,
    required String anual,
    required List<String> beneficios,
    required bool isPremium,
    String? cardSubtitle,

    /// Add-on (ex.: Open Finance extra) — preenchido a partir de `app_config` via [LandingPublicContent.applyPremiumTextsFromCheckoutPricing].
    String? extrasLine,
    String? ribbonText,
  }) {
    final premiumSubtitle =
        cardSubtitle ?? (isPremium ? c.divPremiumCardSubtitle : null);
    final premiumRibbon = ribbonText ?? (isPremium ? c.divPremiumRibbon : null);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(22, isPremium ? 28 : 22, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isPremium
                  ? _lpViolet.withValues(alpha: 0.45)
                  : Colors.grey.shade200,
              width: isPremium ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isPremium ? _lpViolet : Colors.black)
                    .withValues(alpha: isPremium ? 0.16 : 0.05),
                blurRadius: isPremium ? 32 : 16,
                offset: const Offset(0, 12),
              ),
              if (isPremium)
                BoxShadow(
                  color: _lpGold.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: titulo.length > 52 ? 17 : 22,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: _lpDeep,
                  letterSpacing: -0.5,
                ),
              ),
              if (premiumSubtitle != null && premiumSubtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  premiumSubtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _lpViolet,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _priceLine(Icons.calendar_today_rounded, mensal, isPremium),
              const SizedBox(height: 8),
              _priceLine(Icons.event_repeat_rounded, anual, isPremium),
              if (extrasLine != null && extrasLine.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: _lpCyan.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isPremium ? _lpCyan : Colors.grey)
                          .withValues(alpha: isPremium ? 0.35 : 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.hub_rounded,
                        size: 18,
                        color: isPremium ? _lpViolet : Colors.teal.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          extrasLine.trim(),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color:
                                isPremium ? _lpDeep : Colors.blueGrey.shade800,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                c.divIncluiLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 10),
              ...beneficios.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: isPremium ? _lpViolet : Colors.teal.shade600,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: _lpSlate,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isPremium && premiumRibbon != null && premiumRibbon.isNotEmpty)
          Positioned(
            top: -10,
            right: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                    colors: [_lpGold, _lpGold.withValues(alpha: 0.85)]),
                boxShadow: [
                  BoxShadow(
                      color: _lpGold.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Text(
                premiumRibbon,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.05,
                  color: _lpDeep,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _priceLine(IconData icon, String text, bool premium) {
    return Row(
      children: [
        Icon(icon, size: 20, color: premium ? _lpViolet : Colors.grey.shade500),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _lpSlate,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterStrip(BuildContext context, LandingPublicContent c) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            _lpViolet.withValues(alpha: 0.4),
            _lpCyan.withValues(alpha: 0.35),
            _lpGold.withValues(alpha: 0.35)
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: _lpViolet.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(1.5),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18.5),
          border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        ),
        child: Column(
          children: [
            Text(
              c.divFooterDomain,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _lpViolet,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _goHome,
                  child: Text(c.divFooterHome,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, color: _lpDeep)),
                ),
                Text('·', style: TextStyle(color: Colors.grey.shade400)),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/termos'),
                  child: Text(c.divFooterTerms,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                ),
                Text('·', style: TextStyle(color: Colors.grey.shade400)),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/privacidade'),
                  child: Text(c.divFooterPrivacy,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      BuildContext context, String text, VoidCallback onPressed,
      {required bool isPrimary}) {
    if (!isPrimary) {
      return SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: _lpDeep,
            side: BorderSide(
                color: _lpViolet.withValues(alpha: 0.22), width: 1.5),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
          ),
          child: Text(text,
              style:
                  GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      );
    }
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  _lpViolet,
                  const Color(0xFF4F46E5),
                  _lpCyan,
                  _lpRose.withValues(alpha: 0.65)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: _lpViolet.withValues(alpha: 0.4),
                    blurRadius: 22,
                    offset: const Offset(0, 11)),
                BoxShadow(
                    color: _lpGold.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
