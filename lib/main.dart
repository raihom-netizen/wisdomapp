import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'utils/ensure_web_document_head_stub.dart'
    if (dart.library.html) 'utils/ensure_web_document_head_web.dart'
    as ensure_web_head;
import 'theme/gemini_theme.dart';
import 'widgets/wisdomapp_branded_loading.dart';
import 'screens/landing_screen.dart';
import 'screens/tela_divulgacao_page.dart';
import 'screens/assego_public_signup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/admin_route_gate.dart';
import 'screens/signup_screen.dart';
import 'screens/home_shell.dart';
import 'screens/biometric_gate_screen.dart';
import 'services/biometric_auth_service.dart';
import 'services/auth_service.dart';
import 'services/app_session_cache.dart';
import 'services/delegate_access_service.dart';
import 'services/home_start_module_cache.dart';
import 'services/course_videos_cache_service.dart';
import 'services/login_preferences.dart';
import 'services/user_profile_startup_cache.dart';
import 'utils/firestore_user_doc_id.dart';
import 'services/session_restore_service.dart';
import 'screens/downloads_screen.dart';
import 'screens/payment_status_screen.dart';
import 'screens/escolha_plano_page.dart';
import 'screens/privacidade_screen.dart';
import 'screens/termos_screen.dart';
import 'screens/suporte_screen.dart';
import 'screens/login_para_plano_screen.dart';
import 'screens/premium_success_page.dart';
import 'constants/bank_brand_assets.dart';
import 'screens/supported_banks_screen.dart';
import 'widgets/license_gate.dart';
import 'services/version_check_service.dart';
import 'services/push_background_handler.dart';
import 'services/push_notification_service.dart';
import 'services/functions_service.dart';
import 'services/ios_payments_gate.dart';
import 'utils/pwa_install_helper.dart';
import 'utils/visibility_resume.dart';
import 'utils/browser_document_title.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'widgets/global_web_offline_banner.dart';
import 'widgets/shell_keyboard_bottom_pad.dart';
import 'utils/webview_platform_register.dart';
import 'utils/connectivity_offline.dart';
import 'utils/browser_online_stub.dart'
    if (dart.library.html) 'utils/browser_online_web.dart';

