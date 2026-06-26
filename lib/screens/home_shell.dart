import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/firestore_user_doc_id.dart';
import '../services/account_switch_flow.dart';
import '../services/delegate_access_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/ios_payments_gate.dart';
import '../services/pending_storage_upload_service.dart';
import '../services/scale_rates_period_service.dart';
import '../services/scale_rates_service.dart';
import '../services/agenda_boot_orchestrator.dart';
import '../services/scale_notifications_service.dart';
import '../services/scale_auto_confirm_service.dart';
import '../services/user_backup_service.dart';
import '../services/backup_save.dart';
import '../services/user_settings_docs_cache.dart';
import '../services/functions_service.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/pwa_install_helper.dart';
import '../pwa_install/install_card.dart';
import '../theme/app_colors.dart';
import '../services/push_notification_service.dart';
import '../services/widget_data_service.dart';
import '../models/user_profile.dart';
import '../widgets/user_menu_lateral.dart';
import '../services/home_start_module_cache.dart';
import '../services/user_profile_startup_cache.dart';
import '../widgets/home_start_module_picker.dart';
import '../widgets/app_version_footer.dart';
import '../widgets/floating_shell_banners.dart';
import '../utils/admin_panel_launch.dart';
import 'dashboard_screen.dart';
import 'finance_screen.dart';
import 'meta_financeira_screen.dart';
import 'calculator_screen.dart';
import 'reports_screen.dart';
import 'wisdom_agenda_screen.dart';
import 'anotacoes_screen.dart';
import '../widgets/onboarding_tour.dart';
import '../widgets/premium_global_message_host.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';
import 'complete_profile_screen.dart';
import 'onboarding_screen.dart';
import 'settings_screen.dart';
import '../services/weekly_summary_in_app_coordinator.dart';
import '../services/user_client_telemetry_service.dart';
import 'cursos_videos_screen.dart';
import 'wisdom_dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _idx = 0;

  /// Módulos já instanciados no [IndexedStack] — materialização preguiçosa (evita 10 árvores de uma vez).
  final Set<int> _materializedModuleIndices = {0};

  /// Mantém no máximo 2 módulos vivos (atual + anterior) — libera streams/memória ao trocar de aba.
  static const int _kMaxRetainedMaterializedModules = 2;
  String _lastShellAuthEffectiveUid = '';
  String? _telemetryPingScheduledForUid;
  static const int _kShellModuleCount = 10;

  /// Mesmos módulos do rodapé de acesso rápido (menu abre fullscreen com os mesmos dados).
  static const Set<int> _footerQuickAccessModuleIndices = {0, 1, 2, 3, 7};

  /// Scroll principal por índice do módulo — ao trocar de aba, [jumpTo(0)] no módulo que sai e no que entra.
  late final List<ScrollController> _shellModuleScrollControllers =
      List<ScrollController>.generate(
    _kShellModuleCount,
    (_) => ScrollController(),
  );
  int? _footerPressedIndex;
  bool _menuCollapsed = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _onboardingChecked = false;
  bool _paymentSuccessBannerDismissed = false;
  bool _showPwaInstallBanner = false;

  /// True enquanto o utilizador não quis ver o cartão (snooze 7 dias — sugestão UX web).
  bool _pwaSnoozeActive = false;

  /// Throttle: não chamar checkMyPayment a cada resume (máx. 1x a cada 15s).
  DateTime? _lastPendingPaymentCheck;

  static const double _mobileBreakpoint = 600;

  /// Mantém o breakpoint retrato/paisagem estável enquanto o IME anima (shortestSide oscila).
  double _peakShortestSide = 0;
  Orientation? _orientationForPeak;

  /// Rodapé com 5 atalhos: em telas mais estreitas que isto, rótulos abreviados (ícones iguais).
  static const double _footerUltraNarrowWidth = 392;
  static const Duration _pendingPaymentThrottle = Duration(seconds: 15);

  /// Caminhos `users/{id}/…` nas regras: alinhar à sessão (web pode desincronizar o [HomeShell.uid]).
  String get _userDocId => firestoreUserDocIdForAppShell(widget.uid);

  /// UID efetivo para perfil/streams (nunca vazio na reabertura otimista Android).
  String get _profileFirestoreUid {
    final id = _userDocId;
    if (id.isNotEmpty) return id;
    final w = widget.uid.trim();
    return w;
  }

  bool get _hasFirestoreUid => _profileFirestoreUid.isNotEmpty;

  /// Android/iOS: fila offline do Firestore sincroniza sozinha; só ajudamos ao voltar a rede (sem UI).
  StreamSubscription<List<ConnectivityResult>>? _mobileConnSub;
  bool? _mobileWasOffline;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _weeklySummarySub;

  /// Reabre subscrições `users/{uid}/…` quando a sessão fica disponível (web).
  StreamSubscription<User?>? _shellAuthSub;

  /// Web: evita cancelar/recriar `.snapshots()` no mesmo tick que `notifyAuthListeners` (assert Firestore JS).
  Timer? _weeklySummaryRebindDebounce;
  bool _autoConfirmRunning = false;
  DateTime? _lastAutoConfirmClientRun;
  static const Duration _autoConfirmClientThrottle = Duration(minutes: 15);

  static bool _connectivityIsOffline(List<ConnectivityResult> result) {
    if (result.isEmpty) return true;
    return result.every((r) => r == ConnectivityResult.none);
  }

  void _bindWeeklySummaryListener() {
    if (kIsWeb) {
      _weeklySummaryRebindDebounce?.cancel();
      _weeklySummaryRebindDebounce = Timer(
        const Duration(milliseconds: 160),
        () {
          if (!mounted) return;
          _bindWeeklySummaryListenerNow();
        },
      );
      return;
    }
    _bindWeeklySummaryListenerNow();
  }

  void _bindWeeklySummaryListenerNow() {
    _weeklySummarySub?.cancel();
    final uid = firestoreUserDocIdStrictFromSession();
    if (uid.isEmpty) return;
    _weeklySummarySub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('weekly_summary')
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        unawaited(
          WeeklySummaryInAppCoordinator.onWeeklySummarySnapshot(uid, snap),
        );
      },
      onError: (Object e, StackTrace st) {
        debugPrint('weekly_summary snapshots: $e\n$st');
      },
    );
  }

  Future<void> _silentlySyncFirestoreAfterReconnect() async {
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.waitForPendingWrites();
    } catch (_) {}
    unawaited(PendingStorageUploadService.drainAll().catchError((_) {}));
    // Só limpa RAM; sem notificar telas inativas (evita recálculo em massa).
    ScaleRatesService().invalidateMemory(null, false);
  }

  void _initMobileFirestoreOfflineSync() {
    if (kIsWeb) return;
    Future<void> bootstrap() async {
      try {
        final r = await Connectivity().checkConnectivity();
        if (mounted) _mobileWasOffline = _connectivityIsOffline(r);
      } catch (_) {
        if (mounted) _mobileWasOffline = false;
      }
    }

    unawaited(bootstrap());
    _mobileConnSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = _connectivityIsOffline(results);
      if (_mobileWasOffline == true && !offline) {
        unawaited(_silentlySyncFirestoreAfterReconnect());
      }
      _mobileWasOffline = offline;
    });
  }

  /// Títulos dos módulos no topo (mesma ordem das abas): botão voltar + título padronizado.
  static const List<String> _moduleTitles = [
    'Início',
    'Financeiro',
    'Objetivo Financeiro',
    'Agenda',
    'Calculadora',
    'Dicas Financeiras',
    'Relatórios',
    'Cursos em Vídeo',
    'Minhas Anotações',
    'Configurações',
  ];

  String _currentModuleTitle() {
    if (_idx >= 0 && _idx < _moduleTitles.length) return _moduleTitles[_idx];
    return 'WISDOMAPP';
  }

  /// Barra: "Olá, [nome]" e vencimento da licença (controle para o usuário).
  Widget _buildBarGreetingAndLicense(
    UserProfile profile, {
    bool isCompact = false,
  }) {
    final isDelegate = DelegateAccessService.isActingAsDelegate;
    final sessionEmail = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    final ownerEmail = (DelegateAccessService.principalEmail ?? '').trim();
    final name = profile.name.trim().isEmpty ? 'Usuário' : profile.name;
    final fontSize = isCompact ? 16.0 : 17.0;
    final smallFontSize = isCompact ? 10.5 : 11.5;
    final email =
        isDelegate && ownerEmail.isNotEmpty ? ownerEmail : profile.email.trim();
    final plan = profile.planDisplayLabelForUi;
    String? venc;
    if (profile.licenseExpiresAt != null) {
      final e = profile.licenseExpiresAt!;
      venc =
          '${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}';
    }
    final resumoLic = venc != null ? '$plan · válido até $venc' : plan;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Olá, $name',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          softWrap: true,
        ),
        if (email.isNotEmpty) ...[
          SizedBox(height: isCompact ? 2 : 3),
          Text(
            isDelegate ? 'Titular: $email' : email,
            style: TextStyle(
              fontSize: smallFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.88),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            softWrap: false,
          ),
        ],
        if (isDelegate && sessionEmail.isNotEmpty) ...[
          SizedBox(height: isCompact ? 1 : 2),
          Text(
            'Autorizado: $sessionEmail',
            style: TextStyle(
              fontSize: smallFontSize - 0.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.78),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
        SizedBox(height: isCompact ? 2 : 4),
        Text(
          resumoLic,
          style: TextStyle(
            fontSize: smallFontSize,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.95),
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: isCompact ? 2 : 3,
          softWrap: true,
        ),
      ],
    );
  }

  Future<void> _consumeAndroidWidgetIntent() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      const ch = MethodChannel('controletotal/launcher');
      final raw = await ch.invokeMethod<dynamic>('takePendingModule');
      final idx = raw is int ? raw : int.tryParse('$raw') ?? -1;
      if (!mounted || idx < 0 || idx >= _kShellModuleCount) return;
      _setModuleIndex(idx);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    DelegateAccessService.sessionRevision.addListener(
      _onDelegateSessionChanged,
    );
    WidgetsBinding.instance.addObserver(this);
    _applyCachedPreferredStartModule();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Tarifas GO: só após idle longo (Escalas/Calculadora carregam ao abrir o módulo).
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (!mounted) return;
        unawaited(ScaleRatesPeriodService().ensureLoaded());
        unawaited(ScaleRatesService().ensureGlobalDefaults());
        if (_userDocId.isNotEmpty) {
          unawaited(UserSettingsDocsCache.prefetch(_userDocId));
        }
      });
    });
    // Aviso de nova versão: só no painel Início ([DashboardScreen]), não na barra global.
    // Backup automático: após idle (não compete com o 1º paint).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) unawaited(_checkAutoBackup());
      });
    });
    // PIX pendente: após idle (Cloud Function).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final delay = defaultTargetPlatform == TargetPlatform.android
          ? const Duration(seconds: 8)
          : const Duration(milliseconds: 1800);
      Future<void>.delayed(delay, () {
        if (mounted) _checkPendingPayment(force: true);
      });
    });
    if (kIsWeb) {
      _loadPwaBannerPreference();
      initPwaBeforeInstallPrompt(() {
        Future<void> checkSnoozeAndShow() async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final snoozeUntil = prefs.getInt(_pwaSnoozeKey) ?? 0;
            if (snoozeUntil > DateTime.now().millisecondsSinceEpoch) return;
            if (mounted) setState(() => _showPwaInstallBanner = true);
          } catch (_) {}
        }

        checkSnoozeAndShow();
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showStandaloneWelcomeOnce(),
      );
    }
    // Widget da tela inicial (Android): atualiza próximo plantão e resumo financeiro
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wUid = _profileFirestoreUid;
      if (wUid.isNotEmpty) {
        Future<void>.delayed(const Duration(seconds: 10), () {
          if (!mounted) return;
          unawaited(WidgetDataService.updateWidgetData(wUid));
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _consumeAndroidWidgetIntent(),
    );
    // FCM: registro após idle (não compete com login / 1º paint).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || kIsWeb) return;
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted || kIsWeb) return;
        unawaited(PushNotificationService().inicializar().catchError((_) {}));
      });
    });
    // Notificações locais + sync da agenda: após o 1º frame (fora do caminho crítico).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleDeferredShellBoot();
    });
    _initMobileFirestoreOfflineSync();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadPreferredStartModule(),
    );
    _bindWeeklySummaryListener();
    _shellAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      _bindWeeklySummaryListener();
      if (user != null && user.uid.isNotEmpty) {
        final effective = firestoreUserDocIdStrictFromSession();
        if (effective.isEmpty) return;
        // Evita setState/rebuild do shell inteiro a cada tick de auth (web/Android).
        if (effective == _lastShellAuthEffectiveUid) return;
        _lastShellAuthEffectiveUid = effective;
        unawaited(_loadPreferredStartModule());
        unawaited(
          _scheduleDeferredShellBoot(delay: const Duration(seconds: 4)),
        );
        if (!kIsWeb) {
          final wUid = _profileFirestoreUid;
          if (wUid.isNotEmpty) {
            Future<void>.delayed(const Duration(seconds: 14), () {
              if (!mounted) return;
              unawaited(
                WidgetDataService.updateWidgetData(wUid).catchError((_) {}),
              );
            });
          }
        }
      }
    });
    // Web/PWA: alinhar o token do Firestore à sessão antes das subscrições dos módulos.
    unawaited(
      (() async {
        try {
          final u = FirebaseAuth.instance.currentUser;
          if (u != null) {
            await u.getIdToken(kIsWeb);
          }
        } catch (_) {}
      })(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final o = MediaQuery.orientationOf(context);
    final s = MediaQuery.sizeOf(context).shortestSide;
    if (_orientationForPeak == null) {
      _orientationForPeak = o;
      _peakShortestSide = s;
    } else if (o != _orientationForPeak) {
      _orientationForPeak = o;
      _peakShortestSide = s;
    } else if (s > _peakShortestSide) {
      _peakShortestSide = s;
    }
  }

  /// Cordex: verifica PIX pendente no MP (resolve PIX não atualizar licença no iPhone).
  /// Chamado ao abrir o app e ao retornar do background (usuário paga e volta).
  /// [force] = true ignora throttle (ex.: primeira chamada no init).
  Future<void> _checkPendingPayment({bool force = false}) async {
    if (!force &&
        _lastPendingPaymentCheck != null &&
        DateTime.now().difference(_lastPendingPaymentCheck!) <
            _pendingPaymentThrottle) {
      return;
    }
    _lastPendingPaymentCheck = DateTime.now();
    try {
      final res = await FunctionsService().checkMyPayment();
      if (mounted && (res['activated'] == true)) {
        await AuthService().refreshToken();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DelegateAccessService.revalidateSession());
      // Repõe fila local (iOS ~60 slots): após avisos dispararem, reagenda os próximos eventos.
      if (!kIsWeb) {
        unawaited(PushNotificationService.ensureRegisteredAfterResume());
        // Só dispara avisos já na fila iminente — sem reler 600+ docs do Firestore ao voltar do background.
        ScaleNotificationsService().checkDueNow();
      }
      _checkPendingPayment(force: false);
      _autoConfirmarPlantaoesPassados(showFeedback: false);
      // Mantém sessão e dados atualizados ao voltar do multitarefa / reabrir o ícone (sem logout).
      final u = FirebaseAuth.instance.currentUser;
      u?.getIdToken(true).then((_) {}, onError: (_) {});
      FirebaseFirestore.instance.enableNetwork().catchError((_) {});
      if (!kIsWeb) {
        FirebaseFirestore.instance.waitForPendingWrites().catchError((_) {});
      }
      if (mounted) setState(() {});
    }
  }

  bool _deferredShellBootScheduled = false;

  /// Agenda notificações/sync sem competir com o 1º paint do painel (Android).
  Future<void> _scheduleDeferredShellBoot({
    Duration delay = const Duration(milliseconds: 2800),
  }) {
    if (_deferredShellBootScheduled) return Future<void>.value();
    _deferredShellBootScheduled = true;
    return Future<void>.delayed(delay, () async {
      if (!mounted) return;
      unawaited(ScaleNotificationsService().init());
      final nUid = firestoreUserDocIdStrictFromSession();
      if (nUid.isEmpty) return;
      unawaited(AgendaBootOrchestrator.runOnLogin(nUid));
    });
  }

  /// Descarta módulos antigos do IndexedStack — só mantém atual + anterior (menos streams/Firestore).
  void _retainMaterializedModules(int currentIdx, int previousIdx) {
    final keep = {currentIdx, previousIdx};
    _materializedModuleIndices.removeWhere((idx) => !keep.contains(idx));
    _materializedModuleIndices.add(currentIdx);
  }

  void _setModuleIndex(int i, {VoidCallback? alsoInSetState}) {
    if (!mounted || i < 0 || i >= _kShellModuleCount) return;
    final prev = _idx;
    final needsMaterialize = !_materializedModuleIndices.contains(i);
    setState(() {
      _idx = i;
      alsoInSetState?.call();
      _materializedModuleIndices.add(i);
      if (prev != i) {
        _retainMaterializedModules(i, prev);
      } else if (needsMaterialize &&
          _materializedModuleIndices.length >
              _kMaxRetainedMaterializedModules) {
        _retainMaterializedModules(i, prev);
      }
    });
    if (prev != i) {
      if (i == 9 && _userDocId.isNotEmpty) {
        unawaited(UserSettingsDocsCache.prefetch(_userDocId));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final idx in [prev, i]) {
          final c = _shellModuleScrollControllers[idx];
          if (c.hasClients) c.jumpTo(0);
        }
      });
    }
  }

  void _onMenuSelected(int i) {
    _setModuleIndex(i);
  }

  void _applyCachedPreferredStartModule() {
    if (kIsWeb) {
      final t = Uri.base.queryParameters['tab']?.toLowerCase().trim();
      if (t == 'finance' || t == 'financeiro') {
        _idx = 1;
        _materializedModuleIndices.add(1);
        return;
      }
      if (t == 'escalas' || t == 'escala' || t == 'agenda') {
        _idx = 3;
        _materializedModuleIndices.add(3);
        return;
      }
    }
    final cached = HomeStartModuleCache.getSync(_userDocId);
    if (cached != null && kHomeDefaultStartModuleLabels.containsKey(cached)) {
      _idx = cached;
      _materializedModuleIndices.add(cached);
    }
  }

  Future<void> _loadPreferredStartModule() async {
    if (!_hasFirestoreUid) return;
    if (kIsWeb) {
      final t = Uri.base.queryParameters['tab']?.toLowerCase().trim();
      if (t == 'finance' || t == 'financeiro') {
        if (mounted) _setModuleIndex(1);
        return;
      }
      if (t == 'escalas' || t == 'escala' || t == 'agenda') {
        if (mounted) _setModuleIndex(3);
        return;
      }
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .collection('settings')
          .doc('planning')
          .get(const GetOptions(source: Source.serverAndCache));
      final data = snap.data() ?? <String, dynamic>{};
      final raw = data[kHomeDefaultStartModuleField];
      final preferred = normalizeHomeStartModuleIndex(
        raw is num ? raw.toInt() : 1,
      );
      if (!kHomeDefaultStartModuleLabels.containsKey(preferred)) return;
      if (!mounted) return;
      await HomeStartModuleCache.save(_userDocId, preferred);
      if (_idx != preferred) {
        _setModuleIndex(preferred);
      }
    } catch (_) {
      // Mantém o padrão atual se a leitura da preferência falhar.
    }
  }

  Widget _buildFooterComAtalho() {
    final width = MediaQuery.sizeOf(context).width;
    final footerNarrow = width <= _footerUltraNarrowWidth;
    // Tamanhos responsivos: cresce gradualmente com a largura, sem perder configuração.
    final isUltraNarrow = width < 340;
    final isNarrow = width < 420;
    final isWide = width >= 720;
    final double pillSize =
        isUltraNarrow ? 32 : (isNarrow ? 36 : (isWide ? 42 : 38));
    final double iconBase =
        isUltraNarrow ? 18 : (isNarrow ? 20 : (isWide ? 24 : 22));
    final double labelSize =
        isUltraNarrow ? 9.5 : (isNarrow ? 10.5 : (isWide ? 11.5 : 11));
    final pressScale = kIsWeb ? 0.97 : 0.94;
    final selectedScale = kIsWeb ? 1.06 : 1.08;
    final scaleDuration = Duration(milliseconds: kIsWeb ? 105 : 125);
    final containerDuration = Duration(milliseconds: kIsWeb ? 160 : 175);
    final glowDuration = Duration(milliseconds: kIsWeb ? 150 : 170);

    Widget quickButton({
      required IconData icon,
      required String label,
      required int index,
      required Color accent,
    }) {
      final selected = _idx == index;
      final pressed = _footerPressedIndex == index;
      final accentDark = Color.lerp(accent, Colors.black, 0.20) ?? accent;
      final pillGradient = selected
          ? [accent, accentDark]
          : [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.08)];
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTapDown: (_) => setState(() => _footerPressedIndex = index),
          onTapCancel: () {
            if (_footerPressedIndex == index) {
              setState(() => _footerPressedIndex = null);
            }
          },
          onTapUp: (_) {
            if (_footerPressedIndex == index) {
              setState(() => _footerPressedIndex = null);
            }
          },
          onTap: () => _setModuleIndex(index),
          child: AnimatedScale(
            scale: pressed ? pressScale : (selected ? selectedScale : 1.0),
            duration: scaleDuration,
            curve: pressed ? Curves.easeInOut : Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: containerDuration,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                2,
                isUltraNarrow ? 2 : 3,
                2,
                isUltraNarrow ? 1 : 2,
              ),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: pressed ? 1 : 0,
                        duration: glowDuration,
                        curve: Curves.easeOut,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.2),
                              radius: 1.0,
                              colors: [
                                accent.withValues(alpha: 0.16),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: containerDuration,
                        curve: Curves.easeOutCubic,
                        width: pillSize,
                        height: pillSize,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: pillGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(pillSize / 2.8),
                          border: Border.all(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.55)
                                : accent.withValues(alpha: 0.28),
                            width: selected ? 1.6 : 1.1,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.62),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                    spreadRadius: -2,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.14),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.22),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                        ),
                        child: Center(
                          child: Icon(
                            icon,
                            size: iconBase,
                            color: selected ? Colors.white : accent,
                            shadows: selected
                                ? const [
                                    Shadow(
                                      color: Color(0x55000000),
                                      blurRadius: 3,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : const <Shadow>[],
                          ),
                        ),
                      ),
                      SizedBox(height: isUltraNarrow ? 2 : 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: labelSize,
                          letterSpacing: selected ? 0.25 : 0.08,
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w800,
                          color: selected
                              ? accent
                              : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isUltraNarrow ? 6 : 10,
        0,
        isUltraNarrow ? 6 : 10,
        bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isUltraNarrow ? 3 : 6,
              vertical: isUltraNarrow ? 4 : 5,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                quickButton(
                  icon: Icons.home_rounded,
                  label: 'Início',
                  index: 0,
                  accent: const Color(0xFF3B82F6),
                ),
                quickButton(
                  icon: Icons.account_balance_wallet_rounded,
                  label: footerNarrow ? 'Financ.' : 'Financeiro',
                  index: 1,
                  accent: const Color(0xFF14B8A6),
                ),
                quickButton(
                  icon: Icons.flag_rounded,
                  label: 'Objetivo',
                  index: 2,
                  accent: const Color(0xFFEC4899),
                ),
                quickButton(
                  icon: Icons.calendar_month_rounded,
                  label: 'Agenda',
                  index: 3,
                  accent: const Color(0xFF6366F1),
                ),
                quickButton(
                  icon: Icons.ondemand_video_rounded,
                  label: 'Cursos',
                  index: 7,
                  accent: const Color(0xFF06B6D4),
                ),
              ],
            ),
          ),
          const AppVersionFooter(
            light: false,
            showVerse: true,
            showVersion: false,
            compact: true,
            shellBottomBar: true,
            showOfficialChannels: false,
          ),
        ],
      ),
    );
  }

  Widget _moduleIndexedStack(UserProfile profile) {
    return IndexedStack(
      index: _idx,
      sizing: StackFit.expand,
      children: List<Widget>.generate(_kShellModuleCount, (i) {
        if (!_materializedModuleIndices.contains(i)) {
          if (_idx == i) {
            return const _ShellModuleBootPlaceholder();
          }
          return const SizedBox.shrink();
        }
        return KeyedSubtree(
          key: ValueKey<String>('${_userDocId}_mod_$i'),
          child: _moduleForIndex(i, profile),
        );
      }),
    );
  }

  /// Corpo do módulo ativo — Android: pad isolado (sem rebuild do IndexedStack no Gboard).
  Widget _shellModuleBody(UserProfile profile) {
    return RepaintBoundary(
      child: ClipRect(
        child: KeyedSubtree(
          key: ValueKey<String>(_userDocId),
          child: _moduleIndexedStack(profile),
        ),
      ),
    );
  }

  void Function(int index) _moduleNavigateHandler({
    bool closeOverlayFirst = false,
  }) {
    if (!closeOverlayFirst) return _setModuleIndex;
    return (i) {
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
      _setModuleIndex(i);
    };
  }

  Widget _moduleForIndex(
    int idx,
    UserProfile profile, {
    bool forceModuleActive = false,
  }) {
    final moduleActive = forceModuleActive || _idx == idx;
    final onNav = _moduleNavigateHandler(closeOverlayFirst: forceModuleActive);
    switch (idx) {
      case 0:
        return WisdomDashboardScreen(
          uid: _userDocId,
          profile: profile,
          shellScrollController: _shellModuleScrollControllers[0],
          onNavigateTo: onNav,
        );
      case 1:
        return FinanceScreen(
          uid: _userDocId,
          profile: profile,
          isShellVisible: moduleActive,
          shellScrollController: _shellModuleScrollControllers[1],
          onNavigateTo: onNav,
        );
      case 2:
        return MetaFinanceiraScreen(
          uid: _userDocId,
          profile: profile,
          onNavigateTo: onNav,
        );
      case 3:
        return WisdomAgendaScreen(
          uid: _userDocId,
          profile: profile,
          isShellVisible: moduleActive,
          shellScrollController: _shellModuleScrollControllers[3],
          onNavigateTo: onNav,
        );
      case 4:
        return CalculatorScreen(
          uid: _userDocId,
          profile: profile,
          onNavigateTo: onNav,
        );
      case 5:
        return WisdomDashboardScreen(
          uid: _userDocId,
          profile: profile,
          onlyTips: true,
          shellScrollController: _shellModuleScrollControllers[5],
          onNavigateTo: onNav,
        );
      case 6:
        return ReportsScreen(
          uid: _userDocId,
          profile: profile,
          onNavigateTo: onNav,
        );
      case 7:
        return CursosVideosScreen(
          uid: _userDocId,
          shellScrollController: _shellModuleScrollControllers[7],
        );
      case 8:
        return AnotacoesScreen(
          uid: _userDocId,
          profile: profile,
          onNavigateTo: onNav,
        );
      case 9:
        return SettingsScreen(
          uid: _userDocId,
          userEmail: profile.email,
          userName: profile.name,
          profile: profile,
          showAppBar: false,
          shellScrollController: _shellModuleScrollControllers[9],
          onNavigateTo: onNav,
        );
      default:
        return DashboardScreen(
          uid: _userDocId,
          profile: profile,
          shellScrollController: _shellModuleScrollControllers[0],
          onNavigateTo: onNav,
        );
    }
  }

  Future<void> _autoConfirmarPlantaoesPassados({
    bool showFeedback = true,
  }) async {
    if (!showFeedback) {
      final last = _lastAutoConfirmClientRun;
      if (last != null &&
          DateTime.now().difference(last) < _autoConfirmClientThrottle) {
        return;
      }
      _lastAutoConfirmClientRun = DateTime.now();
    }
    if (_autoConfirmRunning) return;
    _autoConfirmRunning = true;
    try {
      final count = await ScaleAutoConfirmService()
          .autoConfirmarPlantaoesPassados(_userDocId);
      if (showFeedback && count > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count serviço(s) confirmado(s) automaticamente após o horário de término.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
    } finally {
      _autoConfirmRunning = false;
    }
  }

  static const _pwaVisitCountKey = 'pwa_visit_count';
  static const _pwaSnoozeKey = 'pwa_install_snooze_until_ms';

  Future<void> _loadPwaBannerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozeUntil = prefs.getInt(_pwaSnoozeKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      _pwaSnoozeActive = snoozeUntil > now;
      final visitCount = (prefs.getInt(_pwaVisitCountKey) ?? 0) + 1;
      await prefs.setInt(_pwaVisitCountKey, visitCount);
      const minVisits = 2;
      if (mounted &&
          !isPwaStandalone &&
          !_pwaSnoozeActive &&
          visitCount >= minVisits) {
        setState(() => _showPwaInstallBanner = true);
      }
    } catch (_) {}
  }

  /// Mensagem única ao abrir como app instalado (PWA standalone) — reforça sensação de app no celular.
  Future<void> _showStandaloneWelcomeOnce() async {
    if (!kIsWeb || !isPwaStandalone || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyShown =
          prefs.getBool('pwa_standalone_welcome_shown') ?? false;
      if (alreadyShown) return;
      await prefs.setBool('pwa_standalone_welcome_shown', true);
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'WISDOMAPP — aberto como app. Use pelo ícone na tela inicial.',
            ),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    } catch (_) {}
  }

  Future<void> _dismissPwaBanner() async {
    setState(() {
      _showPwaInstallBanner = false;
      _pwaSnoozeActive = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _pwaSnoozeKey,
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
      );
      await prefs.remove('pwa_install_dismissed');
    } catch (_) {}
  }

  Future<void> _checkAutoBackup() async {
    if (!_hasFirestoreUid) return;
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .collection('settings')
          .doc('backup');
      final snap = await ref.get();
      final data = Map<String, dynamic>.from(
        (snap.data ?? <String, dynamic>{}) as Map,
      );
      final enabled = (data['enabled'] ?? false) as bool;
      if (!enabled) return;
      final frequency = (data['frequency'] ?? 'daily') as String;
      final lastRun = (data['lastRunAt'] as Timestamp?)?.toDate();
      final now = DateTime.now();
      final due = lastRun == null ||
          (frequency == 'daily' && now.difference(lastRun).inHours >= 24) ||
          (frequency == 'weekly' && now.difference(lastRun).inDays >= 7);
      if (!due) return;
      final json = await UserBackupService().exportUserDataAsJson(_userDocId);
      final date = now.toIso8601String().substring(0, 10);
      final filename = 'controle-total-backup-$date.json';
      await saveBackupFile(filename, json);
      await ref.set({
        'lastRunAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup automático feito. Envie o arquivo para o seu Google Drive ou nuvem.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      // ignora erros (ex.: sem permissão ou rede)
    }
  }

  void _onDelegateSessionChanged() {
    if (mounted) setState(() {});
  }

  /// Cabeçalho compacto nos módulos (sub-login): titular + autorizado.
  Widget _buildModuleHeaderCenter(
    UserProfile profile, {
    required bool isCompact,
  }) {
    if (_idx == 0) {
      return _buildBarGreetingAndLicense(profile, isCompact: isCompact);
    }
    final titleStyle = TextStyle(
      fontSize: isCompact ? 18.0 : 19.0,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      letterSpacing: 0.2,
    );
    final smallStyle = TextStyle(
      fontSize: isCompact ? 10.5 : 11.0,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: 0.85),
    );
    if (!DelegateAccessService.isActingAsDelegate) {
      return Text(
        _currentModuleTitle(),
        style: titleStyle,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        softWrap: true,
      );
    }
    final ownerEmail = (DelegateAccessService.principalEmail ?? '').trim();
    final sessionEmail = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _currentModuleTitle(),
          style: titleStyle,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        if (ownerEmail.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'Titular: $ownerEmail',
            style: smallStyle,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
        if (sessionEmail.isNotEmpty)
          Text(
            'Autorizado: $sessionEmail',
            style: smallStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
      ],
    );
  }

  @override
  void dispose() {
    DelegateAccessService.sessionRevision.removeListener(
      _onDelegateSessionChanged,
    );
    _weeklySummaryRebindDebounce?.cancel();
    _shellAuthSub?.cancel();
    _weeklySummarySub?.cancel();
    _mobileConnSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _shellModuleScrollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasFirestoreUid) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF2D5BFF), Color(0xFF0D9488)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const SafeArea(
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      );
    }
    final fs = FirestoreService();
    final profileUid = _profileFirestoreUid;
    // Stream em tempo real: ao pagar, o webhook atualiza users/{uid}; o perfil é recalculado e a UI libera sem recarregar.
    return StreamBuilder<UserProfile>(
      stream: fs.watchProfile(profileUid),
      builder: (context, snap) {
        final profile = snap.data ??
            UserProfileStartupCache.getSync(profileUid) ??
            UserProfileStartupCache.getSync(widget.uid);
        if (profile == null) {
          return Scaffold(
            body: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1A237E),
                    Color(0xFF2D5BFF),
                    Color(0xFF0D9488),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const SafeArea(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          );
        }
        if (snap.hasData) {
          unawaited(UserProfileStartupCache.save(profileUid, snap.data!));
        }

        // Telemetria leve — uma vez por sessão/uid (evita postFrame a cada rebuild do perfil).
        if (_telemetryPingScheduledForUid != profileUid) {
          _telemetryPingScheduledForUid = profileUid;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(UserClientTelemetryService.pingIfDue(profileUid));
          });
        }

        // Hard Lock: bloqueio total se licença expirada + carência ultrapassada
        if (profile.isPastGracePeriod &&
            profile.licenseExpiresAt != null &&
            !profile.isAdmin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/licenca-expirada', (route) => false);
            }
          });
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        if (profile.hasActiveLicense && !_onboardingChecked) {
          _onboardingChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final shouldShow = await OnboardingScreen.shouldShow();
            if (mounted && shouldShow) {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => OnboardingScreen(
                    onComplete: () async {
                      await OnboardingScreen.markDone();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ),
              );
            }
            if (!mounted) return;
            final prefs = await SharedPreferences.getInstance();
            if (!(prefs.getBool('welcome_first_shown') ?? false)) {
              prefs.setBool('welcome_first_shown', true);
              if (!mounted) return;
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Bem-vindo ao WISDOMAPP!'),
                  content: const Text(
                    'Nos primeiros ${UserProfile.newUserTrialDays} dias você tem acesso livre total: pelo celular, computador ou notebook (wisdomapp-b9e98.web.app). Sabedoria financeira com princípios bíblicos. Qualquer dúvida, use Configurações → Suporte.',
                    style: TextStyle(height: 1.4),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Entendi'),
                    ),
                  ],
                ),
              );
            }
          });
        }

        // Hard Lock: tratado pelo LicenseGate — redireciona para /licenca-expirada.

        // Sem licença ativa (e não está em carência): ex. usuário free ou sem assinatura.
        // Layout responsivo: SafeArea + scroll para iPhone/Android (todas as versões).
        if (!profile.hasActiveLicense && !profile.isAdmin) {
          final padding = MediaQuery.paddingOf(context);
          final size = MediaQuery.sizeOf(context);
          final horizontalPadding = size.width < 360 ? 20.0 : 32.0;
          final viewHeight = size.height - padding.top - padding.bottom;
          final minHeight = viewHeight > 0 ? viewHeight : 400.0;
          final isDelegate = DelegateAccessService.isActingAsDelegate;
          final titularEmail =
              (DelegateAccessService.principalEmail ?? profile.email).trim();
          return Scaffold(
            appBar: AppBar(title: const Text('WISDOMAPP')),
            body: SafeArea(
              top: false,
              bottom: true,
              left: true,
              right: true,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      24,
                      horizontalPadding,
                      24 + padding.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 64,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isDelegate
                              ? 'Licença do titular bloqueada'
                              : (profile.isLicenseExpired
                                  ? 'Licença vencida'
                                  : 'Acesso bloqueado'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isDelegate
                              ? 'A licença de ${titularEmail.isNotEmpty ? titularEmail : 'quem autorizou seu acesso'} está vencida ou sem pagamento. '
                                  'Você fica bloqueado até o titular renovar — quando pagar, seu acesso volta automaticamente.'
                              : (profile.isLicenseExpired
                                  ? 'Sua licença expirou. Renove agora para continuar usando o WISDOMAPP.'
                                  : 'Assine um plano para acessar o sistema.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (!isDelegate)
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: () {
                                IosPaymentsGate.pushEscolhaPlano(context);
                              },
                              icon: const Icon(Icons.upgrade_rounded, size: 22),
                              label: Text(
                                profile.isLicenseExpired
                                    ? 'Renovar licença'
                                    : 'Ver planos',
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                minimumSize: const Size(0, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                backgroundColor: AppColors.primary,
                              ),
                            ),
                          ),
                        if (!isDelegate) const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: TextButton.icon(
                            onPressed: () =>
                                AccountSwitchFlow.confirmAndOpenLogin(context),
                            icon: const Icon(
                              Icons.switch_account_rounded,
                              size: 20,
                            ),
                            label: const Text('Trocar de conta'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 48),
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

        // Índices: 0=Início, 1=Financeiro, 2=(legado→Financeiro), 3=Agenda, 4=Calculadora,
        // 5=Dicas, 6=Relatórios, 7=Cursos, 8=Minhas Anotações, 9=Configurações
        // [IndexedStack] mantém estado dos módulos já abertos; só materializamos índices visitados ([_materializedModuleIndices]).

        // Lado mais curto: usa pico na orientação atual para o IME não alternar mobile/tablet a cada frame.
        final peak = _peakShortestSide > 0
            ? _peakShortestSide
            : MediaQuery.sizeOf(context).shortestSide;
        final isMobile = peak < _mobileBreakpoint;

        if (isMobile) {
          final padding = MediaQuery.paddingOf(context);
          return _wrapShellWithGlobalMessages(
            OnboardingTour(
              child: PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) {
                    // Tecla Voltar Android: na tela inicial não faz nada; em outro módulo volta para a tela inicial. Nunca sai do app (só por Logout).
                    if (_idx != 0) {
                      _setModuleIndex(0);
                    }
                  }
                },
                child: Scaffold(
                  key: _scaffoldKey,
                  // Android/iOS: resize nativo do Scaffold (modelo Gestão Yahweh — teclado instantâneo).
                  resizeToAvoidBottomInset: useNativeScaffoldKeyboardResize,
                  drawer: _buildDrawer(profile),
                  body: OrientationBuilder(
                    builder: (context, orientation) {
                      return SafeArea(
                        top: true,
                        bottom: false,
                        left: true,
                        right: true,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // iPhone 14/15/16: constraints às vezes vêm 0 no primeiro frame em portrait; evita layout quebrado.
                            final maxW = constraints.maxWidth > 0
                                ? constraints.maxWidth
                                : 390.0;
                            final maxH = constraints.maxHeight > 0
                                ? constraints.maxHeight
                                : 844.0;
                            final hasRealSize = constraints.maxWidth > 1 &&
                                constraints.maxHeight > 1;
                            // IME só no miolo (Expanded): animar teclado não rebuilda header/banners/rodapé a cada frame.
                            final shellCol = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              // max: preenche a altura útil — com min + Expanded o hit-test podia ficar deslocado até rotacionar.
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                if (kIsWeb &&
                                    !_pwaSnoozeActive &&
                                    !isPwaStandalone &&
                                    (_showPwaInstallBanner || isPwaIos))
                                  InstallPwaCard(
                                    visible: true,
                                    onDismiss: _dismissPwaBanner,
                                  ),
                                if (kIsWeb &&
                                    Uri.base.queryParameters[
                                            'payment_success'] ==
                                        '1' &&
                                    !_paymentSuccessBannerDismissed &&
                                    profile.licenseExpiresAt != null)
                                  _PaymentSuccessBanner(
                                    profile: profile,
                                    licenseExpiresAt: profile.licenseExpiresAt!,
                                    onDismiss: () => setState(
                                      () =>
                                          _paymentSuccessBannerDismissed = true,
                                    ),
                                  ),
                                if (profile.isInGracePeriod)
                                  const _GracePeriodBanner(),
                                if (!profile.hasActiveLicense)
                                  _ReadOnlyBanner(
                                    isLicenseExpired: profile.isLicenseExpired,
                                  ),
                                if (profile.licenseExpiresAt != null &&
                                    profile.licenseExpiresAt!.isAfter(
                                      DateTime.now(),
                                    ))
                                  _LicenseBanner(
                                    licenseExpiresAt: profile.licenseExpiresAt!,
                                    plan: profile.plan,
                                  ),
                                // Barra superior: alvo de toque mínimo 48px (tema + style explícito para iPhone/Android)
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.deepBlueDark,
                                        AppColors.deepBlue,
                                        AppColors.accent,
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.deepBlueDark
                                            .withValues(alpha: 0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: SafeArea(
                                    bottom: false,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          IconButton(
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              tapTargetSize:
                                                  MaterialTapTargetSize.padded,
                                            ),
                                            icon: Icon(
                                              _idx == 0
                                                  ? Icons.menu_rounded
                                                  : Icons.arrow_back_rounded,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                            onPressed: () {
                                              if (_idx == 0) {
                                                _scaffoldKey.currentState
                                                    ?.openDrawer();
                                              } else {
                                                _setModuleIndex(0);
                                              }
                                            },
                                          ),
                                          Expanded(
                                            child: _buildModuleHeaderCenter(
                                              profile,
                                              isCompact: true,
                                            ),
                                          ),
                                          if (!DelegateAccessService
                                              .isActingAsDelegate)
                                            Semantics(
                                              label:
                                                  'Adquirir plano Premium com PIX ou cartão',
                                              child: IconButton(
                                                style: IconButton.styleFrom(
                                                  minimumSize: const Size(
                                                    48,
                                                    48,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .padded,
                                                ),
                                                icon: const Icon(
                                                  Icons.pix_rounded,
                                                  size: 22,
                                                  color: Colors.white,
                                                ),
                                                tooltip:
                                                    'Adquirir plano Premium',
                                                onPressed: () => IosPaymentsGate
                                                    .pushEscolhaPlano(
                                                  context,
                                                ),
                                              ),
                                            ),
                                          if (profile.canAccessAdminPanel)
                                            IconButton(
                                              style: IconButton.styleFrom(
                                                minimumSize: const Size(48, 48),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .padded,
                                              ),
                                              icon: const Icon(
                                                Icons
                                                    .admin_panel_settings_rounded,
                                                size: 22,
                                                color: Colors.white,
                                              ),
                                              onPressed: () => openAdminPanel(
                                                context,
                                                uid: _userDocId,
                                                profile: profile,
                                              ),
                                            ),
                                          IconButton(
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              tapTargetSize:
                                                  MaterialTapTargetSize.padded,
                                            ),
                                            icon: const Icon(
                                              Icons.logout_rounded,
                                              size: 22,
                                              color: Colors.white,
                                            ),
                                            onPressed: () => AccountSwitchFlow
                                                .confirmAndOpenLogin(
                                              context,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (kIsWeb) _OfflineBanner(),
                                // Expanded = ocupa o espaço restante (equivalente a Flexible + Spacer). Funciona em pé e deitado.
                                Expanded(child: _shellModuleBody(profile)),
                                _buildFooterComAtalho(),
                              ],
                            );
                            final shell = Stack(
                              clipBehavior: Clip.none,
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(child: shellCol),
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: padding.bottom + 72,
                                  child: const FloatingShellBanners(),
                                ),
                              ],
                            );
                            return RepaintBoundary(
                              child: hasRealSize
                                  ? SizedBox.expand(child: shell)
                                  : SizedBox(
                                      width: maxW,
                                      height: maxH,
                                      child: shell,
                                    ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        }

        return _wrapShellWithGlobalMessages(
          OnboardingTour(
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) {
                  // Tecla Voltar: na tela inicial não faz nada; em outro módulo volta para a tela inicial. Nunca sai do app (só por Logout).
                  if (_idx != 0) {
                    _setModuleIndex(0);
                  }
                }
              },
              child: Scaffold(
                resizeToAvoidBottomInset: useNativeScaffoldKeyboardResize,
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UserMenuLateral(
                      uid: _userDocId,
                      selectedIndex: _idx,
                      onItemSelected: _onMenuSelected,
                      isCollapsed: _menuCollapsed,
                      onHomeStartModuleSaved: _setModuleIndex,
                    ),
                    Expanded(
                      child: Stack(
                        clipBehavior: Clip.none,
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Barra superior padronizada: botão voltar (ou menu no Início) + título do módulo
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.deepBlueDark,
                                        AppColors.deepBlue,
                                        AppColors.accent,
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.deepBlueDark
                                            .withValues(alpha: 0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: SafeArea(
                                    bottom: false,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              _idx == 0
                                                  ? (_menuCollapsed
                                                      ? Icons.menu
                                                      : Icons.menu_open)
                                                  : Icons.arrow_back_rounded,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                            onPressed: () {
                                              if (_idx == 0) {
                                                setState(
                                                  () => _menuCollapsed =
                                                      !_menuCollapsed,
                                                );
                                              } else {
                                                _setModuleIndex(0);
                                              }
                                            },
                                          ),
                                          Expanded(
                                            child: _buildModuleHeaderCenter(
                                              profile,
                                              isCompact: false,
                                            ),
                                          ),
                                          if (!DelegateAccessService
                                              .isActingAsDelegate) ...[
                                            OutlinedButton.icon(
                                              onPressed: () => IosPaymentsGate
                                                  .pushEscolhaPlano(
                                                context,
                                              ),
                                              icon: const Icon(
                                                Icons.pix_rounded,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                              label: const Text(
                                                'Planos',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: const BorderSide(
                                                  color: Colors.white,
                                                  width: 1.5,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                                minimumSize: Size.zero,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          if (profile.canAccessAdminPanel)
                                            IconButton(
                                              icon: const Icon(
                                                Icons
                                                    .admin_panel_settings_rounded,
                                                color: Colors.white,
                                              ),
                                              onPressed: () => openAdminPanel(
                                                context,
                                                uid: _userDocId,
                                                profile: profile,
                                              ),
                                            ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.logout_rounded,
                                              color: Colors.white,
                                            ),
                                            onPressed: () => AccountSwitchFlow
                                                .confirmAndOpenLogin(
                                              context,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (kIsWeb &&
                                    !_pwaSnoozeActive &&
                                    !isPwaStandalone &&
                                    (_showPwaInstallBanner || isPwaIos))
                                  InstallPwaCard(
                                    visible: true,
                                    onDismiss: _dismissPwaBanner,
                                  ),
                                if (kIsWeb &&
                                    Uri.base.queryParameters[
                                            'payment_success'] ==
                                        '1' &&
                                    !_paymentSuccessBannerDismissed &&
                                    profile.licenseExpiresAt != null)
                                  _PaymentSuccessBanner(
                                    profile: profile,
                                    licenseExpiresAt: profile.licenseExpiresAt!,
                                    onDismiss: () => setState(
                                      () =>
                                          _paymentSuccessBannerDismissed = true,
                                    ),
                                  ),
                                if (!profile.hasActiveLicense)
                                  _ReadOnlyBanner(
                                    isLicenseExpired: profile.isLicenseExpired,
                                  ),
                                if (profile.licenseExpiresAt != null &&
                                    profile.licenseExpiresAt!.isAfter(
                                      DateTime.now(),
                                    ))
                                  _LicenseBanner(
                                    licenseExpiresAt: profile.licenseExpiresAt!,
                                    plan: profile.plan,
                                  ),
                                if (kIsWeb) _OfflineBanner(),
                                Expanded(
                                  child: RepaintBoundary(
                                    child: SafeArea(
                                      left: false,
                                      right: false,
                                      child: Padding(
                                        padding: EdgeInsets.zero,
                                        child: KeyedSubtree(
                                          key: ValueKey<String>(_userDocId),
                                          child: _moduleIndexedStack(profile),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                _buildFooterComAtalho(),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: MediaQuery.paddingOf(context).bottom + 68,
                            child: const FloatingShellBanners(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Diálogo central de manutenção/promo (overlay) + fila versão/in-app — ativo em qualquer módulo.
  Widget _wrapShellWithGlobalMessages(Widget child) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: PremiumGlobalMessageHost(uid: _userDocId),
          ),
        ),
      ],
    );
  }

  Color _drawerModuleAccent(int moduleIndex) {
    switch (moduleIndex) {
      case 0:
        return const Color(0xFF93C5FD);
      case 1:
        return const Color(0xFF5EEAD4);
      case 2:
        return const Color(0xFFEC4899);
      case 3:
        return const Color(0xFFA5B4FC);
      case 4:
        return const Color(0xFFFDBA74);
      case 5:
        return const Color(0xFFC4B5FD);
      case 6:
        return const Color(0xFF86EFAC);
      case 7:
        return const Color(0xFF22D3EE);
      case 8:
        return const Color(0xFF7DD3FC);
      case 9:
        return const Color(0xFFCBD5E1);
      default:
        return Colors.white70;
    }
  }

  Widget _buildDrawer(UserProfile profile) {
    const items = [
      (0, Icons.home_rounded, 'Início'),
      (1, Icons.account_balance_wallet_rounded, 'Financeiro'),
      (2, Icons.flag_rounded, 'Objetivo Financeiro'),
      (3, Icons.event_note_rounded, 'Agenda'),
      (5, Icons.lightbulb_outline_rounded, 'Dicas Financeiras'),
      (7, Icons.ondemand_video_rounded, 'Cursos em Vídeo'),
    ];
    return Drawer(
      backgroundColor: AppColors.deepBlueDark,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // iPhone 14/15/16 retrato: ao abrir o menu, constraints às vezes vêm 0; evita conteúdo quebrado sem virar o telefone.
          final w = constraints.maxWidth > 0 ? constraints.maxWidth : 320.0;
          final h = constraints.maxHeight > 0 ? constraints.maxHeight : 700.0;
          return RepaintBoundary(
            child: SafeArea(
              child: SizedBox(
                width: w,
                height: h,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/images/icon.png',
                            height: 40,
                            width: 40,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.apps_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'WISDOMAPP',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.alternate_email_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  profile.email.trim().isEmpty
                                      ? 'E-mail não disponível'
                                      : profile.email.trim(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    height: 1.25,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.workspace_premium_rounded,
                                size: 18,
                                color: Colors.amber.shade200,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  profile.planDisplayLabelForUi,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    height: 1.25,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (profile.licenseExpiresAt != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Válido até ${profile.licenseExpiresAt!.day.toString().padLeft(2, '0')}/${profile.licenseExpiresAt!.month.toString().padLeft(2, '0')}/${profile.licenseExpiresAt!.year}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    if (!profile.profileComplete)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        minVerticalPadding: 12,
                        leading: Icon(
                          Icons.person_add_rounded,
                          size: 24,
                          color: AppColors.amber,
                        ),
                        title: const Text(
                          'Completar meus dados',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: const Text(
                          'CPF e outros dados (opcional)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CompleteProfileScreen(
                                uid: _userDocId,
                                currentEmail: profile.email,
                                currentName: profile.name,
                              ),
                            ),
                          );
                        },
                      ),
                    if (!profile.profileComplete)
                      Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    if (!DelegateAccessService.isActingAsDelegate)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        minVerticalPadding: 12,
                        leading: Icon(
                          Icons.pix_rounded,
                          size: 24,
                          color: AppColors.amber,
                        ),
                        title: const Text(
                          'Adquirir plano Premium',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'PIX ou cartão',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          IosPaymentsGate.pushEscolhaPlano(context);
                        },
                      ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      minVerticalPadding: 12,
                      leading: Icon(
                        Icons.settings_rounded,
                        size: 24,
                        color: _idx == 9 ? AppColors.amber : Colors.white70,
                      ),
                      title: Text(
                        'Configurações',
                        style: TextStyle(
                          color: _idx == 9 ? AppColors.amber : Colors.white,
                          fontWeight:
                              _idx == 9 ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Backup, notificações e preferências',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      selected: _idx == 9,
                      selectedTileColor: Colors.white.withValues(alpha: 0.08),
                      onTap: () {
                        _setModuleIndex(9);
                        Navigator.of(context).pop();
                      },
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final item in items)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              minVerticalPadding: 12,
                              leading: Icon(
                                item.$2,
                                size: 24,
                                color: _idx == item.$1
                                    ? AppColors.amber
                                    : _drawerModuleAccent(item.$1),
                              ),
                              title: Text(
                                item.$3,
                                maxLines: item.$1 == 7 ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: item.$1 == 7 ? 13 : 16,
                                  height: item.$1 == 7 ? 1.2 : 1.05,
                                  fontWeight: _idx == item.$1
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _idx == item.$1
                                      ? AppColors.amber
                                      : Colors.white,
                                ),
                              ),
                              selected: _idx == item.$1,
                              selectedTileColor: Colors.white.withValues(
                                alpha: 0.08,
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                final idx = item.$1;
                                final shortSide = MediaQuery.sizeOf(
                                  context,
                                ).shortestSide;
                                final isMobile = shortSide < _mobileBreakpoint;
                                // Rodapé = shell; menu = fullscreen com o mesmo módulo/dados.
                                if (isMobile &&
                                    _footerQuickAccessModuleIndices.contains(
                                      idx,
                                    )) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      fullscreenDialog: true,
                                      builder: (_) => _FullscreenModuleWrapper(
                                        title: item.$3,
                                        child: KeyedSubtree(
                                          key: ValueKey<String>(
                                            '${_userDocId}_menu_$idx',
                                          ),
                                          child: _moduleForIndex(
                                            idx,
                                            profile,
                                            forceModuleActive: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                } else {
                                  _setModuleIndex(idx);
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Botão Voltar (ícone + texto) — wrapper fullscreen acionado pelo menu lateral.
Widget _buildVoltarButtonFullscreen(BuildContext context) {
  return Semantics(
    label: 'Voltar',
    button: true,
    child: InkWell(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 24, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'Voltar',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Fullscreen no mobile quando o módulo é aberto pelo menu (mesmos dados do rodapé).
class _FullscreenModuleWrapper extends StatelessWidget {
  final String title;
  final Widget child;

  const _FullscreenModuleWrapper({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final leadingW = MediaQuery.textScalerOf(
      context,
    ).scale(92).clamp(88.0, 168.0);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: leadingW,
        leading: _buildVoltarButtonFullscreen(context),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        left: true,
        right: true,
        child: child,
      ),
    );
  }
}

/// Subtítulo no header quando a licença está vencida: mensagem em vermelho + link para renovar.
class _LicenseExpiredSubtitle extends StatelessWidget {
  final VoidCallback onTap;

  const _LicenseExpiredSubtitle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: RichText(
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        text: TextSpan(
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          children: [
            const TextSpan(
              text: 'Licença vencida. ',
              style: TextStyle(
                color: Color(0xFFFF6B6B),
                fontWeight: FontWeight.w800,
              ),
            ),
            const TextSpan(
              text:
                  'Não fique sem usar o WISDOMAPP, renove agora sua licença ',
            ),
            TextSpan(
              text: 'clicando aqui',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
              recognizer: TapGestureRecognizer()..onTap = onTap,
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

class _PaymentSuccessBanner extends StatelessWidget {
  final UserProfile profile;
  final DateTime licenseExpiresAt;
  final VoidCallback onDismiss;

  const _PaymentSuccessBanner({
    required this.profile,
    required this.licenseExpiresAt,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final planLabel = profile.planDisplayLabelForUi;
    final venc =
        '${licenseExpiresAt.day.toString().padLeft(2, '0')}/${licenseExpiresAt.month.toString().padLeft(2, '0')}/${licenseExpiresAt.year}';

    return Material(
      color: AppColors.success.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Licença $planLabel ativada com sucesso.',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Vencimento da licença: $venc.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner durante os 3 dias de carência: licença venceu mas usuário ainda pode usar e renovar.
class _GracePeriodBanner extends StatelessWidget {
  const _GracePeriodBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amber.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              color: Colors.orange.shade800,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Período de carência (3 dias). Renove agora para não perder o acesso ao sistema.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            if (!DelegateAccessService.isActingAsDelegate)
              FilledButton(
                onPressed: () {
                  IosPaymentsGate.pushEscolhaPlano(context);
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: const Size(48, 44),
                  backgroundColor: AppColors.primary,
                ),
                child: const Text(
                  'Renovar',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Banner quando licença venceu ou nunca assinou: modo somente visualização.
class _ReadOnlyBanner extends StatelessWidget {
  final bool isLicenseExpired;

  const _ReadOnlyBanner({this.isLicenseExpired = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.error.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: AppColors.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isLicenseExpired
                    ? 'Licença vencida. Você pode visualizar, mas não lançar receitas, despesas, escalas, ocorrências nem emitir relatórios. Renove para continuar.'
                    : 'Modo somente visualização. Assine o plano Premium para lançar e emitir relatórios.',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            if (!DelegateAccessService.isActingAsDelegate)
              FilledButton(
                onPressed: () {
                  IosPaymentsGate.pushEscolhaPlano(context);
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: const Size(48, 44),
                  backgroundColor: AppColors.primary,
                ),
                child: Text(
                  isLicenseExpired ? 'Renovar' : 'Assinar',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Aviso de validade da licença; aparece uma vez, OK some; só volta se licença vencer e renovar.
class _LicenseBanner extends StatefulWidget {
  final DateTime licenseExpiresAt;
  final String plan;

  const _LicenseBanner({required this.licenseExpiresAt, required this.plan});

  @override
  State<_LicenseBanner> createState() => _LicenseBannerState();
}

class _LicenseBannerState extends State<_LicenseBanner> {
  static const _prefsKey = 'license_valid_banner_dismissed_expiry';
  bool _dismissed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey) ?? '';
      final current =
          '${widget.licenseExpiresAt.year}-${widget.licenseExpiresAt.month}-${widget.licenseExpiresAt.day}';
      if (mounted)
        setState(() {
          _dismissed = saved == current;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onDismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        '${widget.licenseExpiresAt.year}-${widget.licenseExpiresAt.month}-${widget.licenseExpiresAt.day}',
      );
      if (mounted) setState(() => _dismissed = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final licenseExpiresAt = widget.licenseExpiresAt;
    final now = DateTime.now();
    final daysLeft = licenseExpiresAt.difference(now).inDays;
    final nearExpiry = daysLeft <= 7 && daysLeft >= 0;
    if (nearExpiry) {
      // Perto do vencimento: sempre mostra; não usa dismiss
      return Material(
        color: AppColors.amber.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade800,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Não fique sem usar seu WISDOMAPP. Renove sua licença.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              if (!DelegateAccessService.isActingAsDelegate) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        IosPaymentsGate.pushEscolhaPlano(context);
                      },
                      child: const Text(
                        'Escolher outro plano',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        IosPaymentsGate.pushEscolhaPlano(context);
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        minimumSize: const Size(48, 44),
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text(
                        'Renovar (PIX ou Cartão)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (_loading || _dismissed) return const SizedBox.shrink();
    final msg =
        'Licença válida até ${licenseExpiresAt.day.toString().padLeft(2, '0')}/${licenseExpiresAt.month.toString().padLeft(2, '0')}/${licenseExpiresAt.year}.';
    return Material(
      color: AppColors.success.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
            FilledButton(
              onPressed: _onDismiss,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                minimumSize: const Size(48, 44),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner quando o dispositivo está offline (**somente web**).
/// No Android/iOS o Firestore já grava na fila local e sincroniza sozinho — sem faixa intrusiva.
class _OfflineBanner extends StatefulWidget {
  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> result,
    ) {
      if (mounted) setState(() => _offline = _isOffline(result));
    });
  }

  Future<void> _check() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _offline = _isOffline(result));
    } catch (_) {}
  }

  static bool _isOffline(List<ConnectivityResult> result) {
    if (result.isEmpty) return true;
    return result.every((r) => r == ConnectivityResult.none);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_offline) return const SizedBox.shrink();
    return Material(
      color: Colors.orange.shade800,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Você está offline. Verifique a conexão.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder leve enquanto o módulo pesado materializa (evita tela branca no Android).
class _ShellModuleBootPlaceholder extends StatelessWidget {
  const _ShellModuleBootPlaceholder();

  static const Color _bg = Color(0xFFF4F7FA);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _bg,
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}