/// Garante [FirebaseApp] default uma única vez e aplica settings do Firestore antes de qualquer leitura.
/// Idempotente: evita crash `duplicate-app` em hot restart / cenários raros.
///
/// Safari iPhone: (1) `firebase_core_web` injeta scripts com `document.head!` — se `head`
/// atrasar no WebKit → "Null check operator used on a null value". Garantimos `<head>` + retentativas.
/// (2) Na Web: cache persistente desligado + **long-polling forçado** (evita assert interno do SDK 11.x
/// em `WatchChangeAggregator` quando o Auth renova token em paralelo ao WebChannel).
Future<void> _configureFirebaseCore() async {
  if (kIsWeb) {
    // 1) Evita crash em firebase_core_web (document.head! …) se head atrasar no WebKit.
    ensure_web_head.ensureWebDocumentReadyForFirebase();
    // 2) Cede um frame ao Safari para DOM + Trusted Types estabilizarem.
    await Future<void>.delayed(const Duration(milliseconds: 32));
    ensure_web_head.ensureWebDocumentReadyForFirebase();
    await Future<void>.delayed(const Duration(milliseconds: 24));
  }

  var appsEmpty = true;
  try {
    appsEmpty = Firebase.apps.isEmpty;
  } catch (e, st) {
    debugPrint('Firebase.apps (web/safari): $e\n$st');
    appsEmpty = true;
  }

  if (appsEmpty) {
    if (kIsWeb) {
      // Safari iOS: firebase_core_web injeta scripts com document.head! — corrida com o DOM
      // ou Trusted Types pode falhar; várias tentativas com backoff costumam estabilizar.
      const maxWebAttempts = 8;
      for (var attempt = 1; attempt <= maxWebAttempts; attempt++) {
        ensure_web_head.ensureWebDocumentReadyForFirebase();
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          break;
        } on FirebaseException catch (e) {
          if (e.code == 'duplicate-app') break;
          rethrow;
        } catch (e, st) {
          debugPrint(
            'Firebase.initializeApp (web) tentativa $attempt/$maxWebAttempts: $e\n$st',
          );
          var stillEmpty = true;
          try {
            stillEmpty = Firebase.apps.isEmpty;
          } catch (_) {}
          if (!stillEmpty) {
            break;
          }
          final msg = e.toString();
          final likelyTransient =
              msg.contains('Null check') ||
              msg.contains('null value') ||
              msg.contains('TrustedTypes') ||
              msg.contains('appendChild');
          if (attempt >= maxWebAttempts ||
              (!likelyTransient && !msg.contains('undefined'))) {
            Error.throwWithStackTrace(e, st);
          }
          await Future<void>.delayed(Duration(milliseconds: 56 * attempt));
        }
      }
    } else {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on FirebaseException catch (e) {
        if (e.code != 'duplicate-app') rethrow;
      } catch (e, st) {
        debugPrint('Firebase.initializeApp: $e\n$st');
        var stillEmpty = true;
        try {
          stillEmpty = Firebase.apps.isEmpty;
        } catch (_) {}
        if (stillEmpty) rethrow;
      }
    }
  }

  if (kIsWeb) {
    // Sem cache IndexedDB na Web: evita INTERNAL ASSERTION no login Google / troca de sessão.
    // Long-polling reduz falhas no agregador de watch do SDK JS 11.x.
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        webExperimentalForceLongPolling: true,
      );
    } catch (e, st) {
      debugPrint(
        'Firestore settings (web: sem cache + long-polling) falhou: $e\n$st',
      );
    }
    return;
  }

  try {
    // Cache offline: Financeiro, Escalas, Calculadora (Firestore), Agenda (reminders)
    // ficam em fila local e sincronizam quando a rede voltar.
    // Android: cache LIMITADO (100 MB) — o cache ilimitado deixava o SQLite crescer
    // sem teto e gerava I/O de disco/jank em aparelhos com armazenamento mais lento.
    // iOS está perfeito e fica como está (ilimitado) para não regredir.
    final int cacheBytes = (defaultTargetPlatform == TargetPlatform.android)
        ? 100 *
              1024 *
              1024 // 100 MB
        : Settings.CACHE_SIZE_UNLIMITED;
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
      cacheSizeBytes: cacheBytes,
    );
  } catch (e, st) {
    debugPrint('Firestore settings (cache completo) falhou: $e\n$st');
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
    } catch (e2, st2) {
      debugPrint('Firestore settings (sem persistência) falhou: $e2\n$st2');
      rethrow;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  // Limita o cache de imagens — especialmente importante na web/PWA Android,
  // onde o cache padrão (1000 imagens / 100MB) acaba causando travadas e
  // GC pauses. Em mobile manter mais conservador.
  if (kIsWeb) {
    PaintingBinding.instance.imageCache.maximumSize = 200;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        50 * 1024 * 1024; // 50 MB
  } else {
    PaintingBinding.instance.imageCache.maximumSize = 400;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        80 * 1024 * 1024; // 80 MB
  }
  registerWebViewForWebEngine();
  // Em release: exibe erro na tela em vez de tela branca quando um widget quebra no build.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Container(
        color: const Color(0xFF1A237E),
        padding: const EdgeInsets.all(24),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    details.exception.toString().split('\n').first,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };
  if (!kIsWeb) {
    // Android 15+ / iOS: conteúdo até às bordas; barras do sistema sobrepostas com ícones legíveis no tema.
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  // iOS/Android: Firebase default DEVE existir antes do primeiro frame que usa Auth/Firestore.
  // Dois runApp (bootstrap + app) em release iOS gerava [core/no-app] em alguns dispositivos.
  try {
    await _configureFirebaseCore();
  } catch (e, st) {
    debugPrint('Firebase init error: $e\n$st');
    runApp(_FirebaseInitErrorApp(message: e.toString()));
    return;
  }
  // Prefs críticas para login instantâneo; locale formata depois do 1º frame.
  await Future.wait<void>([
    LoginPreferences.warmUpForStartup(),
    DelegateAccessService.loadFromPrefs(),
    AppSessionCache.warmUp(),
    BiometricStartupCache.warmUpEnabledHint(),
    UserProfileStartupCache.warmUp(),
    HomeStartModuleCache.warmUp(),
    CourseVideosCacheService.warmUp(),
  ]);
  final reopenUid =
      FirebaseAuth.instance.currentUser?.uid ?? AppSessionCache.cachedUidSync();
  runApp(const ControleTotalApp());
  unawaited(
    initializeDateFormatting('pt_BR', null).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('initializeDateFormatting(pt_BR) ignorado: $e\n$st');
    }),
  );
  if (kIsWeb) {
    unawaited(() async {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (e, st) {
        debugPrint('Auth setPersistence(LOCAL) ignorado: $e\n$st');
      }
      initPwaBeforeInstallPrompt(() {});
    }());
  } else if (BiometricStartupCache.enabledHint == true) {
    BiometricStartupCache.prefetch();
  }
  if (reopenUid != null &&
      reopenUid.isNotEmpty &&
      LoginPreferences.startupAccountSwitchPending != true) {
    // Não bloqueia o 1º frame: atualiza perfil/módulo inicial em background.
    unawaited(
      Future.wait<void>([
            UserProfileStartupCache.prefetch(reopenUid),
            HomeStartModuleCache.prefetch(reopenUid),
            CourseVideosCacheService.prefetch(),
          ])
          .timeout(const Duration(milliseconds: 800), onTimeout: () => <void>[])
          .catchError((_) {}),
    );
    // FCM: inicializado no HomeShell após o 1º frame (evita duplicar trabalho no cold start).
  }
  // Push nativo confiável (não pode falhar): cria canais Android, pede permissão
  // e anexa os listeners de FCM já no arranque — não só ao chegar no HomeShell.
  // Assim o push aparece na tela em qualquer estado: 1º push pós-instalação,
  // app em foreground ou em outra tela. Idempotente: a chamada do HomeShell vira no-op.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    unawaited(
      Future<void>.delayed(
        defaultTargetPlatform == TargetPlatform.android
            ? const Duration(seconds: 5)
            : const Duration(milliseconds: 600),
        () {
          PushNotificationService().inicializar().catchError((_) {});
        },
      ),
    );
  }
  unawaited(IosPaymentsGate.initialize());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    VersionCheckService.checkAndReloadIfNeeded()
        .timeout(const Duration(seconds: 3), onTimeout: () {})
        .catchError((_) {});
    VersionCheckService.startWatchingForUpdates();
  });
  if (kIsWeb) {
    FunctionsService().logDomainAccess().catchError((_) => <String, dynamic>{});
  }
}

/// Se a inicialização falhar em [main], uma única árvore — sem segundo [runApp].
class _FirebaseInitErrorApp extends StatelessWidget {
  const _FirebaseInitErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1A237E);
    Widget errHome = Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Não foi possível iniciar o app (Firebase).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!kIsWeb) {
      errHome = AppKeyboardScope(child: ViewportStabilizer(child: errHome));
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      home: errHome,
    );
  }
}

/// Garante que o layout seja recalculado após o primeiro frame (iPhone 10–17,
/// Safari PWA, Android nativo). Evita toque “morto” até rotacionar retrato/paisagem.
/// Ao voltar do background ou mudar métricas (safe area), força rebuild.
/// Atualiza `<title>` na web por rota (SEO / abas — sugestões melhorias web).
class _WebRouteTitleObserver extends NavigatorObserver {
  static const String _defaultMetaDescription =
      'WISDOMAPP — Sabedoria financeira baseada nos princípios bíblicos. Teste grátis 30 dias. Financeiro, agenda e cursos.';
  static const String _divulgacaoMetaDescription =
      'WISDOMAPP — Divulgação: planos, promoções e login no site oficial. Renove com PIX ou cartão.';

  static const Map<String, String> _titles = {
    '/': 'WISDOMAPP — Início',
    '/login': 'WISDOMAPP — Entrar',
    '/signup': 'WISDOMAPP — Criar conta',
    '/downloads': 'WISDOMAPP — Downloads',
    '/dashboard': 'WISDOMAPP — Painel',
    '/checkout': 'WISDOMAPP — Pagamento',
    '/escolha-plano': 'WISDOMAPP — Planos',
    '/login-para-plano': 'WISDOMAPP — Login',
    '/licenca-expirada': 'WISDOMAPP — Licença',
    '/planos': 'WISDOMAPP — Planos',
    '/divulgacao': 'WISDOMAPP — Divulgação',
    '/admin': 'WISDOMAPP — Admin',
    '/privacidade': 'WISDOMAPP — Privacidade',
    '/termos': 'WISDOMAPP — Termos',
    '/suporte': 'WISDOMAPP — Suporte',
    PublicNavRoutes.bancosSuportados: 'WISDOMAPP — Bancos suportados',
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _apply(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _apply(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _apply(previousRoute);
  }

  void _apply(Route<dynamic> route) {
    if (!kIsWeb) return;
    final name = route.settings.name;
    if (name == null || name.isEmpty) {
      setBrowserDocumentTitle('WISDOMAPP');
      setBrowserMetaDescription(_defaultMetaDescription);
      return;
    }
    setBrowserDocumentTitle(_titles[name] ?? 'WISDOMAPP');
    if (name == '/divulgacao') {
      setBrowserMetaDescription(_divulgacaoMetaDescription);
    } else {
      setBrowserMetaDescription(_defaultMetaDescription);
    }
  }
}

class ViewportStabilizer extends StatefulWidget {
  final Widget child;

  const ViewportStabilizer({super.key, required this.child});

  @override
  State<ViewportStabilizer> createState() => _ViewportStabilizerState();
}

class _ViewportStabilizerState extends State<ViewportStabilizer>
    with WidgetsBindingObserver {
  /// Debounce: evita múltiplos repaints ao voltar (visibility + lifecycle disparam juntos) e previne tela preta/travamento.
  DateTime? _lastVisibleAt;
  DateTime? _lastMetricsBumpAt;

  /// Um único [setState] vazio já marca a subárvore como dirty; não repetir
  /// várias vezes em sequência — isso causava "tremor" ao voltar do sistema
  /// ou ao alternar PWA/aba (vários repaints seguidos).
  void _bumpLayoutOnce() {
    if (!mounted) return;
    // Web: só agenda frame — setState na raiz causava flash preto ao voltar da aba.
    if (kIsWeb) {
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    setState(() {});
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_onFirstFrame);
    setupVisibilityResumeListener(_onPageVisible);
  }

  @override
  void dispose() {
    disposeVisibilityResumeListener();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Após o primeiro frame: um bump + um frame extra + um único fallback tardio.
  /// Menos agressivo que antes (triplo post-frame + 3 timers) para evitar jitter.
  void _onFirstFrame(_) {
    if (!mounted) return;
    _bumpLayoutOnce();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.scheduleFrame();
    });
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Abrir/fechar o teclado (Android/iOS/Web) também dispara didChangeMetrics.
    // setState + rebuild amplo aqui deixava o IME lento ao focar TextFields (admin e app).
    // Um frame extra alinha hit-test/viewport sem reconstruir a árvore inteira.
    final now = DateTime.now();
    if (_lastMetricsBumpAt != null &&
        now.difference(_lastMetricsBumpAt!).inMilliseconds < 280) {
      return;
    }
    _lastMetricsBumpAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  /// Ao voltar do background / aba visível: um único rebuild + frames extras.
  /// Antes: 3× setState em sequência → layout "pulando" ou tremendo.
  void _onPageVisible() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastVisibleAt != null &&
        now.difference(_lastVisibleAt!).inMilliseconds < (kIsWeb ? 800 : 300)) {
      return;
    }
    _lastVisibleAt = now;
    _bumpLayoutOnce();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.scheduleFrame();
    });
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _onPageVisible();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ControleTotalApp extends StatefulWidget {
  const ControleTotalApp({super.key});

  @override
  State<ControleTotalApp> createState() => _ControleTotalAppState();
}

class _ControleTotalAppState extends State<ControleTotalApp> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    PushNotificationService.setScaffoldMessengerKey(_scaffoldMessengerKey);
    DelegateAccessService.onDelegateAccessRevoked = (message) {
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      final controller = messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              unawaited(DelegateAccessService.markRevokedSnackAcknowledged());
            },
          ),
        ),
      );
      controller.closed.then((_) {
        unawaited(DelegateAccessService.markRevokedSnackAcknowledged());
      });
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = GeminiTheme.light;
    final darkTheme = GeminiTheme.dark;

    /// Tema somente claro (modo escuro removido das configurações).
    const themeMode = ThemeMode.light;

    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      // Alinhar ao CFBundleDisplayName (Info.plist) — App Store exige nome semelhante ao do ícone.
      title: 'WISDOMAPP',
      navigatorObservers: [if (kIsWeb) _WebRouteTitleObserver()],
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      // Material, widgets e Cupertino em pt_BR (datas de picker, A11y, iOS).
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Usar sizeOf no clamp evita dependência de viewInsets — menos rebuild quando teclado abre (APK).
        final size = MediaQuery.sizeOf(context);
        var mq = MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true);
        if (size.width < 200 || size.height < 200) {
          mq = mq.copyWith(
            size: Size(
              size.width < 200 ? 390 : size.width,
              size.height < 200 ? 844 : size.height,
            ),
          );
        }
        final isPhoneLayout = mq.size.shortestSide < 600;
        // Telefone (retrato/paisagem): ViewportStabilizer — toque/viewport estável sem rodar a tela.
        if (isPhoneLayout) {
          Widget mobileLayer =
              child ?? const ColoredBox(color: Color(0xFF1A237E));
          mobileLayer = ViewportStabilizer(child: mobileLayer);
          mobileLayer = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: mobileLayer,
          );
          // Teclado global (Android/Web): pad isolado na raiz — Gboard rápido, sem pad por tela.
          mobileLayer = AppKeyboardScope(child: mobileLayer);
          // Banner off→on (web + mobile): mostra "Modo offline" / "Sincronizando"
          // / "Sincronizado". Pioneirismo: o usuário usa o sistema offline e
          // sincronizamos sozinho ao voltar a internet.
          mobileLayer = GlobalWebOfflineBanner(child: mobileLayer);
          return MediaQuery(data: mq, child: mobileLayer);
        }
        final inner = Theme(
          data: Theme.of(context).copyWith(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
          ),
          child: child ?? const ColoredBox(color: Color(0xFF1A237E)),
        );
        // iPad / tablet nativo: NÃO usar SelectionArea na raiz — captura gestos e já causou
        // relatos de tela preta / toque morto na análise da Apple (Diretriz 2.1).
        Widget stabilized = ViewportStabilizer(child: inner);
        stabilized = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: stabilized,
        );
        stabilized = AppKeyboardScope(child: stabilized);
        if (kIsWeb) {
          stabilized = SelectionArea(child: stabilized);
        }
        // Banner off→on em todos os dispositivos.
        stabilized = GlobalWebOfflineBanner(child: stabilized);
        return MediaQuery(data: mq, child: stabilized);
      },
      // Firebase já inicializado em main(); ir direto para rotas (evita piscar azul/branco).
      home: null,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) =>
            kIsWeb ? const LoginScreen() : const LandingScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/downloads': (context) => const DownloadsScreen(),
        '/dashboard': (context) => const _DashboardRoute(),
        '/checkout': (context) => const _PlanAuthGate(child: CheckoutScreen()),
        '/premium-pro-paywall': (context) =>
            const _PlanAuthGate(child: EscolhaPlanoPage()),

        /// FAQ, site, push: `Navigator.pushNamed(context, PublicNavRoutes.bancosSuportados)`.
        PublicNavRoutes.bancosSuportados: (context) =>
            const SupportedBanksScreen(),
        '/escolha-plano': (context) =>
            const _PlanAuthGate(child: EscolhaPlanoPage()),
        '/login-para-plano': (context) => const LoginParaPlanoScreen(),
        '/licenca-expirada': (context) => const LicencaExpiradaRoute(),
        '/planos': (context) => const LicencaExpiradaRoute(),
        '/divulgacao': (context) => const TelaDivulgacaoPage(),
        '/assego_usuarios': (context) => const AssegoPublicSignupScreen(),
        '/convenio_usuarios': (context) => const AssegoPublicSignupScreen(),
        '/admin': (context) => const AdminRouteGate(),
        '/privacidade': (context) => const PrivacidadeScreen(),
        '/termos': (context) => const TermosScreen(),
        '/suporte': (context) => const SuporteScreen(),
        '/premium-pro-success': (context) {
          final u = FirebaseAuth.instance.currentUser;
          if (u == null) {
            return kIsWeb ? const LoginScreen() : const LandingScreen();
          }
          return PremiumSuccessPage(uid: u.uid);
        },
      },
    );
  }
}

/// Tela exibida enquanto verifica sessão.
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen({
    this.offlineHint = false,
    this.restoreHint = false,
    this.delegateLinkHint = false,
  });

  final bool offlineHint;
  final bool restoreHint;
  final bool delegateLinkHint;

  @override
  Widget build(BuildContext context) {
    if (offlineHint) {
      return const WisdomappBrandedLoading(
        message: 'Sem internet — a restaurar sessão neste aparelho…',
        submessage:
            'Financeiro, Escalas, Calculadora e Agenda gravam localmente e sincronizam quando voltar a rede.',
      );
    }
    if (delegateLinkHint) {
      return const WisdomappBrandedLoading(
        message: 'Preparando acesso…',
        submessage:
            'Se você foi autorizado por outro titular, vamos vincular aos dados da licença principal.',
      );
    }
    return WisdomappBrandedLoading(
      message: restoreHint ? 'Abrindo sua conta…' : 'Abrindo…',
    );
  }
}

/// Verifica o estado de autenticação. Firebase Auth mantém a sessão no disco (LOCAL na web;
/// padrão nativo no Android/iOS) até [AuthService.signOut]. Reabrir o app ou o PWA instalado
/// volta ao painel se ainda houver sessão — sem “cair” no login por timeout curto.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _timeoutHit = false;
  Timer? _timeoutTimer;

  /// Cache do último usuário conhecido: ao voltar do background nunca mostrar loading nem tela preta.
  User? _cachedUser;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _deviceOffline = false;

  /// Sem rede: Firebase Auth pode demorar a ler a sessão do disco — voltamos a consultar [currentUser].
  Timer? _diskAuthPoll;

  @override
  void initState() {
    super.initState();
    _cachedUser = FirebaseAuth.instance.currentUser;
    if (_cachedUser != null || AppSessionCache.cachedUidSync() != null) {
      _ensureAuthRestorePoll();
    }
    if (LoginPreferences.startupAccountSwitchPending == true) {
      _returningUserFlagReady = true;
      _returningUserOnDevice = false;
      _restoreGiveUp = true;
      _timeoutHit = true;
    } else {
      _applyReturningUserFromWarmUp();
    }
    unawaited(_loadReturningUserFlag());
    unawaited(
      SessionRestoreService.tryRestoreIfNeeded().then((u) {
        if (u != null && mounted) {
          setState(() => _cachedUser = u);
        }
      }),
    );
    VersionCheckService.forceUpdateNotifier.addListener(_onForceUpdateChanged);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      var off = isConnectivityOffline(results);
      if (kIsWeb) {
        off = off || !browserNavigatorOnline();
      }
      if (off != _deviceOffline) setState(() => _deviceOffline = off);
    });
    Connectivity().checkConnectivity().then((results) {
      if (!mounted) return;
      var off = isConnectivityOffline(results);
      if (kIsWeb) {
        off = off || !browserNavigatorOnline();
      }
      setState(() => _deviceOffline = off);
    });
    if (kIsWeb) {
      listenBrowserOnlineOffline((online) {
        if (!mounted) return;
        final off = !online;
        if (off != _deviceOffline) setState(() => _deviceOffline = off);
      });
    }
  }

  void _onForceUpdateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    VersionCheckService.forceUpdateNotifier.removeListener(
      _onForceUpdateChanged,
    );
    _timeoutTimer?.cancel();
    _diskAuthPoll?.cancel();
    _restoreGiveUpTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _stopDiskAuthPoll() {
    _diskAuthPoll?.cancel();
    _diskAuthPoll = null;
  }

  /// Sem internet ou cold start: Firebase Auth pode demorar a ler sessão do disco.
  void _ensureAuthRestorePoll() {
    if (_diskAuthPoll != null) return;
    var ticks = 0;
    _diskAuthPoll = Timer.periodic(const Duration(milliseconds: 100), (
      t,
    ) async {
      ticks++;
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        _cachedUser = u;
        _timeoutHit = false;
        _timeoutTimer?.cancel();
        t.cancel();
        _diskAuthPoll = null;
        if (mounted) setState(() {});
        return;
      }
      if (ticks == 3 && !_silentRestoreStarted) {
        _silentRestoreStarted = true;
        final restored = await SessionRestoreService.tryRestoreIfNeeded();
        if (restored != null && mounted) {
          _cachedUser = restored;
          _timeoutHit = false;
          _timeoutTimer?.cancel();
          t.cancel();
          _diskAuthPoll = null;
          setState(() {});
          return;
        }
      }
      if (ticks >= 250) {
        t.cancel();
        _diskAuthPoll = null;
      }
    });
  }

  bool _silentRestoreStarted = false;
  bool _returningUserOnDevice = false;
  bool _returningUserFlagReady = false;
  bool _restoreGiveUp = false;
  Timer? _restoreGiveUpTimer;

  void _applyReturningUserFromWarmUp() {
    final returning = LoginPreferences.startupReturningUser;
    if (returning == null) return;
    _returningUserFlagReady = true;
    _returningUserOnDevice =
        returning && LoginPreferences.startupAccountSwitchPending != true;
    if (_returningUserOnDevice) _scheduleRestoreGiveUp();
  }

  void _scheduleRestoreGiveUp() {
    _restoreGiveUpTimer?.cancel();
    final uid = AppSessionCache.cachedUidSync();
    final fastPath = uid != null && AppSessionCache.isShellReadyForSync(uid);
    // Sessão já aberta neste aparelho: nunca desistir e mandar para landing.
    if (fastPath) return;
    _restoreGiveUpTimer = Timer(
      const Duration(seconds: 45),
      () {
        if (!mounted) return;
        if (FirebaseAuth.instance.currentUser != null || _cachedUser != null) {
          return;
        }
        final cached = AppSessionCache.cachedUidSync();
        if (cached != null && AppSessionCache.isShellReadyForSync(cached)) {
          return;
        }
        setState(() => _restoreGiveUp = true);
      },
    );
  }

  Future<void> _loadReturningUserFlag() async {
    await LoginPreferences.warmUpForStartup();
    final pending = await LoginPreferences.isAccountSwitchPending();
    final returning = await LoginPreferences.hasReturningLoginOnDevice();
    if (!mounted) return;
    setState(() {
      _returningUserFlagReady = true;
      _returningUserOnDevice = returning && !pending;
    });
    if (returning && !pending) {
      _scheduleRestoreGiveUp();
    }
  }

  void _startTimeoutIfWaiting() {
    if (_timeoutHit) return;
    _timeoutTimer?.cancel();
    // Offline: esperar bastante — sessão Auth no disco + Firestore em fila.
    final duration = _deviceOffline
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);
    _timeoutTimer = Timer(duration, () {
      if (mounted) setState(() => _timeoutHit = true);
    });
  }

  Widget _authedShell(String uid) =>
      _DelegateAccessGate(child: MaintenanceGate(uid: uid));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Restaurando sessão persistida (APK / iOS / PWA): priorizar currentUser do SDK.
        final syncUser = FirebaseAuth.instance.currentUser;

        if (snapshot.connectionState == ConnectionState.waiting) {
          if (syncUser != null) {
            _stopDiskAuthPoll();
            _cachedUser = syncUser;
            _timeoutHit = false;
            _timeoutTimer?.cancel();
            return _authedShell(syncUser.uid);
          }
          if (_cachedUser != null) {
            _stopDiskAuthPoll();
            return _authedShell(_cachedUser!.uid);
          }
          final optimisticUid = AppSessionCache.cachedUidSync();
          final shellWasReady =
              optimisticUid != null &&
              AppSessionCache.isShellReadyForSync(optimisticUid);
          if (optimisticUid != null &&
              LoginPreferences.startupAccountSwitchPending != true &&
              (shellWasReady ||
                  LoginPreferences.startupReturningUser != false)) {
            _ensureAuthRestorePoll();
            return _authedShell(optimisticUid);
          }
          _ensureAuthRestorePoll();
          _startTimeoutIfWaiting();
          if (_timeoutHit && syncUser == null && _cachedUser == null) {
            _timeoutTimer?.cancel();
            _stopDiskAuthPoll();
            final retryUser = FirebaseAuth.instance.currentUser;
            if (retryUser != null) {
              _cachedUser = retryUser;
              return _authedShell(retryUser.uid);
            }
            if (_returningUserOnDevice) {
              return _AuthLoadingScreen(
                offlineHint: _deviceOffline,
                restoreHint: true,
              );
            }
            if (LoginPreferences.startupAccountSwitchPending == true) {
              return const LandingScreen();
            }
            return const LandingScreen();
          }
          if (LoginPreferences.startupAccountSwitchPending == true) {
            return const LandingScreen();
          }
          return _AuthLoadingScreen(
            offlineHint: _deviceOffline,
            restoreHint: _returningUserFlagReady && _returningUserOnDevice,
          );
        }

        _stopDiskAuthPoll();

        if (snapshot.data != null) {
          _cachedUser = snapshot.data;
          _timeoutHit = false;
          _timeoutTimer?.cancel();
          return _authedShell(snapshot.data!.uid);
        }

        if (syncUser != null) {
          _cachedUser = syncUser;
          _timeoutHit = false;
          _timeoutTimer?.cancel();
          return _authedShell(syncUser.uid);
        }

        _cachedUser = null;

        if (LoginPreferences.startupAccountSwitchPending == true) {
          return const LandingScreen();
        }

        // Stream sem usuário: tenta restore antes de landing/divulgação.
        if (!_returningUserFlagReady) {
          unawaited(_loadReturningUserFlag());
          if (LoginPreferences.startupReturningUser == false) {
            return const LandingScreen();
          }
          return const _AuthLoadingScreen();
        }
        if (_returningUserOnDevice && !_restoreGiveUp) {
          final optimisticUid = AppSessionCache.cachedUidSync();
          if (optimisticUid != null &&
              AppSessionCache.isShellReadyForSync(optimisticUid)) {
            return _authedShell(optimisticUid);
          }
          return const _AuthLoadingScreen(restoreHint: true);
        }
        if (_returningUserOnDevice && _restoreGiveUp) {
          final cachedUid = AppSessionCache.cachedUidSync();
          if (cachedUid != null && AppSessionCache.isShellReadyForSync(cachedUid)) {
            return _authedShell(cachedUid);
          }
          return const LandingScreen();
        }

        _cachedUser = null;
        _timeoutHit = false;
        _timeoutTimer?.cancel();
        return const LandingScreen();
      },
    );
  }
}

/// Resolve acesso delegado (e-mail autorizado → UID principal) antes do painel.
class _DelegateAccessGate extends StatefulWidget {
  const _DelegateAccessGate({required this.child});

  final Widget child;

  @override
  State<_DelegateAccessGate> createState() => _DelegateAccessGateState();
}

class _DelegateAccessGateState extends State<_DelegateAccessGate>
    with WidgetsBindingObserver {
  bool _shellReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DelegateAccessService.sessionRevision.addListener(_onDelegateRevision);
    final cachedUid = AppSessionCache.cachedUidSync();
    if (cachedUid != null && AppSessionCache.isShellReadyForSync(cachedUid)) {
      _shellReady = true;
      DelegateAccessService.ensureDelegateIndexListener();
    }
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DelegateAccessService.sessionRevision.removeListener(_onDelegateRevision);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DelegateAccessService.revalidateSession());
    }
  }

  void _onDelegateRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid ??
        AppSessionCache.cachedUidSync();

    // Reabertura: mostra o painel na hora se já houve login neste aparelho.
    if (uid != null && mounted) {
      setState(() => _shellReady = true);
    }

    if (uid != null && AppSessionCache.isShellReadyForSync(uid)) {
      DelegateAccessService.ensureDelegateIndexListener();
      unawaited(_finishLoginBootstrapInBackground(markShellReady: false));
      return;
    }

    if (uid == null) {
      await DelegateAccessService.loadFromPrefs();
      if (mounted) setState(() => _shellReady = true);
      return;
    }

    unawaited(_finishLoginBootstrapInBackground(markShellReady: true));
  }

  Future<void> _finishLoginBootstrapInBackground({
    bool markShellReady = true,
  }) async {
    await DelegateAccessService.resolveAfterLogin(blocking: false);
    DelegateAccessService.ensureDelegateIndexListener();
    if (!markShellReady) return;
    try {
      await AuthService().ensureUserProfileFromSession(
        skipDelegateIndexProbe: true,
      );
    } catch (_) {}
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await AppSessionCache.markShellReady(uid);
      unawaited(UserProfileStartupCache.prefetch(uid));
      unawaited(HomeStartModuleCache.prefetch(uid));
      unawaited(CourseVideosCacheService.prefetch());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shellReady) {
      return const _AuthLoadingScreen(restoreHint: true);
    }
    return widget.child;
  }
}

/// Manutenção: apenas exibe aviso na tela principal (banner no dashboard). Nunca bloqueia o sistema.
class MaintenanceGate extends StatelessWidget {
  final String uid;

  const MaintenanceGate({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return _AuthenticatedGate(uid: uid);
  }
}

class _AuthenticatedGate extends StatefulWidget {
  final String uid;

  const _AuthenticatedGate({required this.uid});

  @override
  State<_AuthenticatedGate> createState() => _AuthenticatedGateState();
}

class _AuthenticatedGateState extends State<_AuthenticatedGate> {
  /// Usuário escolheu "Desativar digital e entrar" na tela de biometria (evita ficar travado no APK).
  bool _biometricBypass = false;

  /// Future em cache: ao voltar do background não recria e não mostra loading de novo.
  late final Future<List<dynamic>> _biometricFuture =
      BiometricStartupCache.future;

  @override
  void initState() {
    super.initState();
    DelegateAccessService.sessionRevision.addListener(_onDataOwnerChanged);
  }

  @override
  void dispose() {
    DelegateAccessService.sessionRevision.removeListener(_onDataOwnerChanged);
    super.dispose();
  }

  void _onDataOwnerChanged() {
    if (mounted) setState(() {});
  }

  String get _effectiveDocId => firestoreUserDocIdForAppShell(widget.uid);

  Widget _homeShell() =>
      HomeShell(key: ValueKey<String>(_effectiveDocId), uid: widget.uid);

  @override
  Widget build(BuildContext context) {
    final home = _homeShell();
    if (kIsWeb) return home;
    if (_biometricBypass) return home;
    if (BiometricStartupCache.enabledHint == false) return home;

    /// Digital só ao voltar do background ([BiometricGateScreen]); cold start = painel direto.
    if (BiometricStartupCache.enabledHint == true) {
      return BiometricGateScreen(
        uid: widget.uid,
        child: home,
        onDisableAndContinue: () => setState(() => _biometricBypass = true),
      );
    }

    return FutureBuilder<List<dynamic>>(
      future: _biometricFuture,
      builder: (context, snap) {
        if (!snap.hasData) return home;
        final isEnabled = snap.data![0] as bool;
        final biometricAvailable = snap.data![1] as bool;
        final biometricHardware = snap.data![2] as bool;

        if (isEnabled && (biometricAvailable || biometricHardware)) {
          return BiometricGateScreen(
            uid: widget.uid,
            child: home,
            onDisableAndContinue: () => setState(() => _biometricBypass = true),
          );
        }
        return home;
      },
    );
  }
}

/// Rota do dashboard: se o usuário estiver logado mostra HomeShell, senão Login.
class _DashboardRoute extends StatelessWidget {
  const _DashboardRoute();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return HomeShell(key: ValueKey<String>(user.uid), uid: user.uid);
    }
    return kIsWeb ? const LoginScreen() : const LandingScreen();
  }
}

/// Exibe a tela de plano/checkout só se o usuário estiver logado; senão mostra "Faça login para acessar o plano".
class _PlanAuthGate extends StatelessWidget {
  final Widget child;

  const _PlanAuthGate({required this.child});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final promoId = args is Map ? args['promoId']?.toString().trim() : null;
    final pendingPromo = (promoId != null && promoId.isNotEmpty)
        ? promoId
        : null;
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return child;
        }
        return LoginParaPlanoScreen(pendingPromoId: pendingPromo);
      },
    );
  }
}
