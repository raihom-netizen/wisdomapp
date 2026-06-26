import 'dart:async';

import '../constants/finance_bank_presets.dart';
import '../constants/finance_account_visuals.dart';
import '../constants/finance_export_limits.dart';
import '../models/finance_account.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import 'categories_config_screen.dart';
import 'finance_accounts_screen.dart';
import 'finance_bulk_assign_screen.dart';
import '../utils/finance_export_csv.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:file_picker/file_picker.dart';
import '../constants/currency_formats.dart';
import '../models/user_profile.dart';
import '../services/user_categories_service.dart';
import '../services/logs_service.dart';
import '../services/functions_service.dart';
import '../services/transaction_save_service.dart';
import '../theme/app_colors.dart';
import '../widgets/skeleton_loader.dart';
import '../utils/premium_upgrade.dart';
import '../utils/firestore_query_batched_collect.dart';
import '../utils/friendly_error.dart';
import 'novo_lancamento_page.dart';
import '../models/smart_input_pop_result.dart';
import '../services/finance_opening_balance_service.dart';
import '../services/finance_service.dart';
import 'smart_input_screen.dart';
import 'despesas_fixas_screen.dart';
import 'receitas_fixas_screen.dart';
import 'anexo_viewer_screen.dart';
import '../services/fixed_expense_preferences_service.dart';
import '../services/fixed_income_preferences_service.dart';
import '../services/fixed_expense_service.dart';
import '../services/fixed_income_service.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/finance_period_summary.dart';
import '../utils/home_shell_layout.dart';
import '../utils/finance_main_period_server.dart';
import '../utils/finance_insight_query.dart';
import '../utils/finance_transactions_realtime.dart';
import '../widgets/finance_sparkline.dart';
import '../widgets/brl_amount_text_field.dart';
import '../constants/finance_category_visuals.dart';
import '../widgets/finance_category_picker.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/receipt_attachment_utils.dart';
import '../constants/finance_tips.dart';
import '../constants/app_strings.dart';
import '../constants/app_business_rules.dart';
import '../services/first_time_hint_service.dart';
import 'package:intl/intl.dart';
import '../constants/date_time_formats.dart';
import '../services/relatorio_service.dart';
import 'report_preview_screen.dart';
import '../utils/date_picker_a11y.dart';
import '../widgets/app_pie_chart.dart';
import '../widgets/finance_account_category_sheet.dart';
import '../widgets/finance_smart_tips_insight.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import '../services/finance_transfer_service.dart';
import '../widgets/finance_transfer_bottom_sheet.dart';
import '../widgets/finance_transaction_edit_dialog.dart';
import '../widgets/finance_transaction_list_tile.dart';
import '../utils/finance_fatura_transaction_sort.dart';
import '../widgets/finance_transaction_sort_bar.dart';
import 'finance_transactions_fullscreen_page.dart';
import 'finance_categories_fullscreen_page.dart';
import 'finance_assistant_insights_page.dart';
import '../services/delegate_access_service.dart';
import '../utils/firestore_user_doc_id.dart' show firestoreUserDocIdForAppShell, firestoreUserDocIdStrictFromSession;
import '../utils/finance_category_grouping.dart';
import '../utils/finance_shell_navigation.dart';
import '../utils/finance_transactions_hub.dart';
import '../widgets/finance_premium_ui.dart';
import '../widgets/light_filter_picker.dart';
import '../widgets/finance_confirm_payment_sheet.dart';
import '../widgets/finance_credit_card_fatura_sheet.dart';
import '../widgets/finance_fatura_em_aberto_hub.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/pdf_financeiro_super_extrato.dart';

class FinanceScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;
  /// Shell: false quando outro módulo está ativo — pausa streams e acelera o app.
  final bool isShellVisible;
  /// Scroll da lista principal — o shell faz [jumpTo(0)] ao entrar/sair do Financeiro.
  final ScrollController? shellScrollController;

  const FinanceScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.onNavigateTo,
    this.isShellVisible = true,
    this.shellScrollController,
  });

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  static const Color _kPdfActionOrange = Color(0xFFEA580C);

  /// Filtro de período simples: Mensal, Anual ou Por período.
  static const List<String> _periods = ['Mensal', 'Anual', 'Por período'];
  String _selectedPeriod = 'Mensal';
  DateTime? _customRangeStart;
  DateTime? _customRangeEnd;

  /// Datas do período atual (inicializadas em sync com Anual).
  late DateTime _from;
  late DateTime _to;

  /// Padrão: despesas pagas e receitas recebidas (usuário pode alterar para Todos/Pendente).
  String _statusFilter = 'paid';
  /// `all` | `income` | `expense` — filtra a lista e os totais do período na tela.
  String _typeFilter = 'all';
  /// Filtro rápido da grid principal: Todos / Despesas / Receitas (só visualização).
  String _gridListTypeFilter = 'all';
  FinanceFaturaTxSortMode _gridSortMode = FinanceFaturaTxSortMode.dateDesc;
  String? _categoryFilter;
  late Future<List<String>> _categoryFilterOptionsFuture;
  bool _categoryFilterOptionsPrimed = false;
  String _search = '';
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounceTimer;
  /// true = cabeçalho premium + botões; false = só barra compacta (mais espaço para a lista).
  bool _topoExpandido = false;
  /// Período, status e pesquisa — inicia fechado a cada entrada no módulo (novo State ao trocar de aba).
  bool _filtrosPainelAberto = false;
  /// IDs com confirmação otimista: UI mostra "Pago" na hora; gravação em segundo plano.
  final Set<String> _optimisticPaidIds = {};
  /// Patch otimista de edição por docId (evita sensação de lentidão ao salvar).
  final Map<String, Map<String, dynamic>> _optimisticEditedTxById = {};
  Timer? _delayedMainPeriodReloadTimer;
  /// Força refresh das faixas de pendentes após mudança remota (debounced).
  /// Cache do saldo de abertura por período (igual painel e relatórios).
  String _saldoAberturaKey = '';
  /// Saldo em memória — evita FutureBuilder piscar (valor estável + refresh suave).
  ({double total, Map<String, double> byAccount})? _saldoAberturaCached;
  /// Modo seleção na grid de lançamentos: permite excluir vários de uma vez.
  bool _gridSelectionMode = false;
  final Set<String> _gridSelectedIds = {};
  StreamSubscription<List<FinanceAccount>>? _financeAccSub;
  List<FinanceAccount> _financeAccounts = [];
  /// null = lista completa; id = só lançamentos daquela conta.
  String? _financeAccountFilterId;
  StreamSubscription<bool>? _stripHideZeroSub;
  bool _stripHideZeroBalances = false;
  bool _financeAccountsStreamPrimed = false;
  /// Lista principal: evita renderizar milhares de cards de uma vez.
  static const int _txPageSize = 150;
  int _txDisplayLimit = _txPageSize;
  /// Força nova subscrição ao `snapshots()` (ex.: após erro, ou mudança de plano/PRO).
  int _txStreamRetryKey = 0;
  /// Carregamento do período em páginas (lista principal — não bloqueia até ao último batch).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mainPeriodDocs = [];
  bool _mainPeriodLoading = true;
  /// Barra «A sincronizar…» só no pull-to-refresh explícito (não em mutações nem sync em background).
  bool _mainPeriodPullRefreshing = false;
  Object? _mainPeriodLoadError;
  int _mainPeriodLoadedCount = 0;
  String _mainPeriodScheduledLoadKey = '';
  int _mainPeriodLoadGeneration = 0;
  /// Lista com menos dados na rede: [limit] + [startAfter] quando filtros cabem em [where] no Firestore.
  static const int _kMainPeriodFirestorePageSize = 200;
  DocumentSnapshot<Map<String, dynamic>>? _mainPeriodFirestoreCursor;
  bool _mainPeriodHasMoreServer = false;
  bool _mainPeriodServerPagingActive = false;
  ({double income, double expense})? _mainPeriodServerKpis;
  ({double income, double expense})? _periodMergedKpis;
  bool _mainPeriodLoadingMore = false;
  /// Lista principal paginada no Firestore: só ~200 docs em memória — saldos por
  /// conta precisam de leitura completa do período (batched) para bater com os lançamentos.
  Map<String, double> _serverPagingStripPaidNetByAccount = const {};
  int _serverPagingStripNetForGen = -1;
  /// Chave período+filtros — só zera KPIs/saldos por conta quando isto muda (não no pull-to-refresh).
  String _financeBalanceContextKeyApplied = '';
  StreamSubscription<fa.User?>? _authStateSub;
  /// Evita abrir streams de contas antes de [FirebaseAuth] ter `currentUser` (regras exigem `request.auth`).
  bool _financeUserStreamsBound = false;
  /// Último uid com que as subscrições de contas foram abertas (troca de conta = reabrir).
  String? _lastBoundFinanceAuthUid;
  String? _lastBoundFinanceDataUid;
  /// Só força novo carregamento da lista quando o uid da sessão muda — `authStateChanges` pode repetir o mesmo utilizador e apagava a UI à bruta.
  String? _lastAuthUidForFinancePeriodReset;
  bool _financeBootstrapDone = false;
  bool _pdfWarmupScheduled = false;

  // PERF (Fase 2 — Financeiro): os streams de pendentes/preferências eram
  // recriados a CADA build (novo listener Firestore por rebuild) e a query de
  // despesas pendentes tinha 3 assinaturas. Agora cada query é assinada UMA vez
  // (broadcast) e reaproveitada por todos os StreamBuilders.
  //
  // Segurança contra "piscar/vazio": um "tracker" interno guarda o último valor
  // emitido; os StreamBuilders recebem esse valor via `initialData`, então quando
  // uma faixa desmonta/remonta (ex.: troca de aba do shell) ela renderiza na hora
  // o último dado conhecido — sem flash de carregamento e sem perder eventos.
  //
  // Como dependem só do uid, ficam válidos por toda a vida da tela; em troca de
  // uid (didUpdateWidget) são descartados e recriados sob demanda.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _pendingExpensesStreamCache;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _pendingIncomesStreamCache;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingExpensesTrackerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingIncomesTrackerSub;
  QuerySnapshot<Map<String, dynamic>>? _lastPendingExpensesSnap;
  QuerySnapshot<Map<String, dynamic>>? _lastPendingIncomesSnap;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _pendingExpensesStream {
    if (_pendingExpensesStreamCache == null) {
      final s = _txRefPendingExpenses()
          .snapshots(includeMetadataChanges: false)
          .asBroadcastStream();
      _pendingExpensesStreamCache = s;
      _pendingExpensesTrackerSub =
          s.listen((snap) => _lastPendingExpensesSnap = snap, onError: (_) {});
    }
    return _pendingExpensesStreamCache!;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _pendingIncomesStream {
    if (_pendingIncomesStreamCache == null) {
      final s = _txRefPendingIncomes()
          .snapshots(includeMetadataChanges: false)
          .asBroadcastStream();
      _pendingIncomesStreamCache = s;
      _pendingIncomesTrackerSub =
          s.listen((snap) => _lastPendingIncomesSnap = snap, onError: (_) {});
    }
    return _pendingIncomesStreamCache!;
  }

  // Preferências (receitas/despesas fixas) — também eram reassinadas a cada build.
  Stream<Map<String, dynamic>>? _fixedIncomePrefsStreamCache;
  Stream<Map<String, dynamic>>? _fixedExpensePrefsStreamCache;
  StreamSubscription<Map<String, dynamic>>? _fixedIncomePrefsTrackerSub;
  StreamSubscription<Map<String, dynamic>>? _fixedExpensePrefsTrackerSub;
  Map<String, dynamic>? _lastFixedIncomePrefs;
  Map<String, dynamic>? _lastFixedExpensePrefs;

  Stream<Map<String, dynamic>> get _fixedIncomePrefsStream {
    if (_fixedIncomePrefsStreamCache == null) {
      final s = FixedIncomePreferencesService()
          .watch(firestoreUserDocIdForAppShell(widget.uid))
          .asBroadcastStream();
      _fixedIncomePrefsStreamCache = s;
      _fixedIncomePrefsTrackerSub =
          s.listen((v) => _lastFixedIncomePrefs = v, onError: (_) {});
    }
    return _fixedIncomePrefsStreamCache!;
  }

  Stream<Map<String, dynamic>> get _fixedExpensePrefsStream {
    if (_fixedExpensePrefsStreamCache == null) {
      final s = FixedExpensePreferencesService()
          .watch(firestoreUserDocIdForAppShell(widget.uid))
          .asBroadcastStream();
      _fixedExpensePrefsStreamCache = s;
      _fixedExpensePrefsTrackerSub =
          s.listen((v) => _lastFixedExpensePrefs = v, onError: (_) {});
    }
    return _fixedExpensePrefsStreamCache!;
  }

  void _resetPendingStreamCaches() {
    _pendingExpensesTrackerSub?.cancel();
    _pendingIncomesTrackerSub?.cancel();
    _fixedIncomePrefsTrackerSub?.cancel();
    _fixedExpensePrefsTrackerSub?.cancel();
    _pendingExpensesTrackerSub = null;
    _pendingIncomesTrackerSub = null;
    _fixedIncomePrefsTrackerSub = null;
    _fixedExpensePrefsTrackerSub = null;
    _pendingExpensesStreamCache = null;
    _pendingIncomesStreamCache = null;
    _fixedIncomePrefsStreamCache = null;
    _fixedExpensePrefsStreamCache = null;
    _lastPendingExpensesSnap = null;
    _lastPendingIncomesSnap = null;
    _lastFixedIncomePrefs = null;
    _lastFixedExpensePrefs = null;
  }

  /// Após mudança de plano/licença, o token Firestore às vezes ainda reflete a sessão antiga — reabre a lista.
  Future<void> _onRetryLoadTransactions() async {
    final u = fa.FirebaseAuth.instance.currentUser;
    if (u != null) {
      try {
        await u.getIdToken(true);
      } catch (_) {
        // segue; o bump já força re-subscrição
      }
    }
    if (mounted) {
      setState(() {
        _mainPeriodLoadError = null;
        _txStreamRetryKey++;
      });
    }
  }

  /// Recurso para casos em que o cache local do Firestore está corrompido
  /// (IndexedDB / disk): chama `terminate()` + `clearPersistence()` e força
  /// nova leitura. Resolve o «Erro ao carregar lançamentos» sem o usuário ter
  /// de sair e entrar de novo.
  Future<void> _onClearCacheAndRetry() async {
    if (!mounted) return;
    setState(() {
      _mainPeriodLoadError = null;
      _mainPeriodLoading = true;
    });
    try {
      await FirebaseFirestore.instance.terminate();
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.clearPersistence();
    } catch (_) {}
    await _onRetryLoadTransactions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache local limpo. Buscando do servidor…'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Só recarrega saldo de abertura quando o lançamento pode alterá-lo (antes do período).
  void _invalidateRealtimeBalances({DateTime? transactionEffectiveDate}) {
    if (transactionEffectiveDate != null) {
      final d = DateTime(
        transactionEffectiveDate.year,
        transactionEffectiveDate.month,
        transactionEffectiveDate.day,
      );
      final start = DateTime(_from.year, _from.month, _from.day);
      if (!d.isBefore(start)) return;
    }
    _forceRefreshSaldoAberturaBundle();
  }

  void _forceRefreshSaldoAberturaBundle() {
    _saldoAberturaKey = '';
    _saldoAberturaCached = null;
    FinanceOpeningBalanceService.invalidateForUser(widget.uid);
    _ensureSaldoAberturaForPeriod(_from);
  }

  /// Fase 1: total (buckets). Fase 2: saldos por conta em background.
  void _ensureSaldoAberturaForPeriod(DateTime periodStart) {
    final key = '${periodStart.year}-${periodStart.month}-${periodStart.day}';
    if (_saldoAberturaKey == key && _saldoAberturaCached != null) return;
    _saldoAberturaKey = key;
    final peek = FinanceOpeningBalanceService.peekCached(
      uid: widget.uid,
      periodStart: periodStart,
      loadAccounts: false,
    );
    if (peek != null) {
      _saldoAberturaCached = peek;
    }
    unawaited(_loadSaldoAberturaIntoState(periodStart));
  }

  Future<void> _loadSaldoAberturaIntoState(DateTime periodStart) async {
    final fast = await _loadSaldoAberturaBundle(periodStart, withAccounts: false);
    if (!mounted) return;
    setState(() => _saldoAberturaCached = fast);
    final full = await _loadSaldoAberturaBundle(periodStart, withAccounts: true);
    if (!mounted) return;
    setState(() => _saldoAberturaCached = full);
  }

  /// Insere na lista do período os docs recém-gravados (cache local) para saldos na hora.
  /// Retorna true se atualizou a lista sem precisar recarregar o período inteiro.
  Future<bool> _mergeSavedTransactionsIntoMainPeriod(Iterable<String> docIds) async {
    final uid = _effectiveFinanceSessionUid;
    if (uid == null || docIds.isEmpty || !mounted) return false;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions');
    final ids = docIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return false;
    final incoming = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < ids.length; i += 30) {
      final end = i + 30 > ids.length ? ids.length : i + 30;
      final chunk = ids.sublist(i, end);
      try {
        // Recém-gravados: prioriza servidor (cache local pode ainda não ter o doc).
        var qSnap = await col
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 4));
        final found = qSnap.docs.map((d) => d.id).toSet();
        final missing = chunk.where((id) => !found.contains(id)).toList();
        if (missing.isNotEmpty) {
          try {
            final cached = await col
                .where(FieldPath.documentId, whereIn: missing)
                .get(const GetOptions(source: Source.cache))
                .timeout(const Duration(milliseconds: 800));
            incoming.addAll([...qSnap.docs, ...cached.docs]);
          } catch (_) {
            incoming.addAll(qSnap.docs);
          }
        } else {
          incoming.addAll(qSnap.docs);
        }
      } catch (_) {}
    }
    if (!mounted || incoming.isEmpty) return false;
    setState(() {
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
        for (final d in _mainPeriodDocs) d.id: d,
      };
      for (final d in incoming) {
        if (_mainPeriodDocMatchesCurrentFilters(d)) byId[d.id] = d;
      }
      _mainPeriodDocs = byId.values.toList();
      _mainPeriodDocs = FinanceFaturaTransactionSort.sortedDocs(
        _mainPeriodDocs,
        FinanceFaturaTxSortMode.dateDesc,
      );
      _mainPeriodLoadedCount = _mainPeriodDocs.length;
      _mainPeriodLoading = false;
    });
    return true;
  }

  /// Sincroniza saldos/lista só pelos lançamentos afetados (criar, editar, excluir, pagar).
  /// Sem recarregar o período inteiro nem barra «A sincronizar…».
  Future<void> _applyFinanceMutationSync({
    Iterable<String>? docIds,
    Iterable<String>? removedDocIds,
    DateTime? transactionEffectiveDate,
  }) async {
    if (!mounted) return;
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _invalidateRealtimeBalances(transactionEffectiveDate: transactionEffectiveDate);

    final removeSet = (removedDocIds ?? const [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (removeSet.isNotEmpty && mounted) {
      setState(() {
        _mainPeriodDocs.removeWhere((d) => removeSet.contains(d.id));
        for (final id in removeSet) {
          _optimisticEditedTxById.remove(id);
          _optimisticPaidIds.remove(id);
        }
      });
    }

    final ids = (docIds ?? const [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isNotEmpty) {
      await _mergeSavedTransactionsIntoMainPeriod(ids);
      if (mounted) {
        _pruneOptimisticEditedTxAgainstDocs(_mainPeriodDocs);
      }
    }

    if (!mounted) return;
    _notifyFinanceTransactionsChanged(effectiveDate: transactionEffectiveDate);
    unawaited(_refreshMainPeriodServerKpis());
  }

  void _recomputeMainPeriodKpisFromVisibleDocs() {
    if (!_mainPeriodServerPagingActive) return;
    if (_mainPeriodHasMoreServer) return;
    // Lista paginada por `date` pode omitir effectiveDate — KPIs vêm do agregado mesclado.
    unawaited(_refreshMainPeriodServerKpis());
  }

  /// Identifica período + filtros que definem receitas/despesas/saldos exibidos.
  String _financeBalanceContextKey() {
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    return '${from.toIso8601String()}|${to.toIso8601String()}|$_statusFilter|$_typeFilter|'
        '${_search.trim().toLowerCase()}|${_categoryFilter ?? ''}|${_financeAccountFilterId ?? ''}';
  }

  /// Limpa agregados só quando o contexto de saldo mudou (mês/filtro), nunca só por sync/pull.
  void _resetFinanceBalanceAggregatesIfContextChanged() {
    final key = _financeBalanceContextKey();
    if (key == _financeBalanceContextKeyApplied) return;
    _financeBalanceContextKeyApplied = key;
    _mainPeriodServerKpis = null;
    _periodMergedKpis = null;
    _serverPagingStripPaidNetByAccount = const {};
    _serverPagingStripNetForGen = -1;
  }

  bool _mainPeriodDocMatchesCurrentFilters(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final fromDay = DateTime(_from.year, _from.month, _from.day);
    final toDay = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
    if (effective == null ||
        effective.isBefore(fromDay) ||
        effective.isAfter(toDay)) {
      return false;
    }
    if (!_mainPeriodServerPagingActive) {
      if (_statusFilter != 'all' &&
          (d['status'] ?? 'paid').toString() != _statusFilter) {
        return false;
      }
      if (_typeFilter != 'all' && (d['type'] ?? 'expense').toString() != _typeFilter) {
        return false;
      }
    }
    final accountFilter = _financeAccountFilterId?.trim();
    if (accountFilter != null && accountFilter.isNotEmpty) {
      final aid = (d['financeAccountId'] ?? '').toString().trim();
      if (aid != accountFilter) return false;
    }
    return true;
  }

  void _onShellFinanceAccountFilterRequest() {
    final raw = FinanceShellNavigation.pendingAccountId.value;
    if (raw == null || !mounted) return;
    FinanceShellNavigation.pendingAccountId.value = null;
    _applyFinanceAccountFilter(raw.isEmpty ? null : raw);
  }

  @override
  void dispose() {
    DelegateAccessService.sessionRevision.removeListener(_onDelegateSessionChanged);
    FinanceShellNavigation.pendingAccountId.removeListener(_onShellFinanceAccountFilterRequest);
    _authStateSub?.cancel();
    _financeAccSub?.cancel();
    _stripHideZeroSub?.cancel();
    _pendingExpensesTrackerSub?.cancel();
    _pendingIncomesTrackerSub?.cancel();
    _fixedIncomePrefsTrackerSub?.cancel();
    _fixedExpensePrefsTrackerSub?.cancel();
    _searchDebounceTimer?.cancel();
    _delayedMainPeriodReloadTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Lista já carregada para o período (sem paginação incompleta): filtro por conta só em memória.
  bool _financeCanFilterAccountClientSide() {
    if (_search.trim().isNotEmpty) return false;
    final cat = _categoryFilter?.trim() ?? '';
    if (cat.isNotEmpty) return false;
    if (_mainPeriodDocs.isEmpty) return false;
    if (_mainPeriodServerPagingActive && _mainPeriodHasMoreServer) return false;
    return true;
  }

  /// Troca de conta / «Todas»: atualiza lista e saldos sem esvaziar a tela (evita “piscar” / voltar ao Início).
  void _applyFinanceAccountFilter(String? accountId) {
    final trimmed = accountId?.trim() ?? '';
    final next = trimmed.isEmpty ? null : trimmed;
    if (_financeAccountFilterId == next) return;

    final clientOnly = _financeCanFilterAccountClientSide();
    setState(() {
      _financeAccountFilterId = next;
      _resetTxPagination();
    });

    if (clientOnly) {
      _notifyFinanceTransactionsChanged();
      return;
    }

    _mainPeriodScheduledLoadKey = '';
    _scheduleMainPeriodReloadAfterMutationDebounced(
      immediate: true,
      preserveExistingDocs: true,
      accountFilterOnly: true,
    );
  }

  /// Atualiza faixas pendentes, KPIs e saldos do carrossel após criar/editar/excluir/confirmar.
  void _notifyFinanceTransactionsChanged({DateTime? effectiveDate}) {
    if (!mounted) return;
    final deduped = _dedupeMainPeriodDocs(_mainPeriodDocs);
    final paid = _sumPeriodTotalsFromDocs(deduped, statusFilter: 'paid');
    final strip = _netByFinanceAccountIdPaidEffective(deduped, _from, _to);
    setState(() {
      if (deduped.isNotEmpty) {
        _mainPeriodServerKpis = (income: paid.income, expense: paid.expense);
        _periodMergedKpis = (income: paid.income, expense: paid.expense);
        _serverPagingStripPaidNetByAccount = strip;
        _serverPagingStripNetForGen = _mainPeriodLoadGeneration;
      }
    });
    _recomputeMainPeriodKpisFromVisibleDocs();
    FinanceTransactionsHub.notifyMutated(
      uid: widget.uid,
      effectiveDate: effectiveDate,
      invalidateOpeningBalance: false,
    );
    final uid = _effectiveFinanceSessionUid;
    if (uid == null) return;
    unawaited(_refreshMainPeriodStripAccountNets(uid, _mainPeriodLoadGeneration));
  }

  /// Toque no cartão: crédito abre preview isolado (sem filtrar a lista principal).
  void _onFinanceStripCardTap(BuildContext context, FinanceAccount? account) {
    if (account == null) {
      if (_financeAccountFilterId != null) {
        _applyFinanceAccountFilter(null);
      } else {
        _openAllAccountsCategoryBreakdown(context);
      }
      return;
    }
    if (account.isCreditCardProduct) {
      _openCreditCardFaturaSheet(context, account);
      return;
    }
    final id = account.id;
    if (_financeAccountFilterId != id) {
      _applyFinanceAccountFilter(id);
    }
    _openFinanceAccountCategoryBreakdown(context, account);
  }

  Future<void> _confirmarPagamentoFaturaCartao(
    BuildContext context,
    List<String> docIds, {
    required FinanceConfirmPaymentSheetResult result,
    required String cardAccountId,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final unique = docIds.toSet().where((e) => e.trim().isNotEmpty).toList();
    if (unique.isEmpty) return;

    final payDay = DateTime(
      result.paymentDate.year,
      result.paymentDate.month,
      result.paymentDate.day,
    );
    final todayDay = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final isScheduledFuture =
        result.faturaSchedule != null && payDay.isAfter(todayDay);

    if (!isScheduledFuture) {
      setState(() {
        for (final id in unique) {
          _optimisticPaidIds.add(id);
        }
      });
    }

    try {
      await commitFinanceConfirmPaymentBatch(
        txCol: _txRef(),
        docIds: unique,
        uid: widget.uid,
        result: result,
        creditCardFaturaPayment: true,
      );
      if (!mounted) return;
      if (!isScheduledFuture) {
        final confTs = Timestamp.fromDate(result.paymentDate);
        final paidFrom = result.financeAccountId?.trim() ?? '';
        setState(() {
          for (final id in unique) {
            _optimisticPaidIds.remove(id);
            final prev = _optimisticEditedTxById[id];
            _optimisticEditedTxById[id] = {
              if (prev != null) ...prev,
              'status': 'paid',
              'paidAt': confTs,
              'effectiveDate': confTs,
              'financeAccountId': cardAccountId,
              if (paidFrom.isNotEmpty) 'paidFromFinanceAccountId': paidFrom,
            };
          }
          _invalidateRealtimeBalances(transactionEffectiveDate: result.paymentDate);
        });
      } else {
        setState(() {});
      }
      unawaited(_applyFinanceMutationSync(
        docIds: unique,
        transactionEffectiveDate: result.paymentDate,
      ));
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        final df = DateFormat('dd/MM/yyyy');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isScheduledFuture
                  ? (result.faturaSchedule!.autoDebitOnDueDate
                      ? 'Fechamento agendado: débito automático em ${df.format(result.paymentDate)}.'
                      : 'Fechamento registrado: confirme o pagamento em ${df.format(result.paymentDate)}.')
                  : (unique.length > 1
                      ? 'Fatura: ${unique.length} lançamentos pagos.'
                      : 'Pagamento da fatura confirmado.'),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final id in unique) {
            _optimisticPaidIds.remove(id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao pagar fatura: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _openCreditCardFaturaSheet(BuildContext context, FinanceAccount card) {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    FinanceCreditCardFaturaSheet.show(
      context,
      uid: widget.uid,
      profile: widget.profile,
      cardAccount: card,
      allAccounts: _financeAccounts,
      optimisticPaidIds: _optimisticPaidIds,
      onConfirmFaturaPayment: _confirmarPagamentoFaturaCartao,
      onEditTransaction: _editTx,
      onDeleteTransaction: _deleteTx,
      onDeleteBatch: _deleteTxBatch,
      onAttachReceipt: _attachReceipt,
    );
  }

  /// Débitos de fatura agendados cuja data já passou.
  Future<void> _processDueFaturaScheduledPayments() async {
    if (!mounted || !widget.isShellVisible) return;
    try {
      final n = await processDueFaturaScheduledPayments(
        txCol: _txRef(),
        uid: widget.uid,
      );
      if (n > 0 && mounted) {
        _notifyFinanceTransactionsChanged();
      }
    } catch (e, st) {
      debugPrint('_processDueFaturaScheduledPayments: $e\n$st');
    }
  }

  FinanceFaturaSheetHandlers get _faturaSheetHandlers => FinanceFaturaSheetHandlers(
        onConfirmFaturaPayment: _confirmarPagamentoFaturaCartao,
        onEditTransaction: _editTx,
        onDeleteTransaction: _deleteTx,
        onDeleteBatch: _deleteTxBatch,
        onAttachReceipt: _attachReceipt,
      );

  void _openFaturaEmAbertoHub(
    BuildContext context,
    Map<String, double> faturaByCard,
  ) {
    unawaited(
      FinanceFaturaEmAbertoHub.open(
        context,
        uid: widget.uid,
        profile: widget.profile,
        allAccounts: _financeAccounts,
        faturaByCardId: faturaByCard,
        handlers: _faturaSheetHandlers,
        optimisticPaidIds: _optimisticPaidIds,
      ),
    );
  }

  Widget _buildFaturaEmAbertoBand(BuildContext context) {
    if (!widget.isShellVisible) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _pendingExpensesStream,
        initialData: _lastPendingExpensesSnap,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final faturaByCard = FinanceAccountBalanceUtils.faturaAbertaByCardId(
          docs,
          creditCardIds: _creditCardAccountIds,
        );
        final total = FinanceAccountBalanceUtils.totalFaturaEmAberto(faturaByCard);
        final ccIds = _creditCardAccountIds;
        final count = FinanceAccountBalanceUtils.countPendingExpensesOnCreditCards(docs, ccIds);
        final cards = FinanceAccountBalanceUtils.creditCardProducts(_financeAccounts);
        return FinanceFaturaEmAbertoBand(
          totalFatura: total,
          lancamentoCount: count,
          cartaoCount: cards.length,
          compact: true,
          onTap: snap.hasError
              ? () {}
              : () => _openFaturaEmAbertoHub(context, faturaByCard),
        );
      },
    );
  }

  /// Mesmas ações da lista principal, reutilizadas na rota em tela cheia (uma instância por ciclo de vida do State).
  late final FinanceFullscreenHandlers _fullscreenTxHandlers = FinanceFullscreenHandlers.fromFinanceScreen(
        editTx: _editTx,
        deleteTx: _deleteTx,
        confirmarPagamento: _confirmarPagamento,
        attachReceipt: _attachReceipt,
        deleteTxBatch: _deleteTxBatch,
      );

  void _bindFinanceUserDataStreams() {
    if (!mounted) return;
    final cu = fa.FirebaseAuth.instance.currentUser;
    if (cu == null) {
      _financeAccSub?.cancel();
      _stripHideZeroSub?.cancel();
      _financeAccSub = null;
      _stripHideZeroSub = null;
      _financeUserStreamsBound = false;
      _lastBoundFinanceAuthUid = null;
      if (mounted) {
        setState(() {
          _financeAccounts = const [];
          _financeAccountsStreamPrimed = false;
        });
      }
      return;
    }
    final fsUid = firestoreUserDocIdForAppShell(widget.uid);
    if (_financeUserStreamsBound &&
        _lastBoundFinanceAuthUid == cu.uid &&
        _lastBoundFinanceDataUid == fsUid) {
      return;
    }
    _financeAccSub?.cancel();
    _stripHideZeroSub?.cancel();
    _financeAccSub = null;
    _stripHideZeroSub = null;
    _financeUserStreamsBound = true;
    _lastBoundFinanceAuthUid = cu.uid;
    _lastBoundFinanceDataUid = fsUid;
    _financeAccSub = FinanceAccountsService().streamAccounts(fsUid).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _financeAccounts = list;
          _financeAccountsStreamPrimed = true;
          if (_financeAccountFilterId != null && !list.any((a) => a.id == _financeAccountFilterId)) {
            _financeAccountFilterId = null;
          }
        });
      },
      onError: (Object e, StackTrace st) {
        debugPrint('FinanceAccountsStream: $e\n$st');
        if (!mounted) return;
        setState(() {
          _financeAccounts = const [];
          _financeAccountsStreamPrimed = true;
        });
      },
    );
    _stripHideZeroSub = FinanceAdvancedSettingsService().watchStripHideZeroBalances(fsUid).listen(
      (v) {
        if (!mounted) return;
        setState(() => _stripHideZeroBalances = v);
      },
      onError: (Object e, StackTrace st) {
        debugPrint('FinanceAdvancedSettingsStream: $e\n$st');
      },
    );
  }

  String _mainPeriodLoadScheduleKey(String sessionUid) {
    final key = '${_from.millisecondsSinceEpoch}';
    return '${sessionUid}_${key}_${_to.millisecondsSinceEpoch}_$_txStreamRetryKey|$_statusFilter|$_typeFilter|${_categoryFilter ?? ''}|${_financeAccountFilterId ?? ''}';
  }

  /// Primeira pintura: lista do cache local (sem skeleton) quando filtros permitem paginação no servidor.
  Future<void> _primeMainPeriodFromFirestoreCache() async {
    final sessionUid = _effectiveFinanceSessionUid;
    if (sessionUid == null || !mounted) return;
    if (!financeMainPeriodCanServerPage(
      searchLowerTrim: _search,
      statusFilter: _statusFilter,
      categoryFilter: _categoryFilter,
      financeAccountFilterId: _financeAccountFilterId,
    )) {
      return;
    }
    try {
      final q = financeMainPeriodFirestoreQuery(
        sessionUid: sessionUid,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        typeFilter: _typeFilter,
      ).limit(_kMainPeriodFirestorePageSize);
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (!mounted || snap.docs.isEmpty) return;
      setState(() {
        _mainPeriodDocs = snap.docs;
        _mainPeriodFirestoreCursor = snap.docs.last;
        _mainPeriodHasMoreServer =
            snap.docs.length >= _kMainPeriodFirestorePageSize;
        _mainPeriodLoadedCount = snap.docs.length;
        _mainPeriodLoading = false;
        _mainPeriodServerPagingActive = true;
        _mainPeriodLoadError = null;
      });
      unawaited(_refreshMainPeriodServerKpis());
    } catch (_) {}
  }

  void _scheduleMainPeriodLoadForCurrentFilters(String sessionUid) {
    final lk = _mainPeriodLoadScheduleKey(sessionUid);
    if (_mainPeriodScheduledLoadKey != lk) {
      _mainPeriodScheduledLoadKey = lk;
      _mainPeriodLoadGeneration++;
      final gen = _mainPeriodLoadGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_executeMainPeriodLoad(gen, sessionUid));
      });
    }
  }

  /// Contas + «ocultar saldo zero» em paralelo ao stream; primeira pintura mais rápida.
  Future<void> _primeFinanceBootstrap() async {
    if (!mounted || firestoreUserDocIdStrictFromSession().isEmpty) return;
    try {
      final results = await Future.wait<Object>([
        FinanceAccountsService().listOnce(widget.uid),
        FinanceAdvancedSettingsService().getStripHideZeroBalancesOnce(widget.uid),
      ]);
      final accounts = results[0] as List<FinanceAccount>;
      final stripHide = results[1] as bool;
      if (!mounted) return;
      setState(() {
        _financeAccounts = accounts;
        _stripHideZeroBalances = stripHide;
        _financeAccountsStreamPrimed = true;
      });
    } catch (e, st) {
      debugPrint('_primeFinanceBootstrap: $e\n$st');
    }
  }

  void _onDelegateSessionChanged() {
    if (!mounted) return;
    if (!widget.isShellVisible) return;
    _resumeFinanceHeavyWork();
    setState(() => _mainPeriodScheduledLoadKey = '');
    _requestMainPeriodReload();
  }

  void _scrollFinanceModuleToTop() {
    final c = widget.shellScrollController;
    if (c == null || !c.hasClients) return;
    c.jumpTo(0);
  }

  void _resetFinanceEntryUiState() {
    if (!_topoExpandido && !_filtrosPainelAberto) return;
    setState(() {
      _topoExpandido = false;
      _filtrosPainelAberto = false;
    });
  }

  void _pauseFinanceHeavyWork() {
    _financeAccSub?.cancel();
    _financeAccSub = null;
    _stripHideZeroSub?.cancel();
    _stripHideZeroSub = null;
    _financeUserStreamsBound = false;
  }

  void _ensureCategoryFilterOptionsLoaded() {
    if (_categoryFilterOptionsPrimed) return;
    _categoryFilterOptionsPrimed = true;
    _categoryFilterOptionsFuture = _loadCategoryFilterOptions();
  }

  void _resumeFinanceHeavyWork() {
    if (!mounted || !widget.isShellVisible) return;
    _ensureCategoryFilterOptionsLoaded();
    _bindFinanceUserDataStreams();
    if (!_financeBootstrapDone) {
      _financeBootstrapDone = true;
      unawaited(_primeFinanceBootstrap());
    }
    // Firestore/KPIs no frame seguinte — pinta o módulo antes do trabalho pesado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isShellVisible) return;
      unawaited(FinanceOpeningBalanceService.ensureServerBucketsRebuildIfNeeded(widget.uid));
      unawaited(_primeMainPeriodFromFirestoreCache());
      unawaited(_processDueFaturaScheduledPayments());
      _requestMainPeriodReload();
      if (!_pdfWarmupScheduled) {
        _pdfWarmupScheduled = true;
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted && widget.isShellVisible) {
            unawaited(RelatorioService.warmUpPdfAssets());
          }
        });
      }
    });
  }

  void _syncFinanceShellVisibility({bool scrollToTop = false}) {
    if (!mounted) return;
    if (!widget.isShellVisible) {
      _pauseFinanceHeavyWork();
      return;
    }
    if (scrollToTop) {
      _resetFinanceEntryUiState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.isShellVisible) return;
        _scrollFinanceModuleToTop();
      });
    }
    _resumeFinanceHeavyWork();
    final peekOpen = FinanceOpeningBalanceService.peekCached(
      uid: widget.uid,
      periodStart: _from,
      loadAccounts: true,
    );
    if (peekOpen != null) {
      _saldoAberturaCached = peekOpen;
      _saldoAberturaKey = '${_from.year}-${_from.month}-${_from.day}';
    }
    if (fa.FirebaseAuth.instance.currentUser != null) {
      _ensureSaldoAberturaForPeriod(_from);
    }
  }

  void _requestMainPeriodReload() {
    if (!mounted || !widget.isShellVisible) return;
    final sid = _effectiveFinanceSessionUid;
    if (sid == null) return;
    _mainPeriodScheduledLoadKey = '';
    _scheduleMainPeriodLoadForCurrentFilters(sid);
  }

  @override
  void initState() {
    super.initState();
    DelegateAccessService.sessionRevision.addListener(_onDelegateSessionChanged);
    FinanceShellNavigation.pendingAccountId.addListener(_onShellFinanceAccountFilterRequest);
    final (f, t) = _rangeForPeriod();
    _from = f;
    _to = t;
    _lastAuthUidForFinancePeriodReset = fa.FirebaseAuth.instance.currentUser?.uid;
    _authStateSub = fa.FirebaseAuth.instance.authStateChanges().listen((u) {
      if (!mounted) return;
      final id = u?.uid;
      if (id == _lastAuthUidForFinancePeriodReset) {
        if (widget.isShellVisible) _resumeFinanceHeavyWork();
        return;
      }
      _lastAuthUidForFinancePeriodReset = id;
      setState(() {
        _mainPeriodScheduledLoadKey = '';
      });
      if (widget.isShellVisible) _requestMainPeriodReload();
    });
    _categoryFilterOptionsFuture = Future.value(const <String>[]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onShellFinanceAccountFilterRequest();
      _syncFinanceShellVisibility(scrollToTop: true);
    });
  }

  @override
  void didUpdateWidget(covariant FinanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      // Troca de conta/delegação: descarta os streams cacheados para reabrir no uid novo.
      _resetPendingStreamCaches();
    }
    if (oldWidget.isShellVisible != widget.isShellVisible ||
        oldWidget.uid != widget.uid) {
      _syncFinanceShellVisibility(scrollToTop: widget.isShellVisible);
      return;
    }
    if (oldWidget.profile.plan != widget.profile.plan ||
        oldWidget.profile.planStatus != widget.profile.planStatus ||
        oldWidget.profile.hasActiveLicense != widget.profile.hasActiveLicense ||
        oldWidget.profile.licenseExpiresAt != widget.profile.licenseExpiresAt) {
      unawaited(_onRetryLoadTransactions());
    }
  }

  Future<List<String>> _loadCategoryFilterOptions() async {
    final x = await UserCategoriesService().load(firestoreUserDocIdForAppShell(widget.uid));
    return UserCategoriesService.sortedWithoutIncluirNova([
      ...x.income,
      ...x.expense,
    ]);
  }

  void _refreshCategoryFilterOptions() {
    _categoryFilterOptionsPrimed = true;
    setState(() {
      _categoryFilterOptionsFuture = _loadCategoryFilterOptions();
    });
  }

  InputDecoration _financeFilterDropdownDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.textPrimary.withValues(alpha: 0.9),
      ),
      prefixIcon: Icon(icon, size: 20, color: AppColors.primary.withValues(alpha: 0.85)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.45), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Future<void> _openCategoryFilterPicker() async {
    final options = await _categoryFilterOptionsFuture;
    if (!mounted) return;
    final picked = await pickFinanceCategoryForFilter(
      context: context,
      uid: firestoreUserDocIdForAppShell(widget.uid),
      typeFilter: _typeFilter,
      currentFilter: _categoryFilter,
      periodExtraCategories: options,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _categoryFilter = picked;
      _resetTxPagination();
    });
  }

  void _openFullscreenLancamentos(BuildContext context) {
    Navigator.of(context)
        .push<FinanceFullscreenFilterSnapshot?>(
      MaterialPageRoute<FinanceFullscreenFilterSnapshot?>(
        builder: (ctx) => FinanceTransactionsFullscreenPage(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          profile: widget.profile,
          initialFrom: _from,
          initialTo: _to,
          initialStatusFilter: _statusFilter,
          initialTypeFilter: _typeFilter,
          initialCategory: _categoryFilter,
          initialSearch: _searchCtrl.text,
          initialFinanceAccountId: _financeAccountFilterId,
          handlers: _fullscreenTxHandlers,
        ),
      ),
    )
        .then((snap) {
      if (!mounted || snap == null) return;
      _applyFullscreenFilterSnapshot(snap);
    });
  }

  void _applyFullscreenFilterSnapshot(FinanceFullscreenFilterSnapshot snap) {
    _searchDebounceTimer?.cancel();
    setState(() {
      _selectedPeriod = snap.selectedPeriod;
      _customRangeStart = snap.customRangeStart;
      _customRangeEnd = snap.customRangeEnd;
      _statusFilter = snap.statusFilter;
      _typeFilter = snap.typeFilter;
      _categoryFilter = snap.categoryFilter;
      _financeAccountFilterId = snap.financeAccountFilterId;
      _searchCtrl.text = snap.searchText;
      _search = snap.searchText.toLowerCase().trim();
    });
    _applyPeriod();
  }

  /// Valor monetário de um lançamento Firestore (evita cast quebrando o PDF se vier string/Int).
  double _financeAmountToDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final t = v.toString().trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t.replaceAll(',', '.')) ?? 0;
  }

  String? _filenameAccountSuffix() {
    if (_financeAccountFilterId == null) return null;
    for (final a in _financeAccounts) {
      if (a.id == _financeAccountFilterId) {
        var s = a.displayName.replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '_').trim();
        if (s.isEmpty) s = 'conta';
        return s.length > 48 ? s.substring(0, 48) : s;
      }
    }
    return 'conta';
  }

  String? _selectedFinanceAccountLabel() {
    if (_financeAccountFilterId == null) return null;
    for (final a in _financeAccounts) {
      if (a.id == _financeAccountFilterId) {
        return a.displayName.trim();
      }
    }
    return null;
  }

  List<FinanceAccount> _visibleAccountsForStrip(
    Map<String, double> netByAcc, {
    Map<String, double> faturaByCard = const {},
  }) {
    if (!_stripHideZeroBalances) return _financeAccounts;
    return _financeAccounts.where((a) {
      if (a.isCreditCardProduct) {
        return (faturaByCard[a.id] ?? 0).abs() > 0.0001;
      }
      return (netByAcc[a.id] ?? 0).abs() > 0.0001;
    }).toList();
  }

  /// Aplica reorder do carrossel preservando a posição relativa das contas
  /// **ocultas** (filtro «Ocultar saldo zero»): só os ids visíveis trocam de
  /// posição entre si; cada conta oculta mantém o slot global onde já estava.
  /// "Todas as contas" não entra na lista — fica fixa no header.
  Future<void> _reorderFinanceAccountsStrip(
    List<FinanceAccount> visible,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex < 0 || newIndex > visible.length) return;
    final visibleIds = visible.map((a) => a.id).toList();
    final movedId = visibleIds.removeAt(oldIndex);
    visibleIds.insert(newIndex, movedId);
    final visibleSet = visible.map((a) => a.id).toSet();
    final newOrder = <String>[];
    var vIdx = 0;
    for (final acc in _financeAccounts) {
      if (visibleSet.contains(acc.id) && vIdx < visibleIds.length) {
        newOrder.add(visibleIds[vIdx]);
        vIdx++;
      } else {
        newOrder.add(acc.id);
      }
    }
    // Atualiza a UI imediatamente (otimista) — depois o stream do Firestore
    // re-emite a ordem definitiva.
    final reordered = <FinanceAccount>[];
    for (final id in newOrder) {
      final acc = _financeAccounts.firstWhere(
        (a) => a.id == id,
        orElse: () => _financeAccounts.first,
      );
      reordered.add(acc);
    }
    if (mounted) {
      setState(() => _financeAccounts = reordered);
    }
    HapticFeedback.selectionClick();
    try {
      await FinanceAccountsService().setAccountOrder(
        firestoreUserDocIdForAppShell(widget.uid),
        newOrder,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar a nova ordem: $e')),
      );
    }
  }

  int _countTxSemConta(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    var n = 0;
    for (final doc in docs) {
      final d = doc.data();
      if ((d['financeAccountId'] ?? '').toString().trim().isNotEmpty) continue;
      n++;
    }
    return n;
  }

  Future<void> _openStripLongPressMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Opções do painel de contas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ocultar contas com saldo zero'),
              subtitle: const Text('No período atual, no carrossel de contas.'),
              value: _stripHideZeroBalances,
              onChanged: widget.profile.hasActiveLicense
                  ? (v) async {
                      await FinanceAdvancedSettingsService().setStripHideZeroBalances(firestoreUserDocIdForAppShell(widget.uid), v);
                      if (mounted) setState(() {});
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  : null,
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      ),
    );
  }

  /// Retorna (início, fim) do período selecionado. Fim do período completo (mês/ano) para incluir despesas com data futura no período (paga antecipada).
  (DateTime, DateTime) _rangeForPeriod() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Mensal':
        // Mês completo (1º ao último dia) para incluir despesas com data futura no mês (paga antecipada).
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
      case 'Anual':
        // Ano completo para incluir despesas com data no ano (ex.: paga antecipada); alinhado ao painel inicial.
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
      case 'Por período':
        final start = _customRangeStart ?? DateTime(now.year, now.month, 1);
        final end = _customRangeEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return (DateTime(start.year, start.month, start.day), DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59));
      default:
        return (DateTime(now.year, 1, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
    }
  }

  void _resetTxPagination() {
    _txDisplayLimit = _txPageSize;
  }

  Future<void> _loadMainPeriodMergedFallback(int myGen, String sessionUid) async {
    final merged = await financePeriodMergedDocumentsCollect(
      uid: sessionUid,
      from: _from,
      to: _to,
      statusFilter: _statusFilter,
      typeFilter: _typeFilter,
      financeAccountId: _financeAccountFilterId,
    );
    if (!mounted || myGen != _mainPeriodLoadGeneration) return;
    setState(() {
      _mainPeriodDocs = merged;
      _mainPeriodLoadedCount = merged.length;
      _mainPeriodLoading = false;
      _mainPeriodLoadError = null;
      _mainPeriodServerPagingActive = false;
      _mainPeriodHasMoreServer = false;
      _mainPeriodFirestoreCursor = null;
      _pruneOptimisticEditedTxAgainstDocs(_mainPeriodDocs);
    });
    unawaited(_refreshMainPeriodStripAccountNets(sessionUid, myGen));
    unawaited(_refreshMainPeriodServerKpis());
    _notifyFinanceTransactionsChanged();
  }

  Future<void> _executeMainPeriodLoad(
    int myGen,
    String sessionUid, {
    bool preserveExistingDocs = false,
    bool accountFilterOnly = false,
  }) async {
    if (!mounted || myGen != _mainPeriodLoadGeneration) return;

    final useServerPage = financeMainPeriodCanServerPage(
      searchLowerTrim: _search,
      statusFilter: _statusFilter,
      categoryFilter: _categoryFilter,
      financeAccountFilterId: _financeAccountFilterId,
    );

    final silentReload =
        preserveExistingDocs && _mainPeriodDocs.isNotEmpty;

    setState(() {
      // Não limpar _optimisticEditedTxById aqui: o ramo com paginação no servidor
      // pinta primeiro o cache Firestore (stale) e apagava o patch antes da lista
      // refletir o update — a lista parecia não gravar (ex.: descrição). Remover
      // patches só depois que os documentos carregados batem com o servidor (_prune…).
      _mainPeriodLoading = !silentReload;
      _mainPeriodLoadError = null;
      if (!preserveExistingDocs) {
        // Sempre esvazia lista antes de recarregar — evita duplicar docId.
        _mainPeriodDocs = [];
        _mainPeriodLoadedCount = 0;
        _mainPeriodServerPagingActive = useServerPage;
        _mainPeriodFirestoreCursor = null;
        _mainPeriodHasMoreServer = false;
        _mainPeriodLoadingMore = false;
        _resetFinanceBalanceAggregatesIfContextChanged();
      } else if (accountFilterOnly) {
        _mainPeriodServerPagingActive = useServerPage;
      }
    });

    try {
      if (useServerPage) {
        final q = financeMainPeriodFirestoreQuery(
          sessionUid: sessionUid,
          from: _from,
          to: _to,
          statusFilter: _statusFilter,
          typeFilter: _typeFilter,
        );
        final firstPageQuery = q.limit(_kMainPeriodFirestorePageSize);
        try {
          final cachedSnap = await firstPageQuery.get(const GetOptions(source: Source.cache));
          if (mounted && myGen == _mainPeriodLoadGeneration && cachedSnap.docs.isNotEmpty) {
            setState(() {
              _mainPeriodDocs = cachedSnap.docs;
              _mainPeriodFirestoreCursor = cachedSnap.docs.last;
              _mainPeriodHasMoreServer = cachedSnap.docs.length >= _kMainPeriodFirestorePageSize;
              _mainPeriodLoadedCount = cachedSnap.docs.length;
            });
          }
        } catch (_) {
          // Cache pode estar vazio/indisponível; segue para servidor.
        }
        try {
          final snap = await firstPageQuery.get().timeout(const Duration(seconds: 12));
          if (!mounted || myGen != _mainPeriodLoadGeneration) return;
          setState(() {
            _mainPeriodDocs = snap.docs;
            _mainPeriodFirestoreCursor = snap.docs.isEmpty ? null : snap.docs.last;
            _mainPeriodHasMoreServer = snap.docs.length >= _kMainPeriodFirestorePageSize;
            _mainPeriodLoadedCount = snap.docs.length;
            _mainPeriodLoading = false;
            _pruneOptimisticEditedTxAgainstDocs(_mainPeriodDocs);
          });
          unawaited(_refreshMainPeriodServerKpis());
          unawaited(_refreshMainPeriodStripAccountNets(sessionUid, myGen));
          unawaited(_mergeMainPeriodDocsFromEffectiveDate(sessionUid, myGen));
          _notifyFinanceTransactionsChanged();
          return;
        } on TimeoutException {
          if (!mounted || myGen != _mainPeriodLoadGeneration) return;
          await _loadMainPeriodMergedFallback(myGen, sessionUid);
          return;
        } on FirebaseException catch (e) {
          debugPrint('_executeMainPeriodLoad server page: $e');
          if (!mounted || myGen != _mainPeriodLoadGeneration) return;
          await _loadMainPeriodMergedFallback(myGen, sessionUid);
          return;
        }
      }

      final merged = await financePeriodMergedDocumentsCollect(
        uid: sessionUid,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        typeFilter: _typeFilter,
        financeAccountId: _financeAccountFilterId,
      );
      if (!mounted || myGen != _mainPeriodLoadGeneration) return;
      setState(() {
        _mainPeriodDocs = merged;
        _mainPeriodLoadedCount = merged.length;
        _mainPeriodLoading = false;
        _mainPeriodServerPagingActive = false;
        _mainPeriodHasMoreServer = false;
        _mainPeriodFirestoreCursor = null;
        _pruneOptimisticEditedTxAgainstDocs(_mainPeriodDocs);
      });
      unawaited(_refreshMainPeriodStripAccountNets(sessionUid, myGen));
      unawaited(_refreshMainPeriodServerKpis());
      _notifyFinanceTransactionsChanged();
    } catch (e, st) {
      debugPrint('_executeMainPeriodLoad: $e\n$st');
      if (mounted && myGen == _mainPeriodLoadGeneration) {
        try {
          await _loadMainPeriodMergedFallback(myGen, sessionUid);
          return;
        } catch (e2, st2) {
          debugPrint('_executeMainPeriodLoad fallback: $e2\n$st2');
        }
        if (_mainPeriodDocs.isNotEmpty) {
          setState(() {
            _mainPeriodLoading = false;
            _mainPeriodLoadError = null;
            _mainPeriodServerPagingActive = false;
            _mainPeriodHasMoreServer = false;
          });
          _scheduleMainPeriodReloadAfterMutationDebounced();
          return;
        }
        setState(() {
          _mainPeriodLoading = false;
          _mainPeriodLoadError = e;
          _mainPeriodServerPagingActive = false;
          _mainPeriodHasMoreServer = false;
        });
      }
    }
  }

  Future<void> _refreshMainPeriodServerKpis() async {
    if (!mounted) return;
    try {
      final r = await FinancePeriodSummary.load(
        uid: firestoreUserDocIdForAppShell(widget.uid),
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        typeFilter: _typeFilter,
      );
      if (!mounted) return;
      setState(() {
        _mainPeriodServerKpis = (income: r.income, expense: r.expense);
        _periodMergedKpis = (income: r.income, expense: r.expense);
      });
    } catch (_) {}
  }

  Future<void> _refreshPeriodMergedKpis() => _refreshMainPeriodServerKpis();

  /// Completa a lista paginada por [date] com lançamentos cuja [effectiveDate] cai no período.
  Future<void> _mergeMainPeriodDocsFromEffectiveDate(String sessionUid, int generation) async {
    if (!mounted || generation != _mainPeriodLoadGeneration) return;
    try {
      final merged = await financePeriodMergedDocumentsCollect(
        uid: sessionUid,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        typeFilter: _typeFilter,
        financeAccountId: _financeAccountFilterId,
      );
      if (!mounted || generation != _mainPeriodLoadGeneration) return;
      setState(() {
        _mainPeriodDocs = merged;
        _mainPeriodLoadedCount = merged.length;
        _mainPeriodHasMoreServer = false;
        _mainPeriodFirestoreCursor = null;
        _mainPeriodServerPagingActive = false;
        _pruneOptimisticEditedTxAgainstDocs(_mainPeriodDocs);
      });
      unawaited(_refreshMainPeriodServerKpis());
      final m = _netByFinanceAccountIdPaidEffective(merged, _from, _to);
      if (!mounted || generation != _mainPeriodLoadGeneration) return;
      setState(() {
        _serverPagingStripPaidNetByAccount = m;
        _serverPagingStripNetForGen = generation;
      });
    } catch (e, st) {
      debugPrint('_mergeMainPeriodDocsFromEffectiveDate: $e\n$st');
    }
  }

  /// Saldo líquido **pago** por conta no período (evita 2ª varredura quando 1 página cobre o período).
  Future<void> _refreshMainPeriodStripAccountNets(String sessionUid, int generation) async {
    if (!mounted) return;
    if (generation != _mainPeriodLoadGeneration) return;
    try {
      if (_mainPeriodServerPagingActive) {
        final all = await financePeriodMergedDocumentsCollect(
          uid: sessionUid,
          from: _from,
          to: _to,
          statusFilter: _statusFilter,
          typeFilter: _typeFilter,
          financeAccountId: _financeAccountFilterId,
        ).timeout(const Duration(seconds: 45));
        if (!mounted || generation != _mainPeriodLoadGeneration) return;
        final m = _netByFinanceAccountIdPaidEffective(all, _from, _to);
        setState(() {
          _serverPagingStripPaidNetByAccount = m;
          _serverPagingStripNetForGen = generation;
        });
        return;
      }
      final m = _netByFinanceAccountIdPaidEffective(_mainPeriodDocs, _from, _to);
      setState(() {
        _serverPagingStripPaidNetByAccount = m;
        _serverPagingStripNetForGen = generation;
      });
    } catch (e, st) {
      debugPrint('_refreshMainPeriodStripAccountNets: $e\n$st');
    }
  }

  Future<void> _loadMoreMainPeriodFirestore(String sessionUid) async {
    if (!_mainPeriodServerPagingActive || !_mainPeriodHasMoreServer) return;
    final cursor = _mainPeriodFirestoreCursor;
    if (cursor == null) return;
    final gen = _mainPeriodLoadGeneration;
    if (!mounted) return;
    setState(() => _mainPeriodLoadingMore = true);
    try {
      final q = financeMainPeriodFirestoreQuery(
        sessionUid: sessionUid,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        typeFilter: _typeFilter,
      ).startAfterDocument(cursor).limit(_kMainPeriodFirestorePageSize);
      final snap = await q.get();
      if (!mounted || gen != _mainPeriodLoadGeneration) return;
      setState(() {
        _mainPeriodDocs = [..._mainPeriodDocs, ...snap.docs];
        _mainPeriodFirestoreCursor = snap.docs.isEmpty ? cursor : snap.docs.last;
        _mainPeriodHasMoreServer = snap.docs.length >= _kMainPeriodFirestorePageSize;
        _mainPeriodLoadedCount = _mainPeriodDocs.length;
        _mainPeriodLoadingMore = false;
        _pruneOptimisticEditedTxAgainstDocs(_mainPeriodDocs);
      });
    } catch (e, st) {
      debugPrint('_loadMoreMainPeriodFirestore: $e\n$st');
      if (mounted && gen == _mainPeriodLoadGeneration) {
        setState(() => _mainPeriodLoadingMore = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Não foi possível carregar mais: ${friendlyMessage(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// PDF/CSV com período = tela e filtros «servidor»: se a lista ainda tem mais páginas no Firestore, lê o período completo uma vez.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _resolveExportTxSnapshots(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime from,
    DateTime to,
  ) async {
    final sid = _effectiveFinanceSessionUid;
    if (sid == null || sid.isEmpty) return docs;
    if (!financeMainPeriodCanServerPage(
      searchLowerTrim: _search,
      statusFilter: _statusFilter,
      categoryFilter: _categoryFilter,
      financeAccountFilterId: _financeAccountFilterId,
    )) {
      return docs;
    }
    if (!_mainPeriodServerPagingActive || !_mainPeriodHasMoreServer) return docs;
    final f0 = DateTime(from.year, from.month, from.day);
    final f1 = DateTime(_from.year, _from.month, _from.day);
    final t0 = DateTime(to.year, to.month, to.day);
    final t1 = DateTime(_to.year, _to.month, _to.day);
    if (f0 != f1 || t0 != t1) return docs;
    try {
      final q = financeMainPeriodFirestoreQuery(
        sessionUid: sid,
        from: from,
        to: to,
        statusFilter: _statusFilter,
        typeFilter: _typeFilter,
      );
      return await firestoreQueryCollectDocumentsBatched(q);
    } catch (_) {
      return docs;
    }
  }

  Future<void> _reloadMainPeriodDocsPull() async {
    final uid = _effectiveFinanceSessionUid;
    if (uid == null) return;
    // Pull-to-refresh explícito: sincroniza lista; saldos só mudam se houver diferença real.
    _mainPeriodLoadGeneration++;
    final g = _mainPeriodLoadGeneration;
    if (mounted) setState(() => _mainPeriodPullRefreshing = true);
    try {
      await _executeMainPeriodLoad(g, uid, preserveExistingDocs: true);
    } finally {
      if (mounted) setState(() => _mainPeriodPullRefreshing = false);
    }
  }

  void _scheduleMainPeriodReloadAfterMutation({
    DateTime? transactionEffectiveDate,
    Iterable<String>? savedDocIds,
  }) {
    unawaited(_applyFinanceMutationSync(
      docIds: savedDocIds,
      transactionEffectiveDate: transactionEffectiveDate,
    ));
  }

  void _scheduleMainPeriodReloadAfterMutationDebounced({
    bool immediate = false,
    bool preserveExistingDocs = true,
    bool accountFilterOnly = false,
  }) {
    final uid = _effectiveFinanceSessionUid;
    if (uid == null || !mounted) return;
    void runReload() {
      if (!mounted) return;
      _mainPeriodLoadGeneration++;
      final g = _mainPeriodLoadGeneration;
      unawaited(
        _executeMainPeriodLoad(
          g,
          uid,
          preserveExistingDocs: preserveExistingDocs,
          accountFilterOnly: accountFilterOnly,
        ),
      );
    }
    _delayedMainPeriodReloadTimer?.cancel();
    if (immediate) {
      runReload();
      return;
    }
    _delayedMainPeriodReloadTimer = Timer(
      const Duration(milliseconds: 380),
      runReload,
    );
  }

  /// UID do documento `users/{id}/…` (titular quando sub-login).
  String? get _effectiveFinanceSessionUid {
    final dataUid = firestoreUserDocIdStrictFromSession();
    if (dataUid.isNotEmpty) return dataUid;
    final current = fa.FirebaseAuth.instance.currentUser?.uid;
    if (current != null && current.isNotEmpty) return current;
    final last = _lastAuthUidForFinancePeriodReset;
    if (last != null && last.isNotEmpty) return last;
    return null;
  }

  /// Saldos por conta no carrossel: mapa do período completo (paginação servidor).
  /// Mantém último valor conhecido durante reload — saldo não «pula» no pull.
  Map<String, double>? get _stripPeriodNetPaidOverride =>
      _serverPagingStripPaidNetByAccount.isNotEmpty ? _serverPagingStripPaidNetByAccount : null;

  Map<String, dynamic> _txDataForMainPeriodDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final patch = _optimisticEditedTxById[doc.id];
    if (patch == null || patch.isEmpty) return doc.data();
    return {...doc.data(), ...patch};
  }

  static bool _financeTxOptimisticFieldEqual(dynamic serverVal, dynamic patchVal) {
    if (serverVal == patchVal) return true;
    if (serverVal is Timestamp && patchVal is Timestamp) {
      return serverVal.seconds == patchVal.seconds && serverVal.nanoseconds == patchVal.nanoseconds;
    }
    if (serverVal is num && patchVal is num) {
      return (serverVal.toDouble() - patchVal.toDouble()).abs() < 1e-9;
    }
    final s = (serverVal ?? '').toString();
    final p = (patchVal ?? '').toString();
    return s == p;
  }

  /// Remove patches quando o snapshot já reflete o que foi gravado (evita overlay eterno).
  void _pruneOptimisticEditedTxAgainstDocs(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (_optimisticEditedTxById.isEmpty) return;
    final byId = <String, Map<String, dynamic>>{
      for (final d in docs) d.id: d.data(),
    };
    for (final id in _optimisticEditedTxById.keys.toList()) {
      final patch = _optimisticEditedTxById[id];
      if (patch == null || patch.isEmpty) continue;
      final server = byId[id];
      if (server == null) continue;
      var matches = true;
      for (final e in patch.entries) {
        final k = e.key;
        if (k == 'type') continue;
        if (k == 'financeAccountId') {
          final sa = (server[k] ?? '').toString().trim();
          final pa = (e.value ?? '').toString().trim();
          if (sa != pa) matches = false;
          continue;
        }
        if (!_financeTxOptimisticFieldEqual(server[k], e.value)) matches = false;
      }
      if (matches) _optimisticEditedTxById.remove(id);
    }
  }

  /// IDs selecionados na grelha que ainda estão pendentes (para confirmar em lote).
  List<String> _gridSelectedPendingIdsAmong(List<QueryDocumentSnapshot<Map<String, dynamic>>> docsVisible) {
    final out = <String>[];
    for (final doc in docsVisible) {
      if (!_gridSelectedIds.contains(doc.id)) continue;
      final d = _txDataForMainPeriodDoc(doc);
      if ((d['status'] ?? 'paid').toString() == 'pending') out.add(doc.id);
    }
    return out;
  }

  void _applyPeriod() {
    final (f, t) = _rangeForPeriod();
    setState(() {
      _from = f;
      _to = t;
      _invalidateRealtimeBalances();
      _resetTxPagination();
    });
  }

  (DateTime, DateTime) _previousPeriodSameLength() {
    final f = DateTime(_from.year, _from.month, _from.day);
    final t = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    final prevEnd = f.subtract(const Duration(days: 1));
    final days = t.difference(f).inDays + 1;
    final prevStart = DateTime(prevEnd.year, prevEnd.month, prevEnd.day).subtract(Duration(days: days - 1));
    return (prevStart, DateTime(prevEnd.year, prevEnd.month, prevEnd.day, 23, 59, 59));
  }

  List<MapEntry<String, double>> _topExpenseCategories(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {int n = 3}) {
    final m = <String, double>{};
    final rs = DateTime(_from.year, _from.month, _from.day);
    final re = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    for (final doc in docs) {
      final d = doc.data();
      if ((d['type'] ?? 'expense').toString() != 'expense') continue;
      final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effective == null || effective.isBefore(rs) || effective.isAfter(re)) continue;
      final cat = (d['category'] ?? '').toString().trim();
      final key = cat.isEmpty ? 'Sem categoria' : cat;
      m[key] = (m[key] ?? 0) + (d['amount'] ?? 0).toDouble().abs();
    }
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  List<double> _sparklineForAccount(String accountId, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final byDay = <DateTime, double>{};
    for (final doc in docs) {
      final d = doc.data();
      if ((d['financeAccountId'] ?? '').toString().trim() != accountId) continue;
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      final day = DateTime(dt.year, dt.month, dt.day);
      final amt = (d['amount'] ?? 0).toDouble();
      final delta = d['type'] == 'income' ? amt : -amt;
      byDay[day] = (byDay[day] ?? 0) + delta;
    }
    final keys = byDay.keys.toList()..sort();
    if (keys.length < 2) return <double>[];
    final take = keys.length > 14 ? keys.sublist(keys.length - 14) : keys;
    var run = 0.0;
    final out = <double>[];
    for (final k in take) {
      run += byDay[k] ?? 0;
      out.add(run);
    }
    return out.length >= 2 ? out : <double>[];
  }

  static const int _kFinancePdfPrepYieldEvery = 120;
  static const int _kFinanceHeavyDocsThreshold = 80;
  static const int _kFinanceHeavyDaysThreshold = 180;
  String _dataStrExport(dynamic ts) {
    if (ts == null) return '';
    if (ts is DateTime) return DateTimeFormats.dateBR.format(ts);
    if (ts is Timestamp) return DateTimeFormats.dateBR.format(ts.toDate());
    return '';
  }

  int _sortMsForExport(dynamic ts) {
    if (ts == null) return 0;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    if (ts is Timestamp) return ts.toDate().millisecondsSinceEpoch;
    return 0;
  }

  bool _isHeavyFinanceExport(int docsCount, DateTime from, DateTime to) {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    final daysSpan = t.difference(f).inDays + 1;
    return docsCount > _kFinanceHeavyDocsThreshold || daysSpan > _kFinanceHeavyDaysThreshold;
  }

  /// Overlay bloqueante durante operações de exportação.
  Future<T> _runWithBlockingDialog<T>({
    required String message,
    required Future<T> Function() action,
  }) async {
    var dialogShown = false;
    if (mounted) {
      dialogShown = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    try {
      return await action();
    } finally {
      if (dialogShown && mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) {
          nav.pop();
        }
      }
    }
  }

  Future<(Uint8List, String, bool)> _buildFinancePdfBytes({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required double saldoAbertura,
    required double totalIncome,
    required double totalExpense,
    required DateTime from,
    required DateTime to,
    required String? filenameSuffix,
  }) async {
    final heavyExport = _isHeavyFinanceExport(docs.length, from, to);
    final periodo =
        '${DateTimeFormats.dateBR.format(from)} a ${DateTimeFormats.dateBR.format(to)}';
    final filenameBase = RelatorioService.reportFilenameFromPeriod(
      'despesa_receita',
      from,
      to,
      filenameSuffix != null && filenameSuffix.isNotEmpty ? '— $filenameSuffix' : null,
    );

    final txRows = <Map<String, dynamic>>[];
    for (var i = 0; i < docs.length; i++) {
      if (i > 0 && i % _kFinancePdfPrepYieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final e = docs[i].data();
      final cat = (e['category'] ?? '').toString().trim();
      final desc = (e['description'] ?? '').toString().trim();
      final isInc = (e['type'] ?? 'expense').toString() == 'income';
      final tituloLinha = desc.isNotEmpty ? desc : (isInc ? 'Receita' : 'Despesa');
      txRows.add({
        'sortMs': _sortMsForExport(e['date']),
        'data': _dataStrExport(e['date']),
        'categoria': cat,
        'titulo': tituloLinha,
        'descricao': RelatorioService.sanitizeForReport(
          (cat.isNotEmpty ? 'Categoria: $cat' : '') +
              (cat.isNotEmpty && desc.isNotEmpty ? ' — ' : '') +
              (desc.isNotEmpty
                  ? 'Descricao: $desc'
                  : (cat.isEmpty ? (isInc ? 'Receita' : 'Despesa') : '')),
        ),
        'tipo': isInc ? 'receita' : 'despesa',
        'valor': _financeAmountToDouble(e['amount']),
      });
    }
    txRows.sort((a, b) => (a['sortMs'] as int).compareTo(b['sortMs'] as int));

    final logo = await RelatorioService.loadPdfLogoBytesOnce();
    final bytes = await gerarPdfFinanceiroSuperExtrato(
      transacoes: txRows,
      nomeUsuario: widget.profile.name,
      conta: _selectedFinanceAccountLabel() ?? 'Todas as contas',
      periodo: periodo,
      saldoAbertura: saldoAbertura,
      totalReceitas: totalIncome,
      totalDespesas: totalExpense,
      logoPngBytes: logo,
    );
    return (bytes, filenameBase, heavyExport);
  }

  /// Exporta o período para PDF (padrão relatórios: preview → imprimir, compartilhar WhatsApp, salvar).
  /// [reportFrom] / [reportTo] permitem emitir relatório de outro intervalo (menu Relatórios financeiros).
  /// Totais de receita/despesa são recalculados a partir dos documentos (inclui leitura completa se a lista usava paginação no Firestore).
  Future<void> _exportPdf(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    double saldoAbertura, {
    DateTime? reportFrom,
    DateTime? reportTo,
    String? pdfFilenameAccountSuffix,
    bool filenameFromMainListFilter = true,
    bool showProgressOverlay = true,
  }) async {
    if (docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum lançamento para exportar.')),
        );
      }
      return;
    }

    final from = reportFrom ?? _from;
    final to = reportTo ?? _to;
    final resolved = await _resolveExportTxSnapshots(docs, from, to);
    if (resolved.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum lançamento para exportar.')),
        );
      }
      return;
    }
    if (resolved.length > kFinancePdfCsvExportMaxDocs) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exportação limitada a $kFinancePdfCsvExportMaxDocs lançamentos. Reduza o período ou os filtros.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    double ti = 0;
    double te = 0;
    for (final doc in resolved) {
      final d = doc.data();
      final amount = _financeAmountToDouble(d['amount']);
      if (d['type'] == 'income') ti += amount;
      if (d['type'] == 'expense') te += amount;
    }

    String? suffix;
    if (filenameFromMainListFilter) {
      suffix = _filenameAccountSuffix();
    } else {
      suffix = pdfFilenameAccountSuffix;
      if (suffix != null && suffix.isNotEmpty) {
        suffix = suffix.replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '_').trim();
        if (suffix.isEmpty) suffix = 'conta';
        if (suffix.length > 48) suffix = suffix.substring(0, 48);
      }
    }

    try {
      final (bytes, filenameBase, heavyExport) = showProgressOverlay
          ? await _runWithBlockingDialog(
              message: 'Gerando PDF…\nAguarde um instante.',
              action: () => _buildFinancePdfBytes(
                docs: resolved,
                saldoAbertura: saldoAbertura,
                totalIncome: ti,
                totalExpense: te,
                from: from,
                to: to,
                filenameSuffix: suffix,
              ),
            )
          : await _buildFinancePdfBytes(
              docs: resolved,
              saldoAbertura: saldoAbertura,
              totalIncome: ti,
              totalExpense: te,
              from: from,
              to: to,
              filenameSuffix: suffix,
            );

      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('O PDF ficou vazio — verifique filtros ou tente novamente.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: bytes, filename: filenameBase),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar PDF: ${friendlyMessage(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// PDF do mesmo conjunto do sheet «conta / todas as contas» (período e filtro de status do sheet).
  Future<void> _exportPdfFromAccountSheet(
    BuildContext sheetContext,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    FinanceAccount? account,
    DateTime from,
    DateTime to,
  ) async {
    if (!widget.profile.hasActiveLicense) {
      if (sheetContext.mounted) mostrarAvisoSeLicencaInativa(sheetContext, widget.profile);
      return;
    }
    if (docs.isEmpty) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(content: Text('Nenhum lançamento para exportar.')));
      }
      return;
    }
    final f = DateTime(from.year, from.month, from.day);
    final tEnd = DateTime(to.year, to.month, to.day, 23, 59, 59);
    try {
      final saldoAbertura = await _loadSaldoAberturaFor(f);
      if (!mounted) return;
      String? suffix;
      if (account != null) {
        var s = account.displayName.replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '_').trim();
        if (s.isEmpty) s = 'conta';
        suffix = s.length > 48 ? s.substring(0, 48) : s;
      }
      await _exportPdf(
        docs,
        saldoAbertura,
        reportFrom: f,
        reportTo: tEnd,
        pdfFilenameAccountSuffix: suffix,
        filenameFromMainListFilter: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar PDF: ${friendlyMessage(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  static const String _kRelatorioSemCategoria = '__sem_categoria__';

  bool _docMatchesExportCategory(Map<String, dynamic> d, String? categoryExact) {
    if (categoryExact == null || categoryExact.isEmpty) return true;
    final cat = (d['category'] ?? '').toString().trim();
    if (categoryExact == _kRelatorioSemCategoria) return cat.isEmpty;
    return FinanceCategoryMerger.sameCategoryGroup(cat, categoryExact);
  }

  /// Mesmos filtros da lista principal (status, tipo, categoria, pesquisa, conta) + [categoryExact] do fluxo «Relatórios premium» (merge de grupo).
  bool _txMatchesPdfFilters(Map<String, dynamic> d, {String? categoryExact}) {
    if (_statusFilter != 'all') {
      final status = (d['status'] ?? 'paid').toString();
      if (status != _statusFilter) return false;
    }
    if (_typeFilter != 'all' && (d['type'] ?? 'expense').toString() != _typeFilter) {
      return false;
    }
    if (categoryExact != null && categoryExact.isNotEmpty) {
      if (!_docMatchesExportCategory(d, categoryExact)) return false;
    } else if (_categoryFilter != null) {
      final c = (d['category'] ?? '').toString().trim();
      if (!FinanceCategoryMerger.sameCategoryGroup(c, _categoryFilter!)) return false;
    }
    if (_search.isNotEmpty) {
      final accLabel = _financeAccountLabelForTx(d) ?? '';
      final text = '${d['category'] ?? ''} ${d['description'] ?? ''} $accLabel'.toLowerCase();
      if (!text.contains(_search)) return false;
    }
    if (_financeAccountFilterId != null) {
      final aid = (d['financeAccountId'] ?? '').toString().trim();
      if (aid != _financeAccountFilterId) return false;
    }
    return true;
  }

  /// Busca lançamentos no intervalo, aplica o mesmo filtro de status da tela e categoria opcional; abre preview do PDF.
  Future<void> _exportFinancialReportForRange(
    DateTime from,
    DateTime to, {
    String? categoryExact,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      if (mounted) mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final f = DateTime(from.year, from.month, from.day);
    var tEnd = DateTime(to.year, to.month, to.day, 23, 59, 59);
    if (tEnd.isBefore(f)) tEnd = DateTime(f.year, f.month, f.day, 23, 59, 59);
    try {
      Query<Map<String, dynamic>> baseRangeQuery() {
        Query<Map<String, dynamic>> q = _txRef()
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(f))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(tEnd))
            .orderBy('date', descending: false);
        if (_statusFilter != 'all') {
          q = q.where('status', isEqualTo: _statusFilter);
        }
        if (_typeFilter != 'all') {
          q = q.where('type', isEqualTo: _typeFilter);
        }
        if (_financeAccountFilterId != null) {
          q = q.where('financeAccountId', isEqualTo: _financeAccountFilterId);
        }
        // Categoria: sempre refinado em [_txMatchesPdfFilters] (case-insensitive / grupo).
        return q;
      }

      // Um único overlay: busca Firestore + geração PDF (evita 2.ª fase «Gerando PDF…» a ficar pendente na Web se as fontes ou o save atrasarem).
      final (bytes, filenameBase, _) = await _runWithBlockingDialog(
        message: 'A preparar o PDF…\nPeríodo da tela: ${_formatPeriodLabelForExport(f, tEnd)}. Filtros de status, tipo, categoria, pesquisa e conta aplicados.',
        action: () async {
          final saldoAbertura = await _loadSaldoAberturaFor(f);
          final allDocs = await firestoreQueryCollectDocumentsBatched(
            baseRangeQuery(),
          ).timeout(
                const Duration(minutes: 3),
                onTimeout: () => throw TimeoutException(
                  'Lançamentos do período: tempo esgotado. Verifique a conexão.',
                ),
              );
          final docs = allDocs.where((doc) {
            return _txMatchesPdfFilters(doc.data(), categoryExact: categoryExact);
          }).toList();
          if (docs.length > kFinancePdfCsvExportMaxDocs) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Exportação limitada a $kFinancePdfCsvExportMaxDocs lançamentos. Reduza o período ou os filtros.',
                  ),
                  backgroundColor: AppColors.error,
                ),
              );
            }
            return (Uint8List(0), '', false);
          }
          if (docs.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Nenhum lançamento para o PDF: ajuste o período ou os filtros da tela.'),
                ),
              );
            }
            return (Uint8List(0), '', false);
          }
          double totalIncome = 0;
          double totalExpense = 0;
          for (var i = 0; i < docs.length; i++) {
            if (i > 0 && i % _kFinancePdfPrepYieldEvery == 0) {
              await Future<void>.delayed(Duration.zero);
            }
            final d = docs[i].data();
            final amount = _financeAmountToDouble(d['amount']);
            if (d['type'] == 'income') totalIncome += amount;
            if (d['type'] == 'expense') totalExpense += amount;
          }
          return _buildFinancePdfBytes(
            docs: docs,
            saldoAbertura: saldoAbertura,
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            from: f,
            to: tEnd,
            filenameSuffix: _filenameAccountSuffix(),
          );
        },
      );
      if (bytes.isEmpty) return;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: bytes, filename: filenameBase),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao preparar o PDF: ${friendlyMessage(e)}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _formatPeriodLabelForExport(DateTime from, DateTime to) {
    final a = DateTimeFormats.dateBR.format(from);
    final b = DateTimeFormats.dateBR.format(to);
    return '$a a $b';
  }

  Future<void> _exportCsvFinancialReportForRange(
    DateTime from,
    DateTime to, {
    String? categoryExact,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      if (mounted) mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final f = DateTime(from.year, from.month, from.day);
    var tEnd = DateTime(to.year, to.month, to.day, 23, 59, 59);
    if (tEnd.isBefore(f)) tEnd = DateTime(f.year, f.month, f.day, 23, 59, 59);
    try {
      final allDocs = await firestoreQueryCollectDocumentsBatched(
        _txRef()
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(f))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(tEnd))
            .orderBy('date', descending: false),
      );
      final docs = allDocs.where((doc) {
        return _txMatchesPdfFilters(doc.data(), categoryExact: categoryExact);
      }).toList();
      if (docs.length > kFinancePdfCsvExportMaxDocs) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exportação CSV limitada a $kFinancePdfCsvExportMaxDocs lançamentos. Reduza o período ou os filtros.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
      if (docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum lançamento para exportar.')));
        return;
      }
      final csv = FinanceExportCsv.buildFromFirestoreDocs(docs, accounts: _financeAccounts);
      final accSuf = _filenameAccountSuffix();
      final base = RelatorioService.reportFilenameFromPeriod(
        'despesa_receita',
        f,
        tEnd,
        accSuf != null && accSuf.isNotEmpty ? '— $accSuf' : null,
      );
      await FinanceExportCsv.saveOrShare('$base.csv', csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV gerado. Escolha onde salvar ou compartilhar.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro CSV: ${friendlyMessage(e)}'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _openFinancialReportsPremiumSheet() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return _FinanceReportsPremiumSheet(
          screenFrom: _from,
          screenTo: _to,
          uid: firestoreUserDocIdForAppShell(widget.uid),
          statusFilter: _statusFilter,
          filenameAccountSuffix: _filenameAccountSuffix(),
          semCategoriaToken: _kRelatorioSemCategoria,
          onExportPdf: (opts) {
            Navigator.of(ctx).pop();
            unawaited(_exportFinancialReportForRange(
              opts.from,
              opts.to,
              categoryExact: opts.categoryExact,
            ));
          },
          onExportCsv: (opts) {
            Navigator.of(ctx).pop();
            unawaited(_exportCsvFinancialReportForRange(opts.from, opts.to, categoryExact: opts.categoryExact));
          },
        );
      },
    );
  }

  /// Saldo de abertura: soma de receitas e despesas pagas com data efetiva anterior ao início do período (igual painel e relatórios).
  Future<double> _loadSaldoAberturaFor(DateTime periodStart) async {
    final b = await _loadSaldoAberturaBundle(periodStart);
    return b.total;
  }

  /// Saldo de abertura: total rápido via [finance_month_buckets] (servidor); contas em 2ª fase se necessário.
  Future<({double total, Map<String, double> byAccount})> _loadSaldoAberturaBundle(
    DateTime periodStart, {
    bool withAccounts = false,
  }) async {
    if (fa.FirebaseAuth.instance.currentUser == null) {
      return (total: 0.0, byAccount: const <String, double>{});
    }
    return FinanceOpeningBalanceService.load(
      uid: widget.uid,
      periodStart: periodStart,
      loadAccounts: withAccounts,
    );
  }

  CollectionReference<Map<String, dynamic>> _txRef() {
    final id = firestoreUserDocIdForAppShell(widget.uid);
    return FirebaseFirestore.instance.collection('users').doc(id).collection('transactions');
  }

  /// Só pendentes — evita carregar todos os lançamentos nas faixas azul/laranja (exige índice
  /// `type`+`status`+`date` no Firestore, ver `firestore.indexes.json`).
  static const int _kPendingStreamLimit = 500;

  Query<Map<String, dynamic>> _txRefPendingIncomes() => _txRef()
      .where('type', isEqualTo: 'income')
      .where('status', isEqualTo: 'pending')
      .orderBy('date', descending: false)
      .limit(_kPendingStreamLimit);

  Query<Map<String, dynamic>> _txRefPendingExpenses() => _txRef()
      .where('type', isEqualTo: 'expense')
      .where('status', isEqualTo: 'pending')
      .orderBy('date', descending: false)
      .limit(_kPendingStreamLimit);

  /// Mesma rota do painel inicial: colar SMS / texto inteligente (evita duplicar blocos gigantes na árvore).
  Future<void> _abrirLancamentoInteligente() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (firestoreUserDocIdStrictFromSession().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão a carregar — aguarde um instante e toque de novo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<SmartInputPopResult?>(
      MaterialPageRoute<SmartInputPopResult?>(
        builder: (_) => SmartInputScreen(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          profile: widget.profile,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result != null && result.hasCreated && mounted) {
      if (!context.mounted) return;
      _scheduleMainPeriodReloadAfterMutation(
        savedDocIds: result.createdTransactionIds,
      );
      final n = result.createdTransactionIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n > 1 ? '$n lançamentos guardados.' : 'Lançamento guardado.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () async {
              await FinanceService.deleteTransactionsByDocumentIds(
                uid: firestoreUserDocIdForAppShell(widget.uid),
                context: context,
                documentIds: result.createdTransactionIds,
              );
              if (context.mounted) setState(() => _invalidateRealtimeBalances());
            },
          ),
        ),
      );
    }
  }

  /// Confirma vários pagamentos/recebimentos: mesma data + mesmo banco (sem comprovante em lote).
  Future<void> _confirmarPagamentoEmLote(
    BuildContext context,
    List<String> docIds, {
    required String successSnackBar,
    bool? isIncome,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final unique = docIds.toSet().where((e) => e.trim().isNotEmpty).toList();
    if (unique.isEmpty) return;

    var batchIsIncome = isIncome;
    double sum = 0;
    var incomeCount = 0;
    var expenseCount = 0;
    for (var i = 0; i < unique.length && i < 30; i++) {
      final snap = await _txRef().doc(unique[i]).get();
      final d = snap.data() ?? {};
      sum += (d['amount'] as num?)?.toDouble() ?? 0;
      if ((d['type'] ?? 'expense').toString() == 'income') {
        incomeCount++;
      } else {
        expenseCount++;
      }
    }
    batchIsIncome ??= incomeCount >= expenseCount;
    final totalAmount = sum;

    final financeAccounts = _financeAccounts.isNotEmpty
        ? List<FinanceAccount>.from(_financeAccounts)
        : await FinanceAccountsService().listOnce(firestoreUserDocIdForAppShell(widget.uid));
    if (!context.mounted) return;

    final result = await showFinanceConfirmPaymentBatchSheet(
      context: context,
      isIncome: batchIsIncome,
      financeAccounts: financeAccounts,
      itemCount: unique.length,
      totalAmountPreview: totalAmount,
    );
    if (result == null || !mounted) return;

    setState(() {
      for (final id in unique) {
        _optimisticPaidIds.add(id);
      }
    });

    try {
      await commitFinanceConfirmPaymentBatch(
        txCol: _txRef(),
        docIds: unique,
        uid: widget.uid,
        result: result,
      );
      if (!mounted) return;
      final confTs = Timestamp.fromDate(result.paymentDate);
      final aid = result.financeAccountId?.trim() ?? '';
      setState(() {
        for (final id in unique) {
          _optimisticPaidIds.remove(id);
          final prev = _optimisticEditedTxById[id];
          _optimisticEditedTxById[id] = {
            if (prev != null) ...prev,
            'status': 'paid',
            'paidAt': confTs,
            'effectiveDate': confTs,
            if (aid.isNotEmpty) 'financeAccountId': aid else 'financeAccountId': '',
          };
        }
      });
      unawaited(_applyFinanceMutationSync(
        docIds: unique,
        transactionEffectiveDate: result.paymentDate,
      ));
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successSnackBar),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final id in unique) {
            _optimisticPaidIds.remove(id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _addTx(BuildContext context, String type) async {
    if (!context.mounted) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final result = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => NovoLancamentoPage(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          initialType: type,
          canAttachReceipt: widget.profile.temAcessoPremium,
          hasActiveLicense: widget.profile.hasActiveLicense,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result == null || !context.mounted) return;
    try {
      final saveResult = await TransactionSaveService.saveFromNovoLancamentoResult(
        uid: firestoreUserDocIdForAppShell(widget.uid),
        data: result,
        context: context,
      );
      if (saveResult == null || !mounted) return;
      final date = result['date'] is DateTime ? result['date'] as DateTime : DateTime.now();
      final effectiveDate =
          FinanceLineOpening.effectiveDateTimeFromMap(result) ?? date;
      setState(() {
        final d = DateTime(date.year, date.month, date.day);
        if (d.isBefore(DateTime(_from.year, _from.month, _from.day))) _from = d;
        if (d.isAfter(DateTime(_to.year, _to.month, _to.day))) _to = d;
      });
      _scheduleMainPeriodReloadAfterMutation(
        transactionEffectiveDate: effectiveDate,
        savedDocIds: saveResult.docIds,
      );
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar lançamento: ${e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '')}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      debugPrint('_addTx save error: $e\n$st');
    }
  }

  Future<void> _openTransferBetweenAccounts(BuildContext context) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (_financeAccounts.length < 2) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastre ao menos duas contas para transferir valores.')),
        );
      }
      return;
    }

    final result = await FinanceTransferBottomSheet.show(
      context,
      accounts: _financeAccounts,
      initialFromId: _financeAccounts.first.id,
      initialToId: _financeAccounts.length > 1 ? _financeAccounts[1].id : _financeAccounts.first.id,
    );
    if (result == null || !context.mounted) return;

    final fromAcc = _financeAccounts.firstWhere((a) => a.id == result.fromId);
    final toAcc = _financeAccounts.firstWhere((a) => a.id == result.toId);
    final transferAt = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(result.selectedCalendarDay);

    try {
      await FinanceTransferService.instance.createTransfer(
        uid: widget.uid,
        fromAcc: fromAcc,
        toAcc: toAcc,
        amount: result.amount,
        selectedCalendarDay: result.selectedCalendarDay,
        note: result.note,
        receiptBytes: result.receiptBytes,
        receiptName: result.receiptName,
        receiptMime: result.receiptMime,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao transferir: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (mounted) {
      _scheduleMainPeriodReloadAfterMutation(transactionEffectiveDate: transferAt);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transferência registrada (${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(transferAt)}): ${CurrencyFormats.formatBRL(result.amount)}',
          ),
        ),
      );
    }
  }

  /// Confirma pagamento/recebimento: data, banco/conta (opcional trocar) e comprovante.
  Future<void> _confirmarPagamento(BuildContext context, String docId) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (docId.isEmpty) return;
    final preSnap = await _txRef().doc(docId).get();
    final preData = preSnap.data() ?? {};
    final txType = (preData['type'] ?? 'expense').toString();
    final isIncome = txType == 'income';
    final preEffectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(preData) ??
        (preData['date'] as Timestamp?)?.toDate();
    final financeAccounts = _financeAccounts.isNotEmpty
        ? List<FinanceAccount>.from(_financeAccounts)
        : await FinanceAccountsService().listOnce(firestoreUserDocIdForAppShell(widget.uid));
    final rawAid = (preData['financeAccountId'] ?? '').toString().trim();
    FinanceAccount? cardAccount;
    for (final a in financeAccounts) {
      if (a.id == rawAid && a.isCreditCardProduct) {
        cardAccount = a;
        break;
      }
    }
    final isCardFatura = !isIncome &&
        cardAccount != null &&
        (preData['status'] ?? 'paid').toString() == 'pending';
    if (!context.mounted) return;

    final FinanceConfirmPaymentSheetResult? result;
    if (isCardFatura) {
      final debitBanks = FinanceAccountBalanceUtils.debitBankAccounts(financeAccounts);
      result = await showFinanceConfirmPaymentBatchSheet(
        context: context,
        isIncome: false,
        financeAccounts: debitBanks,
        itemCount: 1,
        totalAmountPreview: (preData['amount'] as num?)?.toDouble(),
        creditCardFaturaPayment: true,
        cardDisplayName: cardAccount.displayName,
      );
    } else {
      result = await showFinanceConfirmPaymentSheet(
        context: context,
        isIncome: isIncome,
        financeAccounts: financeAccounts,
        initialFinanceAccountId: rawAid.isEmpty ? null : rawAid,
        orphanAccountId: rawAid,
        canAttachReceipt: widget.profile.temAcessoPremium,
        amountPreview: (preData['amount'] as num?)?.toDouble(),
        categoryPreview: (preData['category'] ?? '').toString(),
        descriptionPreview: (preData['description'] ?? '').toString(),
      );
    }
    if (result == null || !mounted) return;
    final paymentResult = result!;

    setState(() => _optimisticPaidIds.add(docId));
    try {
      await commitFinanceConfirmPayment(
        txRef: _txRef().doc(docId),
        uid: widget.uid,
        result: paymentResult,
        creditCardFaturaPayment: isCardFatura,
      );
      if (!mounted) return;
      final confTs = Timestamp.fromDate(paymentResult.paymentDate);
      final aid = paymentResult.financeAccountId?.trim() ?? '';
      setState(() {
        _optimisticPaidIds.remove(docId);
        final prev = _optimisticEditedTxById[docId];
        _optimisticEditedTxById[docId] = {
          if (prev != null) ...prev,
          'status': 'paid',
          'paidAt': confTs,
          'effectiveDate': confTs,
          if (isCardFatura) ...{
            'financeAccountId': rawAid,
            if (aid.isNotEmpty) 'paidFromFinanceAccountId': aid,
          } else if (aid.isNotEmpty)
            'financeAccountId': aid
          else
            'financeAccountId': '',
        };
        _invalidateRealtimeBalances(
          transactionEffectiveDate: preEffectiveDate ?? paymentResult.paymentDate,
        );
      });
      unawaited(_applyFinanceMutationSync(
        docIds: [docId],
        transactionEffectiveDate: paymentResult.paymentDate,
      ));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isIncome ? 'Recebimento confirmado.' : 'Pagamento confirmado.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticPaidIds.remove(docId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao confirmar: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _editTx(BuildContext context, String docId, Map<String, dynamic> current, String type) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final pairId = (current['transferPairId'] ?? '').toString().trim();
    if (pairId.isNotEmpty) {
      final accounts = _financeAccounts.isNotEmpty
          ? List<FinanceAccount>.from(_financeAccounts)
          : await FinanceAccountsService().listOnce(firestoreUserDocIdForAppShell(widget.uid));
      if (!context.mounted) return;
      final saved = await FinanceTransferBottomSheet.showEdit(
        context,
        uid: widget.uid,
        profile: widget.profile,
        pairId: pairId,
        accounts: accounts,
        logModulo: 'Financeiro',
      );
      if (saved && mounted) {
        final effectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(current) ??
            (current['date'] as Timestamp?)?.toDate();
        unawaited(_applyFinanceMutationSync(transactionEffectiveDate: effectiveDate));
      }
      return;
    }
    final saved = await showFinanceTransactionEditDialog(
      context: context,
      uid: widget.uid,
      profile: widget.profile,
      docId: docId,
      current: current,
      type: type,
      financeAccountsPreloaded:
          _financeAccounts.isNotEmpty ? List<FinanceAccount>.from(_financeAccounts) : null,
      logModulo: 'Financeiro',
      onSaved: (id, patch, effectiveDate) {
        if (!mounted) return;
        setState(() {
          _invalidateRealtimeBalances(transactionEffectiveDate: effectiveDate);
          _optimisticEditedTxById[id] = patch;
        });
        unawaited(_applyFinanceMutationSync(
          docIds: [id],
          transactionEffectiveDate: effectiveDate,
        ));
      },
    );
    if (!saved) return;
  }

  Future<void> _deleteTx(BuildContext context, String docId) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;
    final snap = await _txRef().doc(docId).get();
    final data = snap.data() ?? {};
    final type = (data['type'] ?? 'expense').toString();
    final amount = (data['amount'] ?? 0).toDouble();
    final category = (data['category'] ?? '').toString();
    final pairId = (data['transferPairId'] ?? '').toString().trim();
    if (pairId.isNotEmpty) {
      final pairSnap = await _txRef().where('transferPairId', isEqualTo: pairId).get();
      for (final pairDoc in pairSnap.docs) {
        await pairDoc.reference.delete();
      }
    } else {
      await _txRef().doc(docId).delete();
    }
    if (mounted) {
      final effectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(data) ??
          (data['date'] as Timestamp?)?.toDate();
      setState(() {
        _mainPeriodDocs.removeWhere((d) => d.id == docId);
      });
      unawaited(_applyFinanceMutationSync(
        removedDocIds: [docId],
        transactionEffectiveDate: effectiveDate,
      ));
    }
    HapticFeedback.lightImpact();
    await LogsService().saveLog(
      modulo: 'Financeiro',
      acao: type == 'income' ? 'Excluiu receita' : 'Excluiu despesa',
      detalhes: '${category.isEmpty ? 'Categoria' : category} • ${CurrencyFormats.formatBRL(amount)}',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lançamento excluído.')));
    }
  }

  /// Exclui vários lançamentos (confirma uma vez, depois exclui em lote).
  Future<void> _deleteTxBatch(BuildContext context, List<String> docIds) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (docIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamentos?'),
        content: Text('${docIds.length} lançamento(s) serão excluídos. Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    int deleted = 0;
    for (final id in docIds) {
      try {
        await _txRef().doc(id).delete();
        deleted++;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _mainPeriodDocs.removeWhere((d) => docIds.contains(d.id));
      });
      unawaited(_applyFinanceMutationSync(removedDocIds: docIds));
    }
    if (context.mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$deleted lançamento(s) excluído(s).')));
    }
  }

  /// Remove duplicatas por docId (proteção extra se algum reload acumular chunks).
  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _dedupeMainPeriodDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in docs) {
      byId[d.id] = d;
    }
    return byId.values.toList();
  }

  /// Totais do período a partir dos docs visíveis.
  ({double income, double expense}) _sumPeriodTotalsFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    String? statusFilter,
  }) {
    final sf = statusFilter ?? _statusFilter;
    final rs = DateTime(_from.year, _from.month, _from.day);
    final re = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    double inc = 0;
    double exp = 0;
    final seen = <String>{};
    for (final doc in docs) {
      if (!seen.add(doc.id)) continue;
      final d = _txDataForMainPeriodDoc(doc);
      if (sf != 'all' && (d['status'] ?? 'paid').toString() != sf) continue;
      final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effective == null || effective.isBefore(rs) || effective.isAfter(re)) continue;
      final amount = _financeAmountToDouble(d['amount']);
      final type = (d['type'] ?? 'expense').toString();
      if (type == 'income') {
        inc += amount;
      } else {
        exp += amount.abs();
      }
    }
    return (income: inc, expense: exp);
  }

  /// Saldo acumulado consolidado («Todas as contas») — abertura + movimentos pagos do período.
  /// Regra fixa: abertura + (receitas − despesas) do período; nunca soma só contas com banco
  /// (excluiria lançamentos sem conta e mudava valor entre refresh e agregado).
  double _saldoAcumuladoConsolidado({
    required double saldoAbertura,
    required double balancePeriodFallback,
    Map<String, double>? periodNetByAccount,
    String? accountFilterId,
    required Map<String, double> openingByAccount,
  }) {
    final filterId = accountFilterId?.trim();
    if (filterId != null && filterId.isNotEmpty) {
      final opening = openingByAccount[filterId] ?? 0.0;
      final period = periodNetByAccount?[filterId];
      if (period != null) return opening + period;
      return opening + balancePeriodFallback;
    }
    return saldoAbertura + balancePeriodFallback;
  }

  /// Movimento líquido pago do período (prioriza agregado mesclado quando lista paginada).
  double _periodNetPaidConsolidated({
    required double fallbackFromVisiblePaidDocs,
    ({double income, double expense})? serverKpis,
  }) {
    if (_mainPeriodServerPagingActive && serverKpis != null) {
      return serverKpis.income - serverKpis.expense;
    }
    return fallbackFromVisiblePaidDocs;
  }

  Set<String> get _creditCardAccountIds =>
      FinanceAccountBalanceUtils.creditCardAccountIds(_financeAccounts);

  /// Saldo líquido por conta **no período**, só lançamentos pagos com data efetiva.
  /// Cartão de crédito não movimenta saldo; pagamento de fatura debita [paidFromFinanceAccountId].
  Map<String, double> _netByFinanceAccountIdPaidEffective(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime from,
    DateTime to,
  ) {
    return FinanceAccountBalanceUtils.netPaidByAccountEffective(
      docs: docs,
      from: from,
      to: to,
      creditCardIds: _creditCardAccountIds,
    );
  }

  static Map<String, double> _mergeAccountBalances(
    Map<String, double> openingByAccount,
    Map<String, double> periodByAccount,
  ) {
    final out = <String, double>{...openingByAccount};
    periodByAccount.forEach((id, val) {
      out[id] = (out[id] ?? 0) + val;
    });
    return out;
  }

  /// Botões `FilledButton.tonal*` na barra de lançamentos: fundo + contorno explícitos para o rótulo e o ícone
  /// permanecerem legíveis (Material 3 sem `backgroundColor` pode fundir cor do texto com o preenchimento).
  ButtonStyle _financeToolbarTonalFilledStyle({
    EdgeInsetsGeometry? padding,
    VisualDensity? visualDensity,
    Size? minimumSize,
  }) {
    return FilledButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.26), width: 1),
      ),
      visualDensity: visualDensity ?? VisualDensity.compact,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: minimumSize ?? const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  Widget _financeAccountMiniCard(
    BuildContext context, {
    required bool selected,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required IconData icon,
    FinanceBankPreset? bankPreset,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Widget? footer,
    String? typeBadge,
    bool creditCardStyle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 148,
            height: 108,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 2.4 : 0.8),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: selected ? 0.45 : 0.22),
                  blurRadius: selected ? 12 : 7,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (creditCardStyle) const FinanceCreditCardPattern(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: bankPreset != null
                              ? FinanceBankBrandThumb(
                                  preset: bankPreset,
                                  size: 26,
                                  onBrandGradient: true,
                                  fallbackIcon: icon,
                                )
                              : Icon(icon, color: Colors.white, size: 20),
                        ),
                        const Spacer(),
                        if (selected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      ],
                    ),
                    if (typeBadge != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: creditCardStyle
                              ? const Color(0xFFFBBF24).withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: creditCardStyle
                                ? const Color(0xFFFDE68A).withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          typeBadge.toUpperCase(),
                          style: TextStyle(
                            color: creditCardStyle ? const Color(0xFFFDE68A) : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 8.5,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                        height: 1.12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 5),
                      footer,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openBulkAssignFromStrip(BuildContext context, {required int semContaNoPainel}) {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FinanceBulkAssignScreen(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          profile: widget.profile,
          initialRangeFrom: _from,
          initialRangeTo: _to,
          semContaNoPainelFinanceiro: semContaNoPainel,
        ),
      ),
    );
  }

  /// Painel por conta: gráficos por categoria + edição / exclusão (toque no cartão banco/cartão).
  void _openFinanceAccountCategoryBreakdown(BuildContext context, FinanceAccount account) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FinanceAccountCategorySheet(
        uid: firestoreUserDocIdForAppShell(widget.uid),
        profile: widget.profile,
        account: account,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        onEditTransaction: _editTx,
        onDeleteTransaction: _deleteTx,
        onDeleteBatch: _deleteTxBatch,
        onConfirmPayment: _confirmarPagamento,
        onAttachReceipt: _attachReceipt,
        onExportPdf: (c, docs) => _exportPdfFromAccountSheet(c, docs, account, _from, _to),
        onApplyAccountFilter: (id) {
          if (!mounted) return;
          _applyFinanceAccountFilter(id);
        },
        openingBalanceHint: _saldoAberturaCached?.byAccount[account.id],
        financeAccounts: _financeAccounts,
        optimisticPaidIds: _optimisticPaidIds,
      ),
    );
  }

  /// Consolidado **Todas as contas**: mesmos gráficos e edição que um banco/cartão, sem filtrar por conta.
  void _openAllAccountsCategoryBreakdown(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FinanceAccountCategorySheet(
        uid: firestoreUserDocIdForAppShell(widget.uid),
        profile: widget.profile,
        account: null,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        onEditTransaction: _editTx,
        onDeleteTransaction: _deleteTx,
        onDeleteBatch: _deleteTxBatch,
        onConfirmPayment: _confirmarPagamento,
        onAttachReceipt: _attachReceipt,
        onExportPdf: (c, docs) => _exportPdfFromAccountSheet(c, docs, null, _from, _to),
        onApplyAccountFilter: (id) {
          if (!mounted) return;
          _applyFinanceAccountFilter(id);
        },
        openingBalanceHint: _saldoAberturaCached?.total,
        financeAccounts: _financeAccounts,
        optimisticPaidIds: _optimisticPaidIds,
      ),
    );
  }

  List<double> _sparklineTodasContas(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final byDay = <DateTime, double>{};
    for (final doc in docs) {
      final d = doc.data();
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      final day = DateTime(dt.year, dt.month, dt.day);
      final amt = (d['amount'] ?? 0).toDouble();
      final delta = d['type'] == 'income' ? amt : -amt;
      byDay[day] = (byDay[day] ?? 0) + delta;
    }
    final keys = byDay.keys.toList()..sort();
    if (keys.length < 2) return <double>[];
    final take = keys.length > 14 ? keys.sublist(keys.length - 14) : keys;
    var run = 0.0;
    final out = <double>[];
    for (final k in take) {
      run += byDay[k] ?? 0;
      out.add(run);
    }
    return out.length >= 2 ? out : <double>[];
  }

  Widget? _sparklineFooterTodas(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final sp = _sparklineTodasContas(docs);
    if (sp.length < 2) return null;
    return FinanceSparkline(values: sp, color: Colors.white.withValues(alpha: 0.92));
  }

  Widget _buildFinanceAccountsStrip(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required Map<String, double> openingByAccount,
    /// Igual ao cartão «Saldo (acum.)»: período filtrado + saldo de abertura (meses anteriores ou ano anterior).
    required double saldoAcumuladoConsolidado,
    required int semContaCount,
    /// Quando a lista usa paginação no servidor, saldos por conta vêm deste mapa (período completo).
    Map<String, double>? stripPeriodNetPaidOverride,
  }) {
    final byAccPeriod = stripPeriodNetPaidOverride ??
        _netByFinanceAccountIdPaidEffective(docs, _from, _to);
    final byAcc = _mergeAccountBalances(openingByAccount, byAccPeriod);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color.lerp(AppColors.primary, AppColors.accent, 0.5)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.pie_chart_outline_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saldos por conta',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A237E)),
                    ),
                    if (_mainPeriodServerPagingActive && _mainPeriodHasMoreServer)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'A lista mostra os lançamentos em páginas — use «Carregar mais do servidor» para ver mais linhas. Os saldos por conta são atualizados com todos os movimentos pagos do período.',
                          style: TextStyle(fontSize: 11, height: 1.3, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (semContaCount > 0) ...[
                      const SizedBox(height: 6),
                      Material(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _openBulkAssignFromStrip(context, semContaNoPainel: semContaCount),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade800,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$semContaCount',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'sem conta',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.orange.shade900),
                                ),
                                Icon(Icons.chevron_right_rounded, size: 18, color: Colors.orange.shade800),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: widget.profile.hasActiveLicense
                      ? () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => FinanceAccountsScreen(uid: firestoreUserDocIdForAppShell(widget.uid), profile: widget.profile),
                            ),
                          );
                        }
                      : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: const Text('Bancos e cartões'),
                ),
                TextButton.icon(
                  onPressed: widget.profile.hasActiveLicense
                      ? () {
                          Navigator.of(context)
                              .push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => CategoriesConfigScreen(uid: firestoreUserDocIdForAppShell(widget.uid)),
                            ),
                          )
                              .then((_) {
                            if (mounted) _refreshCategoryFilterOptions();
                          });
                        }
                      : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                  icon: const Icon(Icons.category_rounded, size: 18),
                  label: const Text('Categorias'),
                ),
                TextButton.icon(
                  onPressed: widget.profile.hasActiveLicense
                      ? () => _openBulkAssignFromStrip(context, semContaNoPainel: semContaCount)
                      : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Atribuir em massa'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Toque em Todas as contas ou num banco/cartão para ver gráficos e lançamentos. Segure e arraste um banco para reordenar — Todas as contas fica sempre primeiro.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500, height: 1.35),
          ),
          const SizedBox(height: 14),
          if (!_financeAccountsStreamPrimed && _financeAccounts.isEmpty)
            SizedBox(
              height: 128,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SkeletonLoader(
                      width: 152,
                      height: 128,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            )
          else if (_financeAccounts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cadastre suas contas para ver o saldo de cada uma neste período.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: widget.profile.hasActiveLicense
                        ? () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => FinanceAccountsScreen(uid: firestoreUserDocIdForAppShell(widget.uid), profile: widget.profile),
                              ),
                            );
                          }
                        : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('Cadastrar agora'),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 128,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _pendingExpensesStream,
        initialData: _lastPendingExpensesSnap,
                builder: (context, pendingSnap) {
                  final faturaByCard = FinanceAccountBalanceUtils.faturaAbertaByCardId(
                    pendingSnap.data?.docs ?? const [],
                    creditCardIds: _creditCardAccountIds,
                  );
                  final accountsStrip = _visibleAccountsForStrip(byAcc, faturaByCard: faturaByCard);
                  return ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (ctx, _) {
                          final t = Curves.easeOut.transform(animation.value);
                          return Material(
                            color: Colors.transparent,
                            elevation: 8 * t,
                            shadowColor: Colors.black.withValues(alpha: 0.35 * t),
                            borderRadius: BorderRadius.circular(18),
                            child: child,
                          );
                        },
                      );
                    },
                    header: _financeAccountMiniCard(
                      context,
                      selected: _financeAccountFilterId == null,
                      title: 'Todas as contas',
                      subtitle: CurrencyFormats.formatBRL(saldoAcumuladoConsolidado),
                      gradient: [AppColors.primary, AppColors.deepBlue],
                      icon: Icons.dashboard_rounded,
                      bankPreset: null,
                      onTap: () => _onFinanceStripCardTap(context, null),
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        unawaited(_openStripLongPressMenu(context));
                      },
                      footer: _sparklineFooterTodas(docs),
                    ),
                    itemCount: accountsStrip.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex--;
                      if (oldIndex == newIndex) return;
                      await _reorderFinanceAccountsStrip(accountsStrip, oldIndex, newIndex);
                    },
                    itemBuilder: (ctx, i) {
                      final a = accountsStrip[i];
                      final net = byAcc[a.id] ?? 0;
                      final vis = financeAccountVisualFor(a);
                      final sp = _sparklineForAccount(a.id, docs);
                      final isCard = a.isCreditCardProduct;
                      final fatura = faturaByCard[a.id] ?? 0;
                      final card = _financeAccountMiniCard(
                        context,
                        selected: _financeAccountFilterId == a.id,
                        title: a.displayName,
                        subtitle: isCard
                            ? 'Fatura ${CurrencyFormats.formatBRL(fatura)}'
                            : CurrencyFormats.formatBRL(net),
                        gradient: vis.gradient,
                        icon: vis.icon,
                        bankPreset: a.preset,
                        typeBadge: vis.badgeLabel,
                        creditCardStyle: vis.isCreditCardStyle,
                        onTap: () => _onFinanceStripCardTap(context, a),
                        footer: sp.length >= 2
                            ? FinanceSparkline(values: sp, color: Colors.white.withValues(alpha: 0.92))
                            : null,
                      );
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey<String>('strip_${a.id}'),
                        index: i,
                        child: Material(
                          color: Colors.transparent,
                          child: card,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          if (_financeAccountFilterId != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  avatar: Icon(Icons.filter_alt_off_rounded, size: 18, color: AppColors.primary),
                  label: const Text('Limpar filtro de conta'),
                  onPressed: () => _applyFinanceAccountFilter(null),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openFinanceInsightSheet({
    required FinanceInsightScope scope,
    required DateTime initialFrom,
    required DateTime initialTo,
    String? initialCategoryExact,
  }) async {
    if (!mounted) return;
    _ensureSaldoAberturaForPeriod(initialFrom);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FinanceInsightSheet(
        uid: firestoreUserDocIdForAppShell(widget.uid),
        initialScope: scope,
        initialFrom: initialFrom,
        initialTo: initialTo,
        initialCategoryExact: initialCategoryExact,
        statusFilter: _statusFilter,
        search: _search,
        financeAccountFilterId: _financeAccountFilterId,
        financeAccountFilterLabel: _financeAccountFilterLabelForInsight(),
        openingBalanceHint: _saldoAberturaCached?.total,
        openingByAccountHint: _saldoAberturaCached?.byAccount,
        onEdit: (docId, current, type) => _editTx(context, docId, current, type),
        onDelete: (docId) => _deleteTx(context, docId),
      ),
    );
  }

  Future<void> _openFinanceCategoriesFullscreen() async {
    if (!mounted) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => FinanceCategoriesFullscreenPage(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          profile: widget.profile,
          from: _from,
          to: _to,
          statusFilter: _statusFilter,
          financeAccountFilterId: _financeAccountFilterId,
          searchLower: _search,
          onCategoryTap: (sheetContext, categoryName) async {
            await showModalBottomSheet<void>(
              context: sheetContext,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              builder: (_) => FinanceInsightSheet(
                uid: firestoreUserDocIdForAppShell(widget.uid),
                initialScope: FinanceInsightScope.expense,
                initialFrom: _from,
                initialTo: _to,
                initialCategoryExact: categoryName,
                statusFilter: _statusFilter,
                search: _searchCtrl.text,
                financeAccountFilterId: _financeAccountFilterId,
                financeAccountFilterLabel: _financeAccountFilterLabelForInsight(),
                openingBalanceHint: _saldoAberturaCached?.total,
                openingByAccountHint: _saldoAberturaCached?.byAccount,
                onEdit: (docId, current, type) => _editTx(sheetContext, docId, current, type),
                onDelete: (docId) => _deleteTx(sheetContext, docId),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openFinanceAssistantInsightsPage({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required double totalIncome,
    required double totalExpense,
    required double balancePeriod,
  }) async {
    if (!mounted) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FinanceAssistantInsightsPage(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          profile: widget.profile,
          from: _from,
          to: _to,
          statusFilter: _statusFilter,
          typeFilter: _typeFilter,
          docs: docs,
          totalIncome: totalIncome,
          totalExpense: totalExpense,
          balancePeriod: balancePeriod,
        ),
      ),
    );
  }

  /// Se a query pendentes falhar (ex.: índice ainda a propagar), evita travar a UI toda.
  Widget _buildPendingStreamErrorBar(String title, Object? err, Color accent) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade800.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: 0.5), width: 3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_tethering_error_rounded, color: Colors.amber.shade900, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$title — faça o deploy dos índices do Firestore (p.ex. `firebase deploy --only firestore:indexes`). '
                  '${kDebugMode ? (err?.toString() ?? '') : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.brown.shade900, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Quadro azul: receitas pendentes. Respeita preferências de receitas fixas (mostrar / próximos meses).
  Widget _buildReceitasPendentesBand(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _fixedIncomePrefsStream,
      initialData: _lastFixedIncomePrefs,
      builder: (context, prefsSnap) {
        final showInPending = prefsSnap.data?['showInPending'] as bool? ?? true;
        final monthsAhead = (prefsSnap.data?['pendingMonthsAhead'] as int?)?.clamp(1, 12) ?? AppBusinessRules.pendingMonthsAheadDefault;
        final limitDate = DateTime(DateTime.now().year, DateTime.now().month + monthsAhead, 1);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _pendingIncomesStream,
          initialData: _lastPendingIncomesSnap,
          builder: (context, snap) {
            if (snap.hasError) {
              return _buildPendingStreamErrorBar(
                'Receitas pendentes',
                snap.error,
                AppColors.financeReceita,
              );
            }
            double total = 0;
            final list = <Map<String, dynamic>>[];
            for (final doc in snap.data?.docs ?? []) {
              final d = Map<String, dynamic>.from(doc.data());
              d['id'] = doc.id;
              if (FinanceAccountBalanceUtils.isOnCreditCardAccount(d, _creditCardAccountIds)) continue;
              if (!showInPending && (d['fixedIncomeId'] ?? '').toString().isNotEmpty) continue;
              final dateTs = d['date'];
              if (dateTs is Timestamp) {
                final dt = dateTs.toDate();
                if (dt.isAfter(limitDate)) continue;
              }
              total += (d['amount'] ?? 0).toDouble().abs();
              list.add(d);
            }
            list.sort((a, b) {
              final ta = (a['date'] as Timestamp?)?.toDate();
              final tb = (b['date'] as Timestamp?)?.toDate();
              if (ta == null || tb == null) return 0;
              return ta.compareTo(tb);
            });
            const blueLight = Color(0xFF0EA5E9);
            const blueLightDark = Color(0xFF0284C7);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _abrirListaReceitasPendentes(context, list),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        blueLight,
                        blueLight.withValues(alpha: 0.9),
                        blueLightDark,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: blueLight.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Receitas pendentes',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white.withValues(alpha: 0.98),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${list.length} lançamento(s) em aberto · Toque para ver',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          CurrencyFormats.formatBRL(total),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Quadro laranja: despesas pendentes. Respeita preferências (mostrar fixas, próximos X meses).
  Widget _buildDespesasPendentesBand(BuildContext context) {
    if (!widget.isShellVisible) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<Map<String, dynamic>>(
      stream: _fixedExpensePrefsStream,
      initialData: _lastFixedExpensePrefs,
      builder: (context, prefsSnap) {
        final showInPending = prefsSnap.data?['showInPending'] as bool? ?? true;
        final monthsAhead = (prefsSnap.data?['pendingMonthsAhead'] as int?)?.clamp(1, 12) ?? AppBusinessRules.pendingMonthsAheadDefault;
        final limitDate = DateTime(DateTime.now().year, DateTime.now().month + monthsAhead, 1);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _pendingExpensesStream,
        initialData: _lastPendingExpensesSnap,
          builder: (context, snap) {
            if (snap.hasError) {
              return _buildPendingStreamErrorBar(
                'Despesas pendentes',
                snap.error,
                AppColors.financeDespesa,
              );
            }
            double total = 0;
            final list = <Map<String, dynamic>>[];
            for (final doc in snap.data?.docs ?? []) {
              final d = Map<String, dynamic>.from(doc.data());
              d['id'] = doc.id;
              if (FinanceAccountBalanceUtils.isOnCreditCardAccount(d, _creditCardAccountIds)) continue;
              if (!showInPending && (d['fixedExpenseId'] ?? '').toString().isNotEmpty) continue;
              final dateTs = d['date'];
              if (dateTs is Timestamp) {
                final dt = dateTs.toDate();
                if (dt.isAfter(limitDate)) continue;
              }
              total += (d['amount'] ?? 0).toDouble().abs();
              list.add(d);
            }
            list.sort((a, b) {
              final ta = (a['date'] as Timestamp?)?.toDate();
              final tb = (b['date'] as Timestamp?)?.toDate();
              if (ta == null || tb == null) return 0;
              return ta.compareTo(tb);
            });
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _abrirListaDespesasPendentes(context, list),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.logoOrange,
                        AppColors.logoOrange.withValues(alpha: 0.85),
                        const Color(0xFFEA580C),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.logoOrange.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Despesas pendentes',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white.withValues(alpha: 0.98),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${list.length} lançamento(s) em aberto · Toque para ver',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          CurrencyFormats.formatBRL(total),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Card "Dica do dia" (rotacionada pelo dia do ano) para educação financeira.
  Widget _buildDicaDoDiaCard() {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    final dica = kFinanceTips[dayOfYear % kFinanceTips.length];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Dica do dia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 4),
                Text(dica, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _abrirListaReceitasPendentes(BuildContext context, List<Map<String, dynamic>> list) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => _PendingListSheetContent(
          title: 'Receitas pendentes',
          iconColor: AppColors.financeReceita,
          list: list,
          scrollController: scrollController,
          emptyMessage: 'Nenhuma receita pendente',
          buildItem: (c, e, {selectionMode = false, isSelected = false, onToggleSelect}) =>
              _buildReceitaPendenteListItem(c, e, selectionMode: selectionMode, isSelected: isSelected, onToggleSelect: onToggleSelect),
          batchConfirmShortLabel: 'Confirmar recebimento',
          onConfirmBatch: (sheetCtx, ids) async {
            await _confirmarPagamentoEmLote(
              sheetCtx,
              ids,
              isIncome: true,
              successSnackBar: ids.length > 1 ? '${ids.length} recebimentos confirmados.' : 'Recebimento confirmado.',
            );
            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          },
          onDeleteBatch: (ids) async {
            await _deleteTxBatch(context, ids);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  Widget _buildReceitaPendenteListItem(
    BuildContext context,
    Map<String, dynamic> e, {
    bool selectionMode = false,
    bool isSelected = false,
    VoidCallback? onToggleSelect,
  }) {
    final amount = (e['amount'] ?? 0).toDouble().abs();
    final cat = (e['category'] ?? '').toString().trim();
    final desc = (e['description'] ?? '').toString().trim();
    final date = (e['date'] as Timestamp?)?.toDate();
    final dateStr = date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '—';
    final docId = (e['id'] ?? '').toString();
    final receipt = Map<String, dynamic>.from(e['receipt'] ?? {});
    final hasReceiptView = ReceiptAttachmentUtils.hasViewableReceipt(receipt);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (selectionMode) ...[
              Checkbox(value: isSelected, onChanged: (_) => onToggleSelect?.call(), materialTapTargetSize: MaterialTapTargetSize.padded),
              const SizedBox(width: 8),
            ],
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.financeReceita.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_downward_rounded, color: AppColors.financeReceita, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat.isNotEmpty ? cat : 'Receita',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (desc.isNotEmpty)
                    Text(desc, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(dateStr, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                ],
              ),
            ),
            if (!selectionMode) ...[
              Text(
                CurrencyFormats.formatBRL(amount),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.financeReceita),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                padding: EdgeInsets.zero,
                tooltip: 'Ações do lançamento',
                onSelected: (v) {
                  if (v == 'edit') _editTx(context, docId, e, 'income');
                  else if (v == 'view' && hasReceiptView) mostrarComprovanteReceipt(context, receipt);
                  else if (v == 'attach') _attachReceipt(context, docId);
                  else if (v == 'delete') _deleteTx(context, docId);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 8), Text('Editar')])),
                  if (hasReceiptView) const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility_rounded, size: 20), SizedBox(width: 8), Text('Ver anexo')])),
                  const PopupMenuItem(value: 'attach', child: Row(children: [Icon(Icons.attach_file_rounded, size: 20), SizedBox(width: 8), Text('Anexar comprovante')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 20), SizedBox(width: 8), Text('Excluir')])),
                ],
              ),
            ] else
              Flexible(
                child: Text(
                  CurrencyFormats.formatBRL(amount),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.financeReceita),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        if (!selectionMode) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  onPressed: () => _confirmarPagamento(context, docId),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Confirmar recebimento', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded, backgroundColor: AppColors.success.withValues(alpha: 0.15), foregroundColor: AppColors.success),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteTx(context, docId),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Excluir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)), minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    final container = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: AppColors.financeReceita.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.financePendente.withValues(alpha: 0.28)),
      ),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: content),
    );
    if (selectionMode && onToggleSelect != null) {
      return InkWell(onTap: onToggleSelect, borderRadius: BorderRadius.circular(16), child: container);
    }
    return container;
  }

  void _abrirListaDespesasPendentes(BuildContext context, List<Map<String, dynamic>> list) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => _PendingListSheetContent(
          title: 'Despesas pendentes',
          iconColor: AppColors.financeDespesa,
          list: list,
          scrollController: scrollController,
          emptyMessage: 'Nenhuma despesa pendente',
          buildItem: (c, e, {selectionMode = false, isSelected = false, onToggleSelect}) =>
              _buildDespesaPendenteListItem(c, e, selectionMode: selectionMode, isSelected: isSelected, onToggleSelect: onToggleSelect),
          batchConfirmShortLabel: 'Confirmar pagamento',
          onConfirmBatch: (sheetCtx, ids) async {
            await _confirmarPagamentoEmLote(
              sheetCtx,
              ids,
              isIncome: false,
              successSnackBar: ids.length > 1 ? '${ids.length} pagamentos confirmados.' : 'Pagamento confirmado.',
            );
            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          },
          onDeleteBatch: (ids) async {
            await _deleteTxBatch(context, ids);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  Widget _buildDespesaPendenteListItem(
    BuildContext context,
    Map<String, dynamic> e, {
    bool selectionMode = false,
    bool isSelected = false,
    VoidCallback? onToggleSelect,
  }) {
    final amount = (e['amount'] ?? 0).toDouble().abs();
    final cat = (e['category'] ?? '').toString().trim();
    final desc = (e['description'] ?? '').toString().trim();
    final date = (e['date'] as Timestamp?)?.toDate();
    final dateStr = date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '—';
    final docId = (e['id'] ?? '').toString();
    final receipt = Map<String, dynamic>.from(e['receipt'] ?? {});
    final hasReceiptView = ReceiptAttachmentUtils.hasViewableReceipt(receipt);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (selectionMode) ...[
              Checkbox(value: isSelected, onChanged: (_) => onToggleSelect?.call(), materialTapTargetSize: MaterialTapTargetSize.padded),
              const SizedBox(width: 8),
            ],
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.financeDespesa.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_upward_rounded, color: AppColors.financeDespesa, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat.isNotEmpty ? cat : 'Despesa',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (desc.isNotEmpty)
                    Text(desc, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(dateStr, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                ],
              ),
            ),
            if (!selectionMode) ...[
              Text(
                CurrencyFormats.formatBRL(amount),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.financeDespesa),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                padding: EdgeInsets.zero,
                tooltip: 'Ações do lançamento',
                onSelected: (v) {
                  if (v == 'edit') _editTx(context, docId, e, 'expense');
                  else if (v == 'view' && hasReceiptView) mostrarComprovanteReceipt(context, receipt);
                  else if (v == 'attach') _attachReceipt(context, docId);
                  else if (v == 'delete') _deleteTx(context, docId);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 8), Text('Editar')])),
                  if (hasReceiptView) const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility_rounded, size: 20), SizedBox(width: 8), Text('Ver anexo')])),
                  const PopupMenuItem(value: 'attach', child: Row(children: [Icon(Icons.attach_file_rounded, size: 20), SizedBox(width: 8), Text('Anexar comprovante')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 20), SizedBox(width: 8), Text('Excluir')])),
                ],
              ),
            ] else
              Flexible(
                child: Text(
                  CurrencyFormats.formatBRL(amount),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.financeDespesa),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        if (!selectionMode) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  onPressed: () => _confirmarPagamento(context, docId),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Confirmar pagamento', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded, backgroundColor: AppColors.success.withValues(alpha: 0.15), foregroundColor: AppColors.success),
                ),
                OutlinedButton.icon(
                  onPressed: () => _deleteTx(context, docId),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Excluir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)), minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    final container = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: AppColors.financeDespesa.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.financePendente.withValues(alpha: 0.28)),
      ),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: content),
    );
    if (selectionMode && onToggleSelect != null) {
      return InkWell(onTap: onToggleSelect, borderRadius: BorderRadius.circular(16), child: container);
    }
    return container;
  }

  Future<void> _attachReceipt(BuildContext context, String txId) async {
    final picked = await ReceiptAttachmentUtils.pickValidated(context);
    if (picked == null) return;

    try {
      await TransactionSaveService.attachReceiptToTransaction(
        uid: widget.uid,
        docId: txId,
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
      );
      if (mounted) {
        setState(() {
          final prev = _optimisticEditedTxById[txId];
          _optimisticEditedTxById[txId] = {
            if (prev != null) ...prev,
            'hasReceipt': true,
          };
        });
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comprovante enviado e vinculado.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }



  DateTime? _transactionCalendarDay(Map<String, dynamic> d) {
    final instant = FinanceFaturaTransactionSort.effectiveInstant(d);
    if (instant == null) return null;
    return DateTime(instant.year, instant.month, instant.day);
  }

  /// Rótulo da conta vinculada, ou null se não houver vínculo.
  String? _financeAccountLabelForTx(Map<String, dynamic> d) {
    final aid = (d['financeAccountId'] ?? '').toString().trim();
    if (aid.isEmpty) return null;
    for (final a in _financeAccounts) {
      if (a.id == aid) return a.displayName;
    }
    return 'Conta removida';
  }

  /// Rótulo para o sheet de insights quando há filtro de conta na tela principal.
  String? _financeAccountFilterLabelForInsight() {
    if (_financeAccountFilterId == null) return null;
    for (final a in _financeAccounts) {
      if (a.id == _financeAccountFilterId) return a.displayName;
    }
    return 'Conta';
  }

  Widget _financeDayHeader(DateTime? day) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.12),
                AppColors.accent.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  day == null ? 'Sem data' : DateTimeFormats.dateBR.format(day),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumReceitaButton(BuildContext context, {required bool dense}) {
    final padV = dense ? 10.0 : 14.0;
    final iconSize = dense ? 20.0 : 22.0;
    final fontSize = dense ? 12.5 : 14.0;
    final radius = BorderRadius.circular(16);
    final onTap = widget.profile.hasActiveLicense
        ? () => _addTx(context, 'income')
        : () => mostrarAvisoSeLicencaInativa(context, widget.profile);
    return Semantics(
      label: 'Registrar nova receita',
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4ADE80), AppColors.success, Color(0xFF166534)],
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFF166534).withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
                BoxShadow(color: const Color(0xFF4ADE80).withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: padV, horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_card_rounded, color: Colors.white, size: iconSize),
                  SizedBox(width: dense ? 4 : 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Receita',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: fontSize,
                          letterSpacing: 0.2,
                        ),
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

  Widget _buildPremiumDespesaButton(BuildContext context, {required bool dense}) {
    final padV = dense ? 10.0 : 14.0;
    final iconSize = dense ? 20.0 : 22.0;
    final fontSize = dense ? 12.5 : 14.0;
    final radius = BorderRadius.circular(16);
    final onTap = widget.profile.hasActiveLicense
        ? () => _addTx(context, 'expense')
        : () => mostrarAvisoSeLicencaInativa(context, widget.profile);
    return Semantics(
      label: 'Registrar nova despesa',
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF87171), AppColors.error, Color(0xFF991B1B)],
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFF991B1B).withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
                BoxShadow(color: const Color(0xFFF87171).withValues(alpha: 0.28), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: padV, horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_rounded, color: Colors.white, size: iconSize),
                  SizedBox(width: dense ? 4 : 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Despesa',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: fontSize,
                          letterSpacing: 0.2,
                        ),
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

  /// Despesas fixas — gradiente logo + sombra (padrão super premium).
  Widget _buildDespesasFixasButtonCompact(BuildContext context, {bool dense = false}) {
    final onTap = widget.profile.hasActiveLicense
        ? () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DespesasFixasScreen(uid: firestoreUserDocIdForAppShell(widget.uid))),
            ).then((_) {
              if (!mounted) return;
              setState(() {}); // Atualiza lista ao voltar da tela Despesas fixas
            })
        : () => mostrarAvisoSeLicencaInativa(context, widget.profile);
    final padV = dense ? 10.0 : 14.0;
    final iconSize = dense ? 20.0 : 22.0;
    final fontSize = dense ? 12.5 : 14.0;
    final radius = BorderRadius.circular(16);
    return Semantics(
      label: 'Abrir despesas fixas',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 7)),
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.22), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Material(
          borderRadius: radius,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.deepBlueDark, AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: radius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: padV, horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_repeat_rounded, color: Colors.white, size: iconSize),
                    SizedBox(width: dense ? 4 : 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Despesas fixas',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: fontSize,
                            letterSpacing: 0.2,
                          ),
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

  /// Receitas fixas — mesmo padrão visual compacto, cores de receita.
  Widget _buildReceitasFixasButtonCompact(BuildContext context, {bool dense = false}) {
    final onTap = widget.profile.hasActiveLicense
        ? () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ReceitasFixasScreen(uid: firestoreUserDocIdForAppShell(widget.uid))),
            ).then((_) {
              if (!mounted) return;
              setState(() {});
            })
        : () => mostrarAvisoSeLicencaInativa(context, widget.profile);
    final padV = dense ? 10.0 : 14.0;
    final iconSize = dense ? 20.0 : 22.0;
    final fontSize = dense ? 12.5 : 14.0;
    final radius = BorderRadius.circular(16);
    return Semantics(
      label: 'Abrir receitas fixas',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: const Color(0xFF14532D).withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 7)),
            BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.22), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Material(
          borderRadius: radius,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF22C55E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: radius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: padV, horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.savings_outlined, color: Colors.white, size: iconSize),
                    SizedBox(width: dense ? 4 : 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Receitas fixas',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: fontSize,
                            letterSpacing: 0.2,
                          ),
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

  Widget _buildTransferenciaButton(BuildContext context, {bool dense = false}) {
    final onTap = widget.profile.hasActiveLicense
        ? () => _openTransferBetweenAccounts(context)
        : () => mostrarAvisoSeLicencaInativa(context, widget.profile);
    final radius = BorderRadius.circular(16);
    final padV = dense ? 10.0 : 12.0;
    final fontSize = dense ? 12.5 : 13.5;
    return Semantics(
      label: 'Transferência entre contas',
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF1E40AF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFF1E40AF).withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: padV, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz_rounded, color: Colors.white, size: dense ? 19 : 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Transferência',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fontSize),
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

  /// Chip de status (Todos / Pago / Pendente) — alinhado ao módulo Agenda (super premium).
  Widget _financeFilterChip({
    required String label,
    required IconData icon,
    required Color accent,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: selected ? accent.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: selected ? accent : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: selected ? accent : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Período (Mensal, Anual, Por período) — pill com gradiente quando selecionado.
  Widget _financePeriodChip({
    required String period,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: selected
                ? const LinearGradient(
                    colors: [AppColors.deepBlueDark, AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : Colors.white,
            border: Border.all(
              color: selected ? Colors.transparent : const Color(0xFFE2E8F0),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.deepBlueDark.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            period,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// Insights leves: top despesas, despesas fixas vs receita, comparativo com período anterior (mesma duração).
  Widget _buildFinanceInsightsBlock(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required double totalIncome,
    required double totalExpense,
    required double balancePeriod,
  }) {
    final (pf, pt) = _previousPeriodSameLength();
    final compareKey = '${pf.toIso8601String()}|${pt.toIso8601String()}|$_statusFilter|$_typeFilter';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (totalExpense > 0.0001) ...[
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 18, color: AppColors.financeDespesa),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Onde foi o dinheiro (despesas)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              TextButton(
                onPressed: widget.profile.hasActiveLicense ? _openFinanceCategoriesFullscreen : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(48, 40),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: const Text('Veja mais'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: financePeriodMergedDocumentsCollect(
              uid: firestoreUserDocIdForAppShell(widget.uid),
              from: _from,
              to: _to,
              statusFilter: _statusFilter,
              typeFilter: 'expense',
              financeAccountId: _financeAccountFilterId,
            ),
            builder: (context, mergedSnap) {
              final mergedDocs = mergedSnap.data ?? docs;
              final topMerged = _topExpenseCategories(mergedDocs, n: 5);
              if (topMerged.isEmpty) return const SizedBox.shrink();
              return Column(
                children: topMerged.map((e) {
                  final pct = totalExpense > 0.0001 ? ((e.value / totalExpense) * 100).clamp(0.0, 100.0) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _WhereMoneyExpenseCard(
                      categoryName: e.key,
                      amount: e.value,
                      percentOfPeriodExpenses: pct,
                      accent: _WhereMoneyExpenseCard.accentFor(e.key),
                      icon: _WhereMoneyExpenseCard.iconFor(e.key),
                      onTap: () => _openFinanceInsightSheet(
                        scope: FinanceInsightScope.expense,
                        initialFrom: _from,
                        initialTo: _to,
                        initialCategoryExact: e.key,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 18),
        ],
        FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: Future.wait([
            FixedExpenseService().list(firestoreUserDocIdForAppShell(widget.uid)),
            FixedIncomeService().list(firestoreUserDocIdForAppShell(widget.uid)),
          ]),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final expList = snap.data![0];
            final incList = snap.data![1];
            var monthlyExp = 0.0;
            for (final e in expList) {
              if (e['active'] == false) continue;
              monthlyExp += ((e['amount'] ?? 0) as num).toDouble().abs();
            }
            var monthlyInc = 0.0;
            for (final e in incList) {
              if (e['active'] == false) continue;
              monthlyInc += ((e['amount'] ?? 0) as num).toDouble().abs();
            }
            if (monthlyExp <= 0 && monthlyInc <= 0) return const SizedBox.shrink();
            final pctExp = totalIncome > 0.0001 ? (monthlyExp / totalIncome) * 100.0 : null;
            final pctInc = totalIncome > 0.0001 ? (monthlyInc / totalIncome) * 100.0 : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (monthlyExp > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.financePendente.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.financePendente.withValues(alpha: 0.28)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.home_work_outlined, color: AppColors.financePendente, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              pctExp != null
                                  ? 'Despesas fixas (cadastro): ${CurrencyFormats.formatBRL(monthlyExp)}/mês · ${pctExp.toStringAsFixed(0)}% das receitas deste período na tela.'
                                  : 'Despesas fixas (cadastro): ${CurrencyFormats.formatBRL(monthlyExp)}/mês. Adicione receitas no período para ver o percentual.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (monthlyInc > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.financeReceita.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.financeReceita.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.savings_outlined, color: AppColors.financeReceita, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              pctInc != null
                                  ? 'Receitas fixas (cadastro): ${CurrencyFormats.formatBRL(monthlyInc)}/mês · ${pctInc.toStringAsFixed(0)}% das receitas deste período na tela.'
                                  : 'Receitas fixas (cadastro): ${CurrencyFormats.formatBRL(monthlyInc)}/mês.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        FutureBuilder(
          key: ValueKey(compareKey),
          future: FinancePeriodSummary.load(
            uid: firestoreUserDocIdForAppShell(widget.uid),
            from: pf,
            to: pt,
            statusFilter: _statusFilter,
            typeFilter: _typeFilter,
          ),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done || !snap.hasData) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  color: AppColors.primary,
                  backgroundColor: AppColors.textMuted.withValues(alpha: 0.12),
                ),
              );
            }
            final r = snap.data!;
            final prevBal = r.income - r.expense;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _PremiumSaldoPeriodoCard(
                prevFrom: pf,
                prevTo: pt,
                prevIncome: r.income,
                prevExpense: r.expense,
                prevBalance: prevBal,
                curIncome: totalIncome,
                curExpense: totalExpense,
                curBalance: balancePeriod,
              ),
            );
          },
        ),
        FinanceSmartTipsInsightBlock(
          uid: firestoreUserDocIdForAppShell(widget.uid),
          docs: docs,
          totalIncome: totalIncome,
          totalExpense: totalExpense,
          balancePeriod: balancePeriod,
          onOpenAssistantPanel: widget.profile.hasActiveLicense
              ? () => _openFinanceAssistantInsightsPage(
                    docs: docs,
                    totalIncome: totalIncome,
                    totalExpense: totalExpense,
                    balancePeriod: balancePeriod,
                  )
              : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
        ),
      ],
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocsForGridListType(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_gridListTypeFilter == 'all') return docs;
    return docs.where((doc) {
      final type = (_txDataForMainPeriodDoc(doc)['type'] ?? 'expense').toString();
      return type == _gridListTypeFilter;
    }).toList();
  }

  Future<void> _openSmartTipsPreviewSheet({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required double totalIncome,
    required double totalExpense,
    required double balancePeriod,
  }) {
    return showFinanceSmartTipsPreviewSheet(
      context: context,
      uid: firestoreUserDocIdForAppShell(widget.uid),
      docs: docs,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      balancePeriod: balancePeriod,
      onOpenAssistantPanel: widget.profile.hasActiveLicense
          ? () {
              Navigator.pop(context);
              unawaited(_openFinanceAssistantInsightsPage(
                docs: docs,
                totalIncome: totalIncome,
                totalExpense: totalExpense,
                balancePeriod: balancePeriod,
              ));
            }
          : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
    );
  }

  Widget _buildFinanceMainKpiSection({
    required double saldoAbertura,
    required double totalIncome,
    required double totalExpense,
    required double saldoAcumulado,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Resumo do período',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Exportar PDF (padrão premium)',
                onPressed: widget.profile.hasActiveLicense
                    ? () => unawaited(_openFinancialReportsPremiumSheet())
                    : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                style: IconButton.styleFrom(
                  foregroundColor: _kPdfActionOrange,
                  backgroundColor: _kPdfActionOrange.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
                _FinanceKpiCard(
                  title: 'Saldo de abertura',
                  value: CurrencyFormats.formatBRL(saldoAbertura),
                  color: saldoAbertura >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                  icon: Icons.account_balance_rounded,
                ),
                _FinanceKpiCard(
                  title: 'Receitas',
                  value: CurrencyFormats.formatBRL(totalIncome),
                  color: AppColors.financeReceita,
                  icon: Icons.arrow_downward,
                  onTap: () => _openFinanceInsightSheet(
                    scope: FinanceInsightScope.income,
                    initialFrom: _from,
                    initialTo: _to,
                  ),
                ),
                _FinanceKpiCard(
                  title: 'Despesas',
                  value: CurrencyFormats.formatBRL(totalExpense),
                  color: AppColors.financeDespesa,
                  icon: Icons.arrow_upward,
                  onTap: () => _openFinanceInsightSheet(
                    scope: FinanceInsightScope.expense,
                    initialFrom: _from,
                    initialTo: _to,
                  ),
                ),
                _FinanceKpiCard(
                  title: 'Saldo (acum.)',
                  value: CurrencyFormats.formatBRL(saldoAcumulado),
                  color: saldoAcumulado >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                  icon: Icons.account_balance_wallet,
                  onTap: () => _openFinanceInsightSheet(
                    scope: FinanceInsightScope.balance,
                    initialFrom: _from,
                    initialTo: _to,
                  ),
                ),
              ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridListTypeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _buildGridTypeButton('all', 'Todos', Icons.layers_rounded, AppColors.deepBlue),
          const SizedBox(width: 8),
          _buildGridTypeButton('expense', 'Despesas', Icons.north_east_rounded, AppColors.financeDespesa),
          const SizedBox(width: 8),
          _buildGridTypeButton('income', 'Receitas', Icons.south_west_rounded, AppColors.financeReceita),
        ],
      ),
    );
  }

  Widget _buildGridTypeButton(String value, String label, IconData icon, Color accent) {
    final selected = _gridListTypeFilter == value;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() {
            _gridListTypeFilter = value;
            _txDisplayLimit = _txPageSize;
            _gridSelectionMode = false;
            _gridSelectedIds.clear();
          }),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, Color.lerp(accent, Colors.white, 0.22)!],
                    )
                  : null,
              color: selected ? null : const Color(0xFFF8FAFC),
              border: Border.all(
                color: selected ? accent.withValues(alpha: 0.55) : const Color(0xFFE2E8F0),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: selected ? Colors.white : AppColors.textMuted),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isShellVisible) {
      return const ColoredBox(color: Color(0xFFF5F7FA));
    }
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    // Sem pesquisa/categoria/conta: lista pode usar [where] + paginação no Firestore (menos dados).
    // Com filtro «Pago» ou texto de pesquisa: período completo em lotes e filtros em memória.
    // Na web, não subscrever até `currentUser` existir — com `request.auth` ausente, as regras negam leitura.
    final String? sessionUid = _effectiveFinanceSessionUid;

    final mq = MediaQuery.of(context);
    final clampedScaler = mq.textScaler.clamp(minScaleFactor: 0.88, maxScaleFactor: 1.34);

    return PopScope(
      canPop: _financeAccountFilterId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _financeAccountFilterId == null) return;
        _applyFinanceAccountFilter(null);
      },
      child: MediaQuery(
      data: mq.copyWith(textScaler: clampedScaler),
      child: RepaintBoundary(
        child: Column(
          children: [
          AnimatedCrossFade(
            firstChild: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, isNarrow ? 4 : 2, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
            children: [
              // Receita | Despesa | Despesas fixas — gradientes e sombras (super premium)
              Row(children: [
                Expanded(child: _buildPremiumReceitaButton(context, dense: false)),
                const SizedBox(width: 8),
                Expanded(child: _buildPremiumDespesaButton(context, dense: false)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _buildDespesasFixasButtonCompact(context, dense: false)),
                const SizedBox(width: 8),
                Expanded(child: _buildReceitasFixasButtonCompact(context, dense: false)),
              ]),
              const SizedBox(height: 8),
              _buildTransferenciaButton(context, dense: false),
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.profile.hasActiveLicense
                      ? () => unawaited(_abrirLancamentoInteligente())
                      : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.primary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.content_paste_go_rounded, size: 22, color: Colors.white),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Lançamento inteligente (texto / SMS)',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                height: 1.2,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Filtros: só período/status/pesquisa; barra compacta do topo usa ícone à direita
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _filtrosPainelAberto = !_filtrosPainelAberto),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepBlueDark.withValues(alpha: 0.07),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withValues(alpha: 0.15),
                                      AppColors.accent.withValues(alpha: 0.12),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _filtrosPainelAberto ? Icons.tune_rounded : Icons.filter_alt_rounded,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _filtrosPainelAberto ? 'Recolher filtros' : 'Filtros e pesquisa',
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontSize: 14, letterSpacing: 0.1),
                                ),
                              ),
                              Icon(
                                _filtrosPainelAberto ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                color: AppColors.primary.withValues(alpha: 0.85),
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Modo compacto (mais espaço para a lista)',
                    child: IconButton.filledTonal(
                      onPressed: () => setState(() {
                        _topoExpandido = false;
                        _filtrosPainelAberto = false;
                      }),
                      icon: const Icon(Icons.unfold_less_rounded, size: 22),
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ],
              ),
              if (_filtrosPainelAberto) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.deepBlueDark.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.date_range_rounded, size: 18, color: AppColors.accent.withValues(alpha: 0.95)),
                        const SizedBox(width: 8),
                        Text(
                          'Período',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _periods.map((p) {
                        return _financePeriodChip(
                          period: p,
                          selected: _selectedPeriod == p,
                          onSelect: () {
                            setState(() {
                              _selectedPeriod = p;
                              if (p == 'Por período' && _customRangeStart == null) {
                                _customRangeStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
                                _customRangeEnd = DateTime.now();
                              }
                              _applyPeriod();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (_selectedPeriod == 'Por período') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                final picked = await showDatePicker(context: context, initialDate: _customRangeStart ?? _from, firstDate: DateTime(2000), lastDate: DateTime(2030));
                                if (picked != null && mounted) setState(() { _customRangeStart = picked; _applyPeriod(); });
                              },
                              icon: const Icon(Icons.calendar_today_rounded, size: 18),
                              label: Text('De ${DateFormat('dd/MM/yy').format(_customRangeStart ?? _from)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                final picked = await showDatePicker(context: context, initialDate: _customRangeEnd ?? _to, firstDate: _customRangeStart ?? DateTime(2000), lastDate: DateTime(2030));
                                if (picked != null && mounted) setState(() { _customRangeEnd = picked; _applyPeriod(); });
                              },
                              icon: const Icon(Icons.event_rounded, size: 18),
                              label: Text('Até ${DateFormat('dd/MM/yy').format(_customRangeEnd ?? _to)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              RepaintBoundary(
                child: LightFilterPicker<String>(
                  value: _statusFilter,
                  decoration: _financeFilterDropdownDecoration(
                      'Status do lançamento', Icons.filter_list_rounded),
                  label: 'Status do lançamento',
                  options: const [
                    LightFilterOption(
                        value: 'all', label: 'Todos os status'),
                    LightFilterOption(value: 'paid', label: 'Pago'),
                    LightFilterOption(value: 'pending', label: 'Pendente'),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _statusFilter = v;
                      _resetTxPagination();
                    });
                    _requestMainPeriodReload();
                  },
                ),
              ),
              const SizedBox(height: 12),
              RepaintBoundary(
                child: Builder(
                  builder: (context) {
                    final accountFilterValid = _financeAccountFilterId == null ||
                        _financeAccounts.any((a) => a.id == _financeAccountFilterId);
                    final accountValue =
                        accountFilterValid ? _financeAccountFilterId : null;
                    final loadingAccounts =
                        !_financeAccountsStreamPrimed && _financeAccounts.isEmpty;
                    return LightFilterPicker<String?>(
                      key: ValueKey<String?>(
                          'acct-$accountValue-${_financeAccounts.length}'),
                      value: accountValue,
                      enabled: !loadingAccounts,
                      label: 'Conta (banco ou cartão)',
                      decoration: _financeFilterDropdownDecoration(
                          'Conta (banco ou cartão)',
                          Icons.account_balance_rounded),
                      options: [
                        const LightFilterOption<String?>(
                          value: null,
                          label: 'Todas as contas',
                        ),
                        if (loadingAccounts)
                          const LightFilterOption<String?>(
                            enabled: false,
                            value: '__loading__',
                            label: 'A carregar contas…',
                          )
                        else
                          ..._financeAccounts.map(
                            (a) => LightFilterOption<String?>(
                              value: a.id,
                              label: a.displayName,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == '__loading__') return;
                        _applyFinanceAccountFilter(v);
                      },
                    );
                  },
                ),
              ),
              if (_financeAccountsStreamPrimed && _financeAccounts.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Sem contas cadastradas. Use Bancos e cartões para criar contas e filtrar por banco aqui.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
                ),
              ],
              const SizedBox(height: 12),
              RepaintBoundary(
                child: LightFilterPicker<String>(
                  value: _typeFilter,
                  label: 'Tipo de lançamento',
                  decoration: _financeFilterDropdownDecoration(
                      'Tipo de lançamento', Icons.swap_vert_rounded),
                  options: const [
                    LightFilterOption(
                        value: 'all', label: 'Receitas e despesas'),
                    LightFilterOption(value: 'income', label: 'Só receitas'),
                    LightFilterOption(value: 'expense', label: 'Só despesas'),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _typeFilter = v;
                      _resetTxPagination();
                    });
                    _requestMainPeriodReload();
                  },
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<String>>(
                future: _categoryFilterOptionsFuture,
                builder: (context, catSnap) {
                  final loading = catSnap.connectionState == ConnectionState.waiting && !catSnap.hasData;
                  String? displayCategory = _categoryFilter;
                  if (_categoryFilter != null && catSnap.hasData) {
                    for (final o in catSnap.data!) {
                      if (FinanceCategoryMerger.sameCategoryGroup(o, _categoryFilter!)) {
                        displayCategory = o;
                        break;
                      }
                    }
                  }
                  return FinanceCategoryFilterTile(
                    selectedCategory: displayCategory,
                    loading: loading,
                    onTap: _openCategoryFilterPicker,
                    onClear: _categoryFilter == null
                        ? null
                        : () => setState(() {
                              _categoryFilter = null;
                              _resetTxPagination();
                            }),
                  );
                },
              ),
              ],
            ],
          ),
        ),
              ],
            ),
          ),
          ),
            ),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildPremiumReceitaButton(context, dense: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildPremiumDespesaButton(context, dense: true)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildDespesasFixasButtonCompact(context, dense: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildReceitasFixasButtonCompact(context, dense: true)),
                    const SizedBox(width: 6),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() {
                          _topoExpandido = true;
                          _filtrosPainelAberto = true;
                        }),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepBlueDark.withValues(alpha: 0.08),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withValues(alpha: 0.85),
                                      AppColors.accent.withValues(alpha: 0.9),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Filtros',
                                style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 12, letterSpacing: 0.2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildTransferenciaButton(context, dense: true),
                const SizedBox(height: 8),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.profile.hasActiveLicense
                        ? () => unawaited(_abrirLancamentoInteligente())
                        : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.primary],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.32),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sms_outlined, size: 22, color: Colors.white),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Lançamento por mensagem (SMS / banco)',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  height: 1.2,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _topoExpandido ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 250),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final periodKey = '${_from.year}-${_from.month}-${_from.day}';
              if (_saldoAberturaKey != periodKey) {
                _ensureSaldoAberturaForPeriod(_from);
              }
              if (sessionUid == null) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 34, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        const Text(
                          'A preparar a sessão offline…',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => unawaited(_onRetryLoadTransactions()),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return KeyedSubtree(
                key: ValueKey(
                  'txlist_${_txStreamRetryKey}_${_from.millisecondsSinceEpoch}_${_to.millisecondsSinceEpoch}_$_statusFilter|$_typeFilter|${_categoryFilter ?? ''}|${_financeAccountFilterId ?? ''}',
                ),
                child: Builder(
                  builder: (context) {
              if (_mainPeriodLoadError != null) {
                _ensureSaldoAberturaForPeriod(_from);
                final openingByAccount =
                    _saldoAberturaCached?.byAccount ?? const <String, double>{};
                final saldoAbertura = _saldoAberturaCached?.total ?? 0.0;
                final saldoAcumulado = _saldoAcumuladoConsolidado(
                  saldoAbertura: saldoAbertura,
                  balancePeriodFallback: 0,
                  periodNetByAccount: _stripPeriodNetPaidOverride,
                  accountFilterId: _financeAccountFilterId,
                  openingByAccount: openingByAccount,
                );
                return ListView(
                  controller: widget.shellScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(
                    bottom: homeShellScrollBottomPadding(
                      context,
                      embeddedInHomeShell: widget.shellScrollController != null,
                      tail: 12,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: _buildFinanceAccountsStrip(
                        context,
                        docs: const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                        openingByAccount: openingByAccount,
                        saldoAcumuladoConsolidado: saldoAcumulado,
                        semContaCount: 0,
                        stripPeriodNetPaidOverride: _stripPeriodNetPaidOverride,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: Colors.orange.shade700),
                        const SizedBox(height: 16),
                        const Text(
                          'Erro ao carregar lançamentos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Os seus dados não foram apagados. Isto costuma ser rede, sessão ou índice Firestore em construção. '
                          'Use "Filtro Todos" (estado) e o botão de tentar de novo. Bancos, cartões e categorias continuam disponíveis acima.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          constraints: const BoxConstraints(maxWidth: 480),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              title: const Text(
                                'Mostrar detalhe técnico (para o suporte)',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                              children: [
                                SelectableText(
                                  _mainPeriodLoadError.toString(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: () => setState(() {
                                _statusFilter = 'all';
                                _resetTxPagination();
                                _txStreamRetryKey++;
                              }),
                              icon: const Icon(Icons.filter_list_rounded),
                              label: const Text('Filtro Todos'),
                            ),
                            FilledButton.icon(
                              onPressed: _onRetryLoadTransactions,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar novamente'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _onClearCacheAndRetry,
                              icon: const Icon(Icons.cleaning_services_rounded),
                              label: const Text('Limpar cache e tentar'),
                            ),
                          ],
                        ),
                      ],
                      ),
                    ),
                  ],
                );
              }
              var docs = _dedupeMainPeriodDocs(_mainPeriodDocs).where((doc) {
                final d = _txDataForMainPeriodDoc(doc);
                if (!_mainPeriodServerPagingActive) {
                  // Filtro por status em memória (evita índice composto no Firestore)
                  if (_statusFilter != 'all') {
                    final status = (d['status'] ?? 'paid').toString();
                    if (status != _statusFilter) return false;
                  }
                  if (_typeFilter != 'all' && (d['type'] ?? 'expense').toString() != _typeFilter) {
                    return false;
                  }
                }
                if (_categoryFilter != null) {
                  final c = (d['category'] ?? '').toString().trim();
                  if (!FinanceCategoryMerger.sameCategoryGroup(c, _categoryFilter!)) return false;
                }
                if (_search.isNotEmpty) {
                  final accLabel = _financeAccountLabelForTx(d) ?? '';
                  final text = '${d['category'] ?? ''} ${d['description'] ?? ''} $accLabel'.toLowerCase();
                  if (!text.contains(_search)) return false;
                }
                if (_financeAccountFilterId != null) {
                  final aid = (d['financeAccountId'] ?? '').toString().trim();
                  if (aid != _financeAccountFilterId) return false;
                }
                return true;
              }).toList();

              docs = FinanceFaturaTransactionSort.sortedDocs(docs, _gridSortMode);

              if (docs.isEmpty) {
                // Mesmo com zero lançamentos no período (ex.: filtro "Pago" e só pendentes), mostra
                // pendentes + Saldos por conta + atalhos — paridade com Android/iOS e acesso a PIX/receita a confirmar.
                _ensureSaldoAberturaForPeriod(_from);
                final saldoAbertura = _saldoAberturaCached?.total ?? 0.0;
                final openingByAccount =
                    _saldoAberturaCached?.byAccount ?? const <String, double>{};
                final saldoAcumulado = _saldoAcumuladoConsolidado(
                  saldoAbertura: saldoAbertura,
                  balancePeriodFallback: 0,
                  periodNetByAccount: _stripPeriodNetPaidOverride,
                  accountFilterId: _financeAccountFilterId,
                  openingByAccount: openingByAccount,
                );
                final bottomPad = homeShellScrollBottomPadding(
                  context,
                  embeddedInHomeShell: widget.shellScrollController != null,
                  tail: 12,
                );
                return RefreshIndicator(
                      onRefresh: () async {
                        await _reloadMainPeriodDocsPull();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(AppStrings.refreshUpdated),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      },
                      child: ListView(
                        controller: widget.shellScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(bottom: bottomPad),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: _buildReceitasPendentesBand(context),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: _buildDespesasPendentesBand(context),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: _buildFaturaEmAbertoBand(context),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: _buildFinanceAccountsStrip(
                              context,
                              docs: const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                              openingByAccount: openingByAccount,
                              saldoAcumuladoConsolidado: saldoAcumulado,
                              semContaCount: 0,
                              stripPeriodNetPaidOverride: _stripPeriodNetPaidOverride,
                            ),
                          ),
                          FinanceSmartTipsCompactBar(
                            onVejaMais: () => unawaited(_openSmartTipsPreviewSheet(
                              docs: const [],
                              totalIncome: 0,
                              totalExpense: 0,
                              balancePeriod: 0,
                            )),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_mainPeriodLoading && _mainPeriodDocs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: SkeletonListLoader(itemCount: 4, itemHeight: 72),
                                  )
                                else ...[
                                Icon(Icons.account_balance_wallet_rounded, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhum lançamento no período.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Adicione sua primeira receita ou despesa para começar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FilledButton.icon(
                                      icon: const Icon(Icons.add_rounded, size: 20),
                                      label: const Text('Receita'),
                                      onPressed: widget.profile.hasActiveLicense ? () => _addTx(context, 'income') : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                                      style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      icon: const Icon(Icons.remove_rounded, size: 20),
                                      label: const Text('Despesa'),
                                      onPressed: widget.profile.hasActiveLicense ? () => _addTx(context, 'expense') : () => mostrarAvisoSeLicencaInativa(context, widget.profile),
                                      style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                                    ),
                                  ],
                                ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
              }

              final semContaAdv = _countTxSemConta(docs);

              final paidTotals = _sumPeriodTotalsFromDocs(docs, statusFilter: 'paid');
              double totalIncome = paidTotals.income;
              double totalExpense = paidTotals.expense;
              final sk = _mainPeriodServerKpis ?? _periodMergedKpis;
              if (sk != null) {
                totalIncome = sk.income;
                totalExpense = sk.expense;
              }
              final periodNetPaid = _periodNetPaidConsolidated(
                fallbackFromVisiblePaidDocs: paidTotals.income - paidTotals.expense,
                serverKpis: sk,
              );
              final balance = periodNetPaid;

              _ensureSaldoAberturaForPeriod(_from);
              final openingByAccount =
                  _saldoAberturaCached?.byAccount ?? const <String, double>{};
              final accountFilterId = _financeAccountFilterId?.trim();
              final saldoAbertura = accountFilterId != null && accountFilterId.isNotEmpty
                  ? (openingByAccount[accountFilterId] ?? 0.0)
                  : (_saldoAberturaCached?.total ?? 0.0);
              final saldoAcumulado = _saldoAcumuladoConsolidado(
                saldoAbertura: saldoAbertura,
                balancePeriodFallback: balance,
                periodNetByAccount: _stripPeriodNetPaidOverride,
                accountFilterId: accountFilterId,
                openingByAccount: openingByAccount,
              );

                  final bottomPad = homeShellScrollBottomPadding(
                  context,
                  embeddedInHomeShell: widget.shellScrollController != null,
                  tail: 12,
                );
                  final gridDocs = _filterDocsForGridListType(docs);
                  final nShow = gridDocs.length < _txDisplayLimit ? gridDocs.length : _txDisplayLimit;
                  final docsVisible = nShow == gridDocs.length ? gridDocs : gridDocs.sublist(0, nShow);
                  final hasMoreTx = gridDocs.length > docsVisible.length;

                  return RefreshIndicator(
                onRefresh: () async {
                  await _reloadMainPeriodDocsPull();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(AppStrings.refreshUpdated),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
                child: CustomScrollView(
                  controller: widget.shellScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverList(
                      delegate: SliverChildListDelegate([
                    if (_mainPeriodPullRefreshing && _mainPeriodLoading)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(minHeight: 4, color: AppColors.primary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'A sincronizar lançamentos… $_mainPeriodLoadedCount',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    // Despesas e receitas pendentes (igual painel)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: _buildReceitasPendentesBand(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: _buildDespesasPendentesBand(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: _buildFaturaEmAbertoBand(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: _buildFinanceAccountsStrip(
                        context,
                        docs: _mainPeriodDocs,
                        openingByAccount: openingByAccount,
                        saldoAcumuladoConsolidado: saldoAcumulado,
                        semContaCount: semContaAdv,
                        stripPeriodNetPaidOverride: _stripPeriodNetPaidOverride,
                      ),
                    ),
                    _buildFinanceMainKpiSection(
                      saldoAbertura: saldoAbertura,
                      totalIncome: totalIncome,
                      totalExpense: totalExpense,
                      saldoAcumulado: saldoAcumulado,
                    ),
                    FinanceSmartTipsCompactBar(
                      onVejaMais: () => unawaited(_openSmartTipsPreviewSheet(
                        docs: docs,
                        totalIncome: totalIncome,
                        totalExpense: totalExpense,
                        balancePeriod: balance,
                      )),
                    ),
                    if (docs.isNotEmpty) _buildGridListTypeBar(),
                    if (docs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: FinanceTransactionSortBar(
                          value: _gridSortMode,
                          onChanged: (mode) => setState(() => _gridSortMode = mode),
                        ),
                      ),
                    if (docs.isNotEmpty && gridDocs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Text(
                          _gridListTypeFilter == 'income'
                              ? 'Nenhuma receita no período com os filtros atuais.'
                              : 'Nenhuma despesa no período com os filtros atuais.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ),
                  if (gridDocs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Material(
                        color: Colors.white,
                        elevation: 2,
                        surfaceTintColor: Colors.white,
                        shadowColor: AppColors.deepBlueDark.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.receipt_long_rounded, size: 22, color: AppColors.primary.withValues(alpha: 0.9)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  hasMoreTx ? '${docsVisible.length} de ${gridDocs.length} lançamentos' : '${gridDocs.length} lançamento(s)',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                                ),
                              ),
                              if (!_gridSelectionMode) ...[
                                IconButton.filledTonal(
                                  tooltip: 'Lista em tela cheia com filtros',
                                  onPressed: () => _openFullscreenLancamentos(context),
                                  icon: const Icon(Icons.open_in_full_rounded, size: 22),
                                  style: IconButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                                    surfaceTintColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.26), width: 1),
                                    ),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () => setState(() => _gridSelectionMode = true),
                                  icon: const Icon(Icons.checklist_rounded, size: 20),
                                  label: Text(
                                    'Selecionar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AppColors.primary,
                                      letterSpacing: 0.15,
                                    ),
                                  ),
                                  style: _financeToolbarTonalFilledStyle(),
                                ),
                              ] else
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final pendingToConfirm = _gridSelectedPendingIdsAmong(docsVisible);
                                      return Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: () => setState(() {
                                          _gridSelectionMode = false;
                                          _gridSelectedIds.clear();
                                        }),
                                        style: _financeToolbarTonalFilledStyle(),
                                        child: Text(
                                          'Cancelar',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            color: AppColors.primary,
                                            letterSpacing: 0.15,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          final pending = <String>[];
                                          for (final doc in docsVisible) {
                                            final d = _txDataForMainPeriodDoc(doc);
                                            if ((d['status'] ?? 'paid').toString() == 'pending') pending.add(doc.id);
                                          }
                                          if (pending.isEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Nenhum pendente na lista visível.')),
                                            );
                                            return;
                                          }
                                          setState(() {
                                            _gridSelectedIds
                                              ..clear()
                                              ..addAll(pending);
                                          });
                                        },
                                        child: const Text('Sel. pendentes'),
                                      ),
                                      if (pendingToConfirm.isNotEmpty)
                                        FilledButton.icon(
                                          onPressed: () async {
                                            await _confirmarPagamentoEmLote(
                                              context,
                                              pendingToConfirm,
                                              successSnackBar: pendingToConfirm.length > 1
                                                  ? '${pendingToConfirm.length} lançamentos confirmados.'
                                                  : 'Lançamento confirmado.',
                                            );
                                            if (mounted) {
                                              setState(() {
                                                _gridSelectionMode = false;
                                                _gridSelectedIds.clear();
                                              });
                                            }
                                          },
                                          icon: const Icon(Icons.done_all_rounded, size: 20),
                                          label: Text('Confirmar (${pendingToConfirm.length})'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.success,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(48, 48),
                                            tapTargetSize: MaterialTapTargetSize.padded,
                                          ),
                                        ),
                                      if (_gridSelectedIds.isNotEmpty)
                                        FilledButton.icon(
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Excluir selecionados?'),
                                                content: Text(
                                                  '${_gridSelectedIds.length} lançamento(s) serão excluídos. Esta ação não pode ser desfeita.',
                                                ),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                                  FilledButton(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                                                    child: const Text('Excluir'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true && mounted) {
                                              await _deleteTxBatch(context, _gridSelectedIds.toList());
                                              if (mounted) {
                                                setState(() {
                                                  _gridSelectionMode = false;
                                                  _gridSelectedIds.clear();
                                                });
                                              }
                                            }
                                          },
                                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                          label: Text('Excluir (${_gridSelectedIds.length})'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.error,
                                            minimumSize: const Size(48, 48),
                                            tapTargetSize: MaterialTapTargetSize.padded,
                                          ),
                                        ),
                                    ],
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                      ]),
                    ),
                    // Lançamentos: lista lazy (constrói só o que aparece). Antes
                    // montava até 150 tiles de uma vez (jank no Android ao rolar/filtrar).
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final showHeader = i == 0 ||
                              _transactionCalendarDay(_txDataForMainPeriodDoc(docsVisible[i - 1])) !=
                                  _transactionCalendarDay(_txDataForMainPeriodDoc(docsVisible[i]));
                          final tile = FinanceTransactionListTile(
                            doc: docsVisible[i],
                            overrideData: _optimisticEditedTxById[docsVisible[i].id],
                            profile: widget.profile,
                            financeAccounts: _financeAccounts,
                            gridSelectionMode: _gridSelectionMode,
                            isSelected: _gridSelectedIds.contains(docsVisible[i].id),
                            optimisticPaidIds: _optimisticPaidIds,
                            onToggleSelection: () => setState(() {
                              final id = docsVisible[i].id;
                              if (_gridSelectedIds.contains(id)) {
                                _gridSelectedIds.remove(id);
                              } else {
                                _gridSelectedIds.add(id);
                              }
                            }),
                            onEdit: _editTx,
                            onDelete: _deleteTx,
                            onConfirmPayment: _confirmarPagamento,
                            onAttachReceipt: _attachReceipt,
                          );
                          if (!showHeader) return tile;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _financeDayHeader(
                                  _transactionCalendarDay(_txDataForMainPeriodDoc(docsVisible[i]))),
                              tile,
                            ],
                          );
                        },
                        childCount: docsVisible.length,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.only(bottom: bottomPad),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                  if (hasMoreTx)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Center(
                        child: FilledButton.tonalIcon(
                          onPressed: () => setState(() => _txDisplayLimit += _txPageSize),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text('Carregar mais (${docs.length - docsVisible.length} restantes)'),
                          style: _financeToolbarTonalFilledStyle(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            visualDensity: VisualDensity.standard,
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                      ),
                    ),
                  if (_mainPeriodServerPagingActive && _mainPeriodHasMoreServer)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: Center(
                        child: FilledButton.tonalIcon(
                          onPressed: _mainPeriodLoadingMore
                              ? null
                              : () => unawaited(_loadMoreMainPeriodFirestore(sessionUid)),
                          icon: _mainPeriodLoadingMore
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(
                            _mainPeriodLoadingMore
                                ? 'A carregar…'
                                : 'Carregar mais do servidor ($_kMainPeriodFirestorePageSize por pedido)',
                          ),
                          style: _financeToolbarTonalFilledStyle(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            visualDensity: VisualDensity.standard,
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                      ),
                    ),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
    ),
    ),
    );
  }
}

/// Sheet de receitas ou despesas pendentes com modo seleção e exclusão em lote.
class _PendingListSheetContent extends StatefulWidget {
  final String title;
  final Color iconColor;
  final List<Map<String, dynamic>> list;
  final ScrollController scrollController;
  final String emptyMessage;
  final Widget Function(
    BuildContext context,
    Map<String, dynamic> e, {
    bool selectionMode,
    bool isSelected,
    VoidCallback? onToggleSelect,
  }) buildItem;
  final Future<void> Function(List<String> ids) onDeleteBatch;
  /// Confirma pagamento/recebimento dos IDs selecionados (opcional).
  final Future<void> Function(BuildContext sheetContext, List<String> ids)? onConfirmBatch;
  final String batchConfirmShortLabel;

  const _PendingListSheetContent({
    required this.title,
    required this.iconColor,
    required this.list,
    required this.scrollController,
    required this.emptyMessage,
    required this.buildItem,
    required this.onDeleteBatch,
    this.onConfirmBatch,
    this.batchConfirmShortLabel = 'Confirmar',
  });

  @override
  State<_PendingListSheetContent> createState() => _PendingListSheetContentState();
}

class _PendingListSheetContentState extends State<_PendingListSheetContent> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _deletingBatch = false;
  bool _confirmingBatch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await shouldShowSheetSelectionHint() && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(AppStrings.sheetSelectionHint),
          behavior: SnackBarBehavior.floating,
        ));
        markSheetSelectionHintShown();
      }
    });
  }

  double get _totalValue => widget.list.fold<double>(0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble().abs());

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    // Layout em duas linhas (título + botões) em telas < 420px e sempre em modo seleção, para evitar título quebrado
    final width = MediaQuery.sizeOf(context).width;
    final useTwoRowHeader = width < 420 || _selectionMode;
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            // Topo do preview: «Voltar» (esquerda) + X (direita).
            buildFinancePreviewTopBar(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: useTwoRowHeader
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: widget.iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                              child: Icon(Icons.schedule_rounded, color: widget.iconColor, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (widget.list.isNotEmpty) Text('Total: ${CurrencyFormats.formatBRL(_totalValue)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.iconColor)),
                          ],
                        )),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildSelectionActions(useWrap: true),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: widget.iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                          child: Icon(Icons.schedule_rounded, color: widget.iconColor, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (widget.list.isNotEmpty) Text('Total: ${CurrencyFormats.formatBRL(_totalValue)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.iconColor)),
                          ],
                        )),
                        _buildSelectionActions(useWrap: false),
                      ],
                    ),
            ),
            Expanded(
              child: widget.list.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(widget.emptyMessage, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    addAutomaticKeepAlives: false,
                    cacheExtent: 520,
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomPadding),
                    itemCount: widget.list.length,
                    itemBuilder: (_, i) {
                      final e = widget.list[i];
                      final id = (e['id'] ?? '').toString();
                      return widget.buildItem(
                        context,
                        e,
                        selectionMode: _selectionMode,
                        isSelected: _selectedIds.contains(id),
                        onToggleSelect: () => setState(() {
                          if (_selectedIds.contains(id)) _selectedIds.remove(id); else _selectedIds.add(id);
                        }),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionActions({required bool useWrap}) {
    if (!_selectionMode) {
      return Semantics(
        label: AppStrings.semanticsSelect,
        button: true,
        child: TextButton.icon(
          onPressed: () => setState(() => _selectionMode = true),
          icon: const Icon(Icons.checklist_rounded, size: 20),
          label: const Text(AppStrings.select),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded),
        ),
      );
    }
    final idList = widget.list
        .map((e) => (e['id'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final buttons = <Widget>[
      TextButton(
        onPressed: () => setState(() { _selectionMode = false; _selectedIds.clear(); }),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded),
        child: const Text(AppStrings.cancel),
      ),
      if (widget.list.isNotEmpty)
        TextButton(
          onPressed: () => setState(() {
            _selectedIds
              ..clear()
              ..addAll(idList);
          }),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded),
          child: const Text('Todos'),
        ),
      if (widget.onConfirmBatch != null && _selectedIds.isNotEmpty)
        FilledButton.icon(
          onPressed: (_deletingBatch || _confirmingBatch) ? null : () async {
            setState(() => _confirmingBatch = true);
            try {
              await widget.onConfirmBatch!(context, _selectedIds.toList());
            } finally {
              if (mounted) setState(() => _confirmingBatch = false);
            }
          },
          icon: _confirmingBatch
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.done_all_rounded, size: 20),
          label: Text(_confirmingBatch ? '…' : '${widget.batchConfirmShortLabel} (${_selectedIds.length})'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      if (_selectedIds.isNotEmpty)
        Semantics(
          label: AppStrings.semanticsDeleteBatch,
          button: true,
          child: FilledButton.icon(
            onPressed: (_deletingBatch || _confirmingBatch) ? null : () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text(AppStrings.deleteSelected),
                  content: Text('${_selectedIds.length} ${AppStrings.deleteSelectedConfirm}'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(AppStrings.cancel)),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: const Text(AppStrings.delete)),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                setState(() => _deletingBatch = true);
                await widget.onDeleteBatch(_selectedIds.toList());
                if (mounted) setState(() => _deletingBatch = false);
              }
            },
            icon: _deletingBatch ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.delete_outline_rounded, size: 20),
            label: Text(_deletingBatch ? 'Excluindo...' : 'Excluir (${_selectedIds.length})'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded),
          ),
        ),
    ];
    if (useWrap) {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.end,
        children: buttons,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: buttons,
    );
  }
}

enum FinanceInsightScope { income, expense, balance }

String _insightPercentLabel(double part, double total, FinanceInsightScope scope) {
  final base = total.abs();
  if (base < 0.005) return '0,0';
  return ((part.abs() / base) * 100).toStringAsFixed(1);
}

class FinanceInsightSheet extends StatefulWidget {
  final String uid;
  final FinanceInsightScope initialScope;
  final DateTime initialFrom;
  final DateTime initialTo;
  /// Quando definido (ex.: toque em "Onde foi o dinheiro"), abre já filtrado nesta categoria.
  final String? initialCategoryExact;
  final String statusFilter;
  final String search;
  /// Mesmo filtro de conta do painel Financeiro.
  final String? financeAccountFilterId;
  final String? financeAccountFilterLabel;
  /// Cache do saldo de abertura (painel/Financeiro) — evita piscar zerado ao abrir.
  final double? openingBalanceHint;
  final Map<String, double>? openingByAccountHint;
  final Future<void> Function(String docId, Map<String, dynamic> current, String type) onEdit;
  final Future<void> Function(String docId) onDelete;

  const FinanceInsightSheet({
    required this.uid,
    required this.initialScope,
    required this.initialFrom,
    required this.initialTo,
    this.initialCategoryExact,
    required this.statusFilter,
    required this.search,
    this.financeAccountFilterId,
    this.financeAccountFilterLabel,
    this.openingBalanceHint,
    this.openingByAccountHint,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<FinanceInsightSheet> createState() => FinanceInsightSheetState();
}

class FinanceInsightSheetState extends State<FinanceInsightSheet> {
  static const int _kInsightPageSize = 30;
  late FinanceInsightScope _scope;
  String _sortMode = 'date_desc';
  String _periodFilter = 'Mensal';
  String _selectedCategory = '__all__';
  late DateTime _from;
  late DateTime _to;
  late Future<List<Map<String, dynamic>>> _docsFuture;
  /// Igual ao painel Financeiro: `all` | `paid` | `pending` — refiltra a consulta.
  late String _statusLocal;
  String _localSearch = '';
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounceTimer;
  /// Categorias do usuário (padrão + custom) — inclui Empréstimo mesmo sem lançamento no período.
  List<String> _userCategoryNames = [];
  late Future<({double income, double expense})> _periodSummaryFuture;
  /// Em modo Saldo: filtra linhas por tipo (`''` = todos).
  String _typeRowFilter = '';
  int _visibleRowsLimit = _kInsightPageSize;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txWatchSub;
  Timer? _txWatchDebounce;
  double _openingTotal = 0.0;
  Map<String, double> _openingByAccount = const {};

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _from = DateTime(widget.initialFrom.year, widget.initialFrom.month, widget.initialFrom.day);
    _to = DateTime(widget.initialTo.year, widget.initialTo.month, widget.initialTo.day, 23, 59, 59);
    final cat = widget.initialCategoryExact?.trim();
    _selectedCategory = (cat != null && cat.isNotEmpty) ? cat : '__all__';
    _statusLocal = widget.statusFilter;
    _searchCtrl.text = widget.search;
    _localSearch = widget.search.trim().toLowerCase();
    _docsFuture = _fetchFilteredTransactions(_from, _to);
    _periodSummaryFuture = _loadPeriodSummary();
    _seedOpeningFromHints();
    unawaited(_loadUserCategoryNames());
    unawaited(_refreshOpeningBalance());
    FinanceTransactionsHub.revision.addListener(_onFinanceHubRevision);
    _bindTransactionsWatch();
  }

  void _seedOpeningFromHints() {
    final peek = FinanceOpeningBalanceService.peekCached(
      uid: widget.uid,
      periodStart: _from,
      loadAccounts: true,
    );
    if (peek != null) {
      _openingTotal = peek.total;
      _openingByAccount = Map<String, double>.from(peek.byAccount);
      return;
    }
    if (widget.openingBalanceHint != null) {
      _openingTotal = widget.openingBalanceHint!;
      _openingByAccount = Map<String, double>.from(widget.openingByAccountHint ?? const {});
    }
  }

  Future<void> _refreshOpeningBalance() async {
    try {
      final r = await FinanceOpeningBalanceService.load(
        uid: widget.uid,
        periodStart: _from,
        loadAccounts: true,
      );
      if (!mounted) return;
      setState(() {
        _openingTotal = r.total;
        _openingByAccount = Map<String, double>.from(r.byAccount);
      });
    } catch (_) {}
  }

  double get _effectiveOpeningBalance {
    final fid = widget.financeAccountFilterId?.trim();
    if (fid != null && fid.isNotEmpty) {
      return _openingByAccount[fid] ?? 0.0;
    }
    return _openingTotal;
  }

  void _bindTransactionsWatch() {
    _txWatchSub?.cancel();
    final fsId = firestoreUserDocIdForAppShell(widget.uid);
    if (fsId.isEmpty) return;
    _txWatchSub = FirebaseFirestore.instance
        .collection('users')
        .doc(fsId)
        .collection('transactions')
        .limit(1)
        .snapshots(includeMetadataChanges: false)
        .listen((_) => _scheduleDocsReloadDebounced());
  }

  void _onFinanceHubRevision() {
    if (!mounted) return;
    _scheduleDocsReloadDebounced();
  }

  void _scheduleDocsReloadDebounced() {
    _txWatchDebounce?.cancel();
    _txWatchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _scheduleDocsReload();
    });
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_onFinanceHubRevision);
    _txWatchDebounce?.cancel();
    _txWatchSub?.cancel();
    _searchDebounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _scheduleDocsReload() {
    setState(() {
      _visibleRowsLimit = _kInsightPageSize;
      _docsFuture = _fetchFilteredTransactions(_from, _to);
      _periodSummaryFuture = _loadPeriodSummary();
    });
    unawaited(_refreshOpeningBalance());
  }

  String get _voltarLabel =>
      widget.financeAccountFilterId != null ? 'Voltar à lista de contas' : 'Voltar';

  Future<({double income, double expense})> _loadPeriodSummary() async {
    final r = await FinancePeriodSummary.load(
      uid: widget.uid,
      from: _from,
      to: _to,
      statusFilter: _statusLocal,
      typeFilter: 'all',
    );
    return (income: r.income, expense: r.expense);
  }

  void _reloadPeriodSummary() {
    setState(() => _periodSummaryFuture = _loadPeriodSummary());
  }

  Future<void> _loadUserCategoryNames() async {
    try {
      final loaded = await UserCategoriesService().load(widget.uid);
      final names = _scope == FinanceInsightScope.income
          ? UserCategoriesService.sortedWithoutIncluirNova(loaded.income)
          : UserCategoriesService.sortedWithoutIncluirNova(loaded.expense);
      if (mounted) setState(() => _userCategoryNames = names);
    } catch (_) {}
  }

  String get _title => switch (_scope) {
        FinanceInsightScope.income => 'Receitas do período',
        FinanceInsightScope.expense => 'Despesas do período',
        FinanceInsightScope.balance => 'Saldo do período',
      };

  Color get _accentColor => switch (_scope) {
        FinanceInsightScope.income => AppColors.financeReceita,
        FinanceInsightScope.expense => AppColors.financeDespesa,
        FinanceInsightScope.balance => AppColors.primary,
      };

  Future<List<Map<String, dynamic>>> _fetchFilteredTransactions(DateTime from, DateTime to) async {
    final docs = await FinanceInsightQuery.fetchPeriodDocs(
      uid: widget.uid,
      from: from,
      to: to,
      statusFilter: _statusLocal,
      financeAccountId: widget.financeAccountFilterId,
    );
    final rows = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final d = doc.data();
      if (_localSearch.isNotEmpty) {
        final text = '${d['category'] ?? ''} ${d['description'] ?? ''}'.toLowerCase();
        if (!text.contains(_localSearch)) continue;
      }
      rows.add({'id': doc.id, 'raw': d});
    }
    return rows;
  }

  Future<double> _loadComparisonTotal(DateTime from, DateTime to, FinanceInsightScope scope) async {
    final days = to.difference(from).inDays + 1;
    final prevStart = from.subtract(Duration(days: days));
    final prevEnd = from.subtract(const Duration(seconds: 1));
    final prevRows = await _fetchFilteredTransactions(prevStart, prevEnd);
    return _computeScopeTotal(prevRows, scope);
  }

  double _computeScopeTotal(List<Map<String, dynamic>> baseRows, FinanceInsightScope scope) {
    var total = 0.0;
    for (final row in baseRows) {
      final d = Map<String, dynamic>.from(row['raw'] as Map<String, dynamic>);
      final type = (d['type'] ?? 'expense').toString();
      final amount = ((d['amount'] ?? 0) as num).toDouble().abs();
      if (scope == FinanceInsightScope.income && type == 'income') total += amount;
      if (scope == FinanceInsightScope.expense && type == 'expense') total += amount;
      if (scope == FinanceInsightScope.balance) total += type == 'income' ? amount : -amount;
    }
    return total;
  }

  void _applyPeriodFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _periodFilter = filter;
      if (filter == 'Mensal') {
        _from = DateTime(now.year, now.month, 1);
        _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      } else if (filter == 'Anual') {
        _from = DateTime(now.year, 1, 1);
        _to = DateTime(now.year, 12, 31, 23, 59, 59);
      }
      _selectedCategory = '__all__';
      _visibleRowsLimit = _kInsightPageSize;
      _docsFuture = _fetchFilteredTransactions(_from, _to);
      _periodSummaryFuture = _loadPeriodSummary();
    });
    unawaited(_refreshOpeningBalance());
  }

  Future<void> _pickCustomPeriod() async {
    final pFrom = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pFrom == null || !mounted) return;
    final pTo = await showDatePicker(
      context: context,
      initialDate: _to.isBefore(pFrom) ? pFrom : _to,
      firstDate: pFrom,
      lastDate: DateTime(2100),
    );
    if (pTo == null || !mounted) return;
    setState(() {
      _periodFilter = 'Período';
      _from = DateTime(pFrom.year, pFrom.month, pFrom.day);
      _to = DateTime(pTo.year, pTo.month, pTo.day, 23, 59, 59);
      _selectedCategory = '__all__';
      _visibleRowsLimit = _kInsightPageSize;
      _docsFuture = _fetchFilteredTransactions(_from, _to);
      _periodSummaryFuture = _loadPeriodSummary();
    });
    unawaited(_refreshOpeningBalance());
  }

  List<Map<String, dynamic>> _rowsByScope(List<Map<String, dynamic>> baseRows, [String? categoryFilter]) {
    final catKey = categoryFilter ?? _selectedCategory;
    final rows = <Map<String, dynamic>>[];
    for (final item in baseRows) {
      final d = Map<String, dynamic>.from(item['raw'] as Map<String, dynamic>);
      final type = (d['type'] ?? 'expense').toString();
      final include = switch (_scope) {
        FinanceInsightScope.income => type == 'income',
        FinanceInsightScope.expense => type == 'expense',
        FinanceInsightScope.balance => true,
      };
      if (!include) continue;
      if (_scope == FinanceInsightScope.balance && _typeRowFilter.isNotEmpty && type != _typeRowFilter) {
        continue;
      }
      final amount = ((d['amount'] ?? 0) as num).toDouble().abs();
      final category = (d['category'] ?? '').toString().trim();
      final description = (d['description'] ?? '').toString().trim();
      final ts = d['date'];
      final date = FinanceLineOpening.effectiveDateTimeFromMap(d) ??
          (ts is Timestamp ? ts.toDate() : null);
      rows.add({
        'id': (item['id'] ?? '').toString(),
        'type': type,
        'amount': amount,
        'category': category.isEmpty ? 'Sem categoria' : category,
        'description': description,
        'date': date,
        'raw': d,
      });
    }

    final filteredRows = catKey == '__all__'
        ? rows
        : rows
            .where((r) => FinanceCategoryMerger.sameCategoryGroup((r['category'] ?? '').toString(), catKey))
            .toList();

    filteredRows.sort((a, b) {
      final aAmount = (a['amount'] ?? 0.0) as double;
      final bAmount = (b['amount'] ?? 0.0) as double;
      final aDate = a['date'] as DateTime?;
      final bDate = b['date'] as DateTime?;
      switch (_sortMode) {
        case 'amount_asc':
          return aAmount.compareTo(bAmount);
        case 'date_desc':
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        case 'date_asc':
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        case 'amount_desc':
        default:
          return bAmount.compareTo(aAmount);
      }
    });
    return filteredRows;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.96,
        minChildSize: 0.62,
        builder: (context, controller) => Container(
          decoration: financePremiumSheetDecoration(surfaceTint: _accentColor),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _docsFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _financeInsightVoltarBar(context),
                    const SizedBox(height: 28),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 28),
                    _financeInsightVoltarBar(context),
                  ],
                );
              }
              final baseRows = snap.data!;
              final allCategoryTotals = <String, double>{};
              final insightMerger = FinanceCategoryMerger();
              for (final item in baseRows) {
                final d = Map<String, dynamic>.from(item['raw'] as Map<String, dynamic>);
                final type = (d['type'] ?? 'expense').toString();
                final include = switch (_scope) {
                  FinanceInsightScope.income => type == 'income',
                  FinanceInsightScope.expense => type == 'expense',
                  FinanceInsightScope.balance => true,
                };
                if (!include) continue;
                final catRaw = (d['category'] ?? '').toString();
                final val = ((d['amount'] ?? 0) as num).toDouble().abs();
                insightMerger.addAmount(allCategoryTotals, catRaw, val);
              }
              final allCategoryOptions = <String>{
                ..._userCategoryNames,
                ...allCategoryTotals.keys,
              }.toList()
                ..sort(UserCategoriesService.compareNamesPt);
              final effectiveCategory =
                  _selectedCategory == '__all__' ||
                          allCategoryOptions.any((k) => FinanceCategoryMerger.sameCategoryGroup(k, _selectedCategory))
                      ? _selectedCategory
                      : '__all__';
              final rows = _rowsByScope(baseRows, effectiveCategory);
              final rowsVisible = rows.length <= _visibleRowsLimit
                  ? rows
                  : rows.take(_visibleRowsLimit).toList();
              final hasMoreRows = rows.length > rowsVisible.length;
              final incomeTotal = rows
                  .where((r) => (r['type'] ?? 'expense') == 'income')
                  .fold<double>(0, (s, r) => s + ((r['amount'] ?? 0.0) as double));
              final expenseTotal = rows
                  .where((r) => (r['type'] ?? 'expense') == 'expense')
                  .fold<double>(0, (s, r) => s + ((r['amount'] ?? 0.0) as double));
              final saldoPeriodo = incomeTotal - expenseTotal;
              final total = _scope == FinanceInsightScope.balance
                  ? saldoPeriodo
                  : rows.fold<double>(0, (sum, r) => sum + ((r['amount'] ?? 0.0) as double));
              final categoryTotals = <String, double>{};
              final rowMerger = FinanceCategoryMerger();
              for (final r in rows) {
                final catRaw = (r['category'] ?? '').toString();
                final val = (r['amount'] ?? 0.0) as double;
                rowMerger.addAmount(categoryTotals, catRaw, val);
              }
              final clickableCatEntries = allCategoryTotals.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final maxCatVal = clickableCatEntries.isEmpty
                  ? 1.0
                  : clickableCatEntries.first.value;
              final sortedCats = categoryTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              final catPieSegments = sortedCats.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final palette = [
                  AppColors.financeReceita,
                  AppColors.financeDespesa,
                  AppColors.financePendente,
                  AppColors.primary,
                  AppColors.accent,
                  AppColors.secondary,
                ];
                return (
                  label: e.key.length > 18 ? '${e.key.substring(0, 18)}…' : e.key,
                  value: e.value,
                  color: palette[i % palette.length],
                );
              }).toList();

              return FutureBuilder<({double income, double expense})>(
                future: _periodSummaryFuture,
                builder: (context, summarySnap) {
                  final summary = summarySnap.data;
                  final authoritativeIncome = summary?.income ?? incomeTotal;
                  final authoritativeExpense = summary?.expense ?? expenseTotal;
                  final saldoPeriodo = authoritativeIncome - authoritativeExpense;
                  final effectiveOpening = _effectiveOpeningBalance;
                  final saldoAcumulado = effectiveOpening + saldoPeriodo;
                  final authoritativeTotal = summary == null
                      ? (_scope == FinanceInsightScope.balance ? saldoAcumulado : total)
                      : switch (_scope) {
                          FinanceInsightScope.income => summary.income,
                          FinanceInsightScope.expense => summary.expense,
                          FinanceInsightScope.balance =>
                              effectiveOpening + summary.income - summary.expense,
                        };
                  final saldoPieSegments = [
                    (label: 'Receitas', value: authoritativeIncome, color: AppColors.financeReceita),
                    (label: 'Despesas', value: authoritativeExpense, color: AppColors.financeDespesa),
                  ];

              return FutureBuilder<double>(
                future: _loadComparisonTotal(_from, _to, _scope),
                builder: (context, cmpSnap) {
                  final previousTotal = cmpSnap.data ?? 0.0;
                  final deltaPrev = authoritativeTotal - previousTotal;
                  final deltaPct = previousTotal.abs() > 0.0001
                      ? (deltaPrev / previousTotal.abs()) * 100
                      : (deltaPrev == 0 ? 0.0 : 100.0);
                  final previousLabel = (() {
                    final days = _to.difference(_from).inDays + 1;
                    final prevStart = _from.subtract(Duration(days: days));
                    final prevEnd = _from.subtract(const Duration(seconds: 1));
                    return '${DateFormat('dd/MM').format(prevStart)} a ${DateFormat('dd/MM').format(prevEnd)}';
                  })();

                  return ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FinancePremiumSheetHeader(
                title: _title,
                subtitle: '${DateFormat('dd/MM/yyyy').format(_from)} — ${DateFormat('dd/MM/yyyy').format(_to)}',
                icon: switch (_scope) {
                  FinanceInsightScope.income => Icons.trending_up_rounded,
                  FinanceInsightScope.expense => Icons.trending_down_rounded,
                  FinanceInsightScope.balance => Icons.account_balance_wallet_rounded,
                },
                iconGradient: [
                  _accentColor,
                  Color.lerp(_accentColor, AppColors.accent, 0.45)!,
                ],
                onBack: () => Navigator.pop(context),
                titleColor: _accentColor,
              ),
              const SizedBox(height: 10),
              FinanceInsightPeriodTotalizer(
                income: authoritativeIncome,
                expense: authoritativeExpense,
                openingBalance: effectiveOpening,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _scopeChip('Receitas', FinanceInsightScope.income, AppColors.financeReceita),
                  _scopeChip('Despesas', FinanceInsightScope.expense, AppColors.financeDespesa),
                  _scopeChip('Saldo', FinanceInsightScope.balance, AppColors.primary),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _periodChip('Mensal'),
                  _periodChip('Anual'),
                  _periodChip('Período'),
                ],
              ),
              if (_periodFilter == 'Período') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickCustomPeriod,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                    '${DateFormat('dd/MM').format(_from)} a ${DateFormat('dd/MM').format(_to)}',
                  ),
                ),
              ],
              if (widget.financeAccountFilterId != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF166534).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.filter_alt_rounded, size: 20, color: Colors.green.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Conta (igual ao painel): ${(widget.financeAccountFilterLabel ?? '').trim().isEmpty ? 'Conta filtrada' : widget.financeAccountFilterLabel!.trim()}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Colors.green.shade900,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: FastTextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Pesquisar categoria ou descrição…',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    _searchDebounceTimer?.cancel();
                    _searchDebounceTimer = Timer(
                      Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                      () {
                        if (!mounted) return;
                        setState(() {
                          _localSearch = v.trim().toLowerCase();
                          _visibleRowsLimit = _kInsightPageSize;
                          _docsFuture = _fetchFilteredTransactions(_from, _to);
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Status dos lançamentos',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Todos'),
                    selected: _statusLocal == 'all',
                    onSelected: (_) => setState(() {
                      _statusLocal = 'all';
                      _visibleRowsLimit = _kInsightPageSize;
                      _docsFuture = _fetchFilteredTransactions(_from, _to);
                      _periodSummaryFuture = _loadPeriodSummary();
                    }),
                    selectedColor: _accentColor.withValues(alpha: 0.22),
                    checkmarkColor: _accentColor,
                  ),
                  FilterChip(
                    label: const Text('Pago'),
                    selected: _statusLocal == 'paid',
                    onSelected: (_) => setState(() {
                      _statusLocal = 'paid';
                      _visibleRowsLimit = _kInsightPageSize;
                      _docsFuture = _fetchFilteredTransactions(_from, _to);
                      _periodSummaryFuture = _loadPeriodSummary();
                    }),
                    selectedColor: _accentColor.withValues(alpha: 0.22),
                    checkmarkColor: _accentColor,
                  ),
                  FilterChip(
                    label: const Text('Pendente'),
                    selected: _statusLocal == 'pending',
                    onSelected: (_) => setState(() {
                      _statusLocal = 'pending';
                      _visibleRowsLimit = _kInsightPageSize;
                      _docsFuture = _fetchFilteredTransactions(_from, _to);
                      _periodSummaryFuture = _loadPeriodSummary();
                    }),
                    selectedColor: _accentColor.withValues(alpha: 0.22),
                    checkmarkColor: _accentColor,
                  ),
                ],
              ),
              if (_scope == FinanceInsightScope.balance) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tipo na lista (saldo)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Receitas e despesas'),
                      selected: _typeRowFilter.isEmpty,
                      onSelected: (_) => setState(() => _typeRowFilter = ''),
                      selectedColor: _accentColor.withValues(alpha: 0.22),
                      checkmarkColor: _accentColor,
                    ),
                    FilterChip(
                      label: const Text('Só receitas'),
                      selected: _typeRowFilter == 'income',
                      onSelected: (_) => setState(() => _typeRowFilter = 'income'),
                      selectedColor: AppColors.financeReceita.withValues(alpha: 0.22),
                      checkmarkColor: AppColors.financeReceita,
                    ),
                    FilterChip(
                      label: const Text('Só despesas'),
                      selected: _typeRowFilter == 'expense',
                      onSelected: (_) => setState(() => _typeRowFilter = 'expense'),
                      selectedColor: AppColors.financeDespesa.withValues(alpha: 0.22),
                      checkmarkColor: AppColors.financeDespesa,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.category_rounded, size: 22, color: _accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Categoria', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            effectiveCategory == '__all__' ? 'Todas as categorias' : effectiveCategory,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () async {
                        final picked = await showFinanceCategoryPicker(
                          context: context,
                          isIncome: _scope == FinanceInsightScope.income,
                          uid: widget.uid,
                          initialQuery: effectiveCategory == '__all__' ? '' : effectiveCategory,
                          extraCategories: allCategoryOptions,
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _selectedCategory = picked.isEmpty ? '__all__' : picked;
                            _visibleRowsLimit = _kInsightPageSize;
                          });
                        }
                      },
                      style: FilledButton.styleFrom(
                        foregroundColor: _accentColor,
                        backgroundColor: _accentColor.withValues(alpha: 0.12),
                      ),
                      child: const Text('Escolher'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _financeInsightChip(
                    'Total',
                    CurrencyFormats.formatBRLTight(authoritativeTotal),
                    _accentColor,
                  ),
                  _financeInsightChip(
                    'Itens',
                    '${rowsVisible.length}${hasMoreRows ? ' de ${rows.length}' : ''}',
                    AppColors.textSecondary,
                  ),
                  _financeInsightChip(
                    'Período anterior ($previousLabel)',
                    CurrencyFormats.formatBRLTight(previousTotal),
                    AppColors.textMuted,
                  ),
                  _financeInsightChip(
                    'Comparativo',
                    '${deltaPrev >= 0 ? '+' : ''}${CurrencyFormats.formatBRLTight(deltaPrev)} (${deltaPct.toStringAsFixed(1)}%)',
                    deltaPrev >= 0 ? AppColors.financeReceita : AppColors.financeDespesa,
                  ),
                  _financeInsightChip(
                    'Saldo abertura',
                    CurrencyFormats.formatBRLTight(effectiveOpening),
                    effectiveOpening >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                  ),
                  if (_scope == FinanceInsightScope.balance)
                    _financeInsightChip(
                      'Mov. período',
                      CurrencyFormats.formatBRLTight(saldoPeriodo),
                      saldoPeriodo >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                    ),
                  if (_scope == FinanceInsightScope.balance)
                    _financeInsightChip(
                      'Saldo (acum.)',
                      CurrencyFormats.formatBRLTight(saldoAcumulado),
                      saldoAcumulado >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                    ),
                ],
              ),
              if (sortedCats.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < sortedCats.length && i < 3; i++)
                        _financeInsightChip(
                          'Top ${i + 1}: ${sortedCats[i].key}',
                          '${_insightPercentLabel(sortedCats[i].value, authoritativeTotal, _scope)}%',
                          _accentColor,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sort_rounded, size: 18),
                    const SizedBox(width: 8),
                    const Text('Ordenar', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sortMode,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'amount_desc', child: Text('Valor (maior > menor)')),
                            DropdownMenuItem(value: 'amount_asc', child: Text('Valor (menor > maior)')),
                            DropdownMenuItem(value: 'date_desc', child: Text('Data (mais recente)')),
                            DropdownMenuItem(value: 'date_asc', child: Text('Data (mais antiga)')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _sortMode = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filtro rápido (clique na barra da categoria)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    if (allCategoryTotals.isEmpty)
                      const Text('Sem categorias no período.')
                    else
                      ...clickableCatEntries.map((entry) {
                        final selected = _selectedCategory == entry.key;
                        final ratio =
                            maxCatVal <= 0 ? 0.05 : (entry.value / maxCatVal).clamp(0.05, 1.0);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() {
                              _selectedCategory = selected ? '__all__' : entry.key;
                              _visibleRowsLimit = _kInsightPageSize;
                            }),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    entry.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 6,
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor: ratio,
                                        child: Container(
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? _accentColor
                                                : _accentColor.withValues(alpha: 0.65),
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  CurrencyFormats.formatBRLTight(entry.value),
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AppPieChart(
                title: _scope == FinanceInsightScope.balance
                    ? 'Receitas x Despesas'
                    : 'Distribuição por categoria',
                segments: _scope == FinanceInsightScope.balance
                    ? saldoPieSegments
                    : catPieSegments,
              ),
              const SizedBox(height: 10),
              const Text(
                'Lançamentos',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Text('Sem lançamentos para este preview.'),
                )
              else
                ...rowsVisible.map((r) {
                  final amount = (r['amount'] ?? 0.0) as double;
                  final category = (r['category'] ?? 'Sem categoria').toString();
                  final description = (r['description'] ?? '').toString();
                  final date = r['date'] as DateTime?;
                  final type = (r['type'] ?? 'expense').toString();
                  final id = (r['id'] ?? '').toString();
                  final percentBase = switch (_scope) {
                    FinanceInsightScope.income => authoritativeIncome,
                    FinanceInsightScope.expense => authoritativeExpense,
                    FinanceInsightScope.balance => authoritativeIncome + authoritativeExpense,
                  };
                  final percent = percentBase > 0 ? (amount.abs() / percentBase) * 100 : 0.0;
                  return FinanceInsightTransactionCard(
                    category: category,
                    description: description,
                    amount: amount,
                    date: date,
                    isIncome: type == 'income',
                    percent: percent,
                    onEdit: () async {
                      await widget.onEdit(id, Map<String, dynamic>.from(r['raw'] as Map<String, dynamic>), type);
                      if (mounted) _scheduleDocsReload();
                    },
                    onDelete: () async {
                      await widget.onDelete(id);
                      if (mounted) _scheduleDocsReload();
                    },
                  );
                }),
                if (hasMoreRows)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: FilledButton.tonalIcon(
                      onPressed: () => setState(() {
                        _visibleRowsLimit += _kInsightPageSize;
                      }),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text('Carregar mais (${rowsVisible.length}/${rows.length})'),
                    ),
                  ),
                const SizedBox(height: 8),
                    ],
                  );
                },
              );
                },
              );
            },
          ),
        ),
      ),
      ),
    );
  }

  /// Botão largo “Voltar” no topo e no fim do preview (uso com uma mão no iPhone).
  Widget _financeInsightVoltarBar(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
        label: Text(_voltarLabel),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          foregroundColor: _accentColor,
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _scopeChip(String label, FinanceInsightScope scope, Color color) {
    final selected = _scope == scope;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _scope = scope;
          _selectedCategory = '__all__';
          _visibleRowsLimit = _kInsightPageSize;
          if (scope != FinanceInsightScope.balance) _typeRowFilter = '';
          _periodSummaryFuture = _loadPeriodSummary();
        });
        unawaited(_loadUserCategoryNames());
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selected ? color : AppColors.textSecondary,
      ),
      side: BorderSide(color: color.withValues(alpha: selected ? 0.85 : 0.35), width: selected ? 2 : 1),
    );
  }

  Widget _periodChip(String label) {
    final selected = _periodFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (label == 'Período') {
          _pickCustomPeriod();
          return;
        }
        _applyPeriodFilter(label);
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selected ? _accentColor : AppColors.textSecondary,
      ),
      side: BorderSide(color: _accentColor.withValues(alpha: selected ? 0.85 : 0.35), width: selected ? 2 : 1),
    );
  }

  Widget _financeInsightChip(String label, String value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opções agregadas para export PDF/CSV a partir do bottom sheet premium.
class _FinanceReportExportOpts {
  final DateTime from;
  final DateTime to;
  final String? categoryExact;

  const _FinanceReportExportOpts({
    required this.from,
    required this.to,
    this.categoryExact,
  });
}

/// Bottom sheet: períodos rápidos + categoria opcional → PDF com preview (mesmo fluxo dos Relatórios).
class _FinanceReportsPremiumSheet extends StatefulWidget {
  final DateTime screenFrom;
  final DateTime screenTo;
  final String uid;
  final String statusFilter;
  final String? filenameAccountSuffix;
  final String semCategoriaToken;
  final void Function(_FinanceReportExportOpts opts) onExportPdf;
  final void Function(_FinanceReportExportOpts opts) onExportCsv;

  const _FinanceReportsPremiumSheet({
    required this.screenFrom,
    required this.screenTo,
    required this.uid,
    required this.statusFilter,
    this.filenameAccountSuffix,
    required this.semCategoriaToken,
    required this.onExportPdf,
    required this.onExportCsv,
  });

  @override
  State<_FinanceReportsPremiumSheet> createState() => _FinanceReportsPremiumSheetState();
}

class _FinanceReportsPremiumSheetState extends State<_FinanceReportsPremiumSheet> {
  /// Filtro simples do relatório: 1 = mensal; 4 = anual; 5 = período livre.
  int _rangeMode = 1;
  late DateTime _cFrom;
  late DateTime _cTo;
  String? _categoryChoice;
  late final Future<
      ({
        List<String> income,
        List<String> expense,
        List<String> hiddenDefaultIncome,
        List<String> hiddenDefaultExpense,
      })> _catsFuture;
  @override
  void initState() {
    super.initState();
    _cFrom = widget.screenFrom;
    _cTo = widget.screenTo;
    _catsFuture = UserCategoriesService().load(firestoreUserDocIdForAppShell(widget.uid));
  }

  String _previewFilenameBase(DateTime rf, DateTime rt) {
    final accSuf = widget.filenameAccountSuffix;
    return RelatorioService.reportFilenameFromPeriod(
      'despesa_receita',
      rf,
      rt,
      accSuf != null && accSuf.isNotEmpty ? '— $accSuf' : null,
    );
  }

  (DateTime, DateTime) _resolveRange() {
    final now = DateTime.now();
    switch (_rangeMode) {
      case 1:
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
      case 4:
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
      default:
        final cf = DateTime(_cFrom.year, _cFrom.month, _cFrom.day);
        var ct = DateTime(_cTo.year, _cTo.month, _cTo.day, 23, 59, 59);
        if (ct.isBefore(cf)) ct = DateTime(cf.year, cf.month, cf.day, 23, 59, 59);
        return (cf, ct);
    }
  }

  Widget _modeChip(String label, int mode, Color accent) {
    final sel = _rangeMode == mode;
    final darker = Color.lerp(accent, Colors.black, 0.14) ?? accent;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _rangeMode = mode),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: sel ? LinearGradient(colors: [accent, darker], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: sel ? null : Colors.white,
              border: Border.all(color: accent.withValues(alpha: sel ? 0 : 0.55), width: sel ? 0 : 2),
              boxShadow: sel
                  ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sel) ...[
                  const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: sel ? Colors.white : accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    final (rf, rt) = _resolveRange();
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -4))],
          ),
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottom),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.primary),
                    label: const Text('Voltar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, Color.lerp(AppColors.primary, AppColors.accent, 0.5)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Relatórios financeiros', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        Text(
                          'Escolha o período e, se quiser, filtre por categoria. O PDF usa o mesmo filtro Pago/Pendente/Todos da tela.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Período do relatório', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
              const SizedBox(height: 10),
              Wrap(
                children: [
                  _modeChip('Mensal', 1, const Color(0xFF0891B2)),
                  _modeChip('Anual', 4, const Color(0xFFEA580C)),
                  _modeChip('Por período', 5, const Color(0xFF9333EA)),
                ],
              ),
              if (_rangeMode == 5) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _cFrom,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setState(() => _cFrom = d);
                        },
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text('De ${DateTimeFormats.dateBR.format(_cFrom)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final first = _cFrom.isBefore(_cTo) ? _cFrom : _cTo;
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _cTo,
                            firstDate: first,
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setState(() => _cTo = d);
                        },
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: Text('Até ${DateTimeFormats.dateBR.format(_cTo)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '${DateTimeFormats.dateBR.format(rf)}  →  ${DateTimeFormats.dateBR.format(rt)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 22),
              Text('Categoria', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
              const SizedBox(height: 8),
              FutureBuilder<
                  ({
                    List<String> income,
                    List<String> expense,
                    List<String> hiddenDefaultIncome,
                    List<String> hiddenDefaultExpense,
                  })>(
                future: _catsFuture,
                builder: (context, snap) {
                  final merged = <String>{};
                  if (snap.hasData) {
                    for (final c in snap.data!.income) {
                      if (c != UserCategoriesService.kIncluirNova) merged.add(c);
                    }
                    for (final c in snap.data!.expense) {
                      if (c != UserCategoriesService.kIncluirNova) merged.add(c);
                    }
                  }
                  final sorted = UserCategoriesService.sortedWithoutIncluirNova(merged);
                  return DropdownButtonFormField<String?>(
                    isExpanded: true,
                    key: ValueKey<String?>(_categoryChoice),
                    initialValue: _categoryChoice,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    hint: const Text('Todas as categorias'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Todas as categorias')),
                      DropdownMenuItem<String?>(value: widget.semCategoriaToken, child: const Text('Sem categoria')),
                      ...sorted.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _categoryChoice = v),
                  );
                },
              ),
              const SizedBox(height: 18),
              Text('Resumo antes de exportar', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
              const SizedBox(height: 8),
              FutureBuilder<({double income, double expense, int docCount})>(
                key: ValueKey<String>(
                  '${rf.millisecondsSinceEpoch}|${rt.millisecondsSinceEpoch}|${_categoryChoice ?? ''}|${widget.statusFilter}',
                ),
                future: FinancePeriodSummary.load(
                  uid: firestoreUserDocIdForAppShell(widget.uid),
                  from: rf,
                  to: rt,
                  statusFilter: widget.statusFilter,
                  categoryExact: _categoryChoice,
                  semCategoriaToken: widget.semCategoriaToken,
                ),
                builder: (context, snap) {
                  final loading = snap.connectionState == ConnectionState.waiting && !snap.hasData;
                  final inc = snap.data?.income ?? 0.0;
                  final exp = snap.data?.expense ?? 0.0;
                  final saldo = inc - exp;
                  String line(String k, String v) => '$k: $v';
                  final fname = _previewFilenameBase(rf, rt);
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (loading)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              borderRadius: BorderRadius.circular(2),
                              color: AppColors.primary,
                            ),
                          ),
                        Text(
                          line('Total receitas', CurrencyFormats.formatBRL(inc)),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35, color: AppColors.financeReceita),
                        ),
                        Text(
                          line('Total despesas', CurrencyFormats.formatBRL(exp)),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35, color: AppColors.financeDespesa),
                        ),
                        Text(
                          line('Saldo', CurrencyFormats.formatBRL(saldo)),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                            color: saldo >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Será salvo como: $fname.pdf (e $fname.csv)',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                'PDF: Extrato Financeiro (layout moderno — logo WISDOMAPP).',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  final (f, t) = _resolveRange();
                  widget.onExportPdf(_FinanceReportExportOpts(
                    from: f,
                    to: t,
                    categoryExact: _categoryChoice,
                  ));
                },
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                label: const Text('Gerar PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: _FinanceScreenState._kPdfActionOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  final (f, t) = _resolveRange();
                  widget.onExportCsv(_FinanceReportExportOpts(
                    from: f,
                    to: t,
                    categoryExact: _categoryChoice,
                  ));
                },
                icon: const Icon(Icons.table_chart_rounded, size: 20),
                label: const Text('Exportar CSV (mesmas colunas do PDF)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.65), width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Comparativo período anterior × atual — layout premium (gradiente, hierarquia, métricas em blocos).
class _PremiumSaldoPeriodoCard extends StatelessWidget {
  const _PremiumSaldoPeriodoCard({
    required this.prevFrom,
    required this.prevTo,
    required this.prevIncome,
    required this.prevExpense,
    required this.prevBalance,
    required this.curIncome,
    required this.curExpense,
    required this.curBalance,
  });

  final DateTime prevFrom;
  final DateTime prevTo;
  final double prevIncome;
  final double prevExpense;
  final double prevBalance;
  final double curIncome;
  final double curExpense;
  final double curBalance;

  static Widget _metricLine({
    required String label,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodPanel({
    required String badge,
    required String dateLine,
    required Color badgeTint,
    required double income,
    required double expense,
    required double balance,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      badgeTint.withValues(alpha: 0.22),
                      badgeTint.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: badgeTint.withValues(alpha: 0.35)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                    color: badgeTint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dateLine,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          _metricLine(
            label: 'Receitas',
            value: CurrencyFormats.formatBRL(income),
            accent: AppColors.financeReceita,
            icon: Icons.south_west_rounded,
          ),
          _metricLine(
            label: 'Despesas',
            value: CurrencyFormats.formatBRL(expense),
            accent: AppColors.financeDespesa,
            icon: Icons.north_east_rounded,
          ),
          _metricLine(
            label: 'Saldo',
            value: CurrencyFormats.formatBRL(balance),
            accent: balance >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
            icon: balance >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prevDates =
        '${DateTimeFormats.dateBR.format(prevFrom)} — ${DateTimeFormats.dateBR.format(prevTo)}';
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final curDates = 'Mesmo filtro da tela · totais do período selecionado';

    final left = _periodPanel(
      badge: 'PERÍODO ANTERIOR',
      dateLine: prevDates,
      badgeTint: AppColors.secondary,
      income: prevIncome,
      expense: prevExpense,
      balance: prevBalance,
    );
    final right = _periodPanel(
      badge: 'PERÍODO ATUAL',
      dateLine: curDates,
      badgeTint: AppColors.accent,
      income: curIncome,
      expense: curExpense,
      balance: curBalance,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF0F4FF),
            Colors.white,
            AppColors.accent.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: AppColors.logoGradient,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.18),
                              AppColors.accent.withValues(alpha: 0.12),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.insights_rounded, color: AppColors.primary, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saldo e fluxo · comparativo',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mesma duração do período selecionado na tela (anterior imediatamente antes).',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (narrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        left,
                        const SizedBox(height: 12),
                        right,
                      ],
                    )
                  else
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 12),
                          Container(width: 1, color: const Color(0xFFE2E8F0)),
                          const SizedBox(width: 12),
                          Expanded(child: right),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão temático para **Onde foi o dinheiro** — abre o preview com gráficos e edição de lançamentos.
class _WhereMoneyExpenseCard extends StatelessWidget {
  const _WhereMoneyExpenseCard({
    required this.categoryName,
    required this.amount,
    required this.percentOfPeriodExpenses,
    required this.accent,
    required this.icon,
    required this.onTap,
  });

  final String categoryName;
  final double amount;
  final double percentOfPeriodExpenses;
  final Color accent;
  final IconData icon;
  final VoidCallback onTap;

  static const List<Color> _palette = [
    Color(0xFFE11D48),
    Color(0xFFEA580C),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF059669),
    Color(0xFF2563EB),
    Color(0xFFDB2777),
    Color(0xFFD97706),
  ];

  static Color accentFor(String category) => _palette[category.hashCode.abs() % _palette.length];

  static IconData iconFor(String category) {
    final l = category.toLowerCase().trim();
    if (l.contains('cart')) return Icons.credit_card_rounded;
    if (l.contains('escola') || l.contains('educa')) return Icons.school_rounded;
    if (l.contains('consórcio') || l.contains('consorcio')) return Icons.groups_rounded;
    if (l.contains('combust') || l.contains('gasolina')) return Icons.local_gas_station_rounded;
    if (l.contains('mercado') || l.contains('super')) return Icons.shopping_cart_rounded;
    if (l.contains('saúde') || l.contains('saude') || l.contains('medic')) return Icons.medical_services_rounded;
    if (l.contains('moradia') || l.contains('aluguel')) return Icons.home_rounded;
    if (l.contains('lazer')) return Icons.sports_esports_rounded;
    if (l.contains('restaur')) return Icons.restaurant_rounded;
    if (l.contains('transport')) return Icons.directions_car_rounded;
    return Icons.pie_chart_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final pctLabel = CurrencyFormats.formatPercentBr(percentOfPeriodExpenses);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accent.withValues(alpha: 0.28)),
                      ),
                      child: Icon(icon, color: accent, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      CurrencyFormats.formatBRLTight(amount),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: accent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: (percentOfPeriodExpenses / 100).clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accent.withValues(alpha: 0.75), accent],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$pctLabel das despesas',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent.withValues(alpha: 0.95)),
                    ),
                    const Spacer(),
                    Text(
                      'Gráficos',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 11, color: accent.withValues(alpha: 0.75)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinanceKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _FinanceKpiCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 560;
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 12),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 6),
            Text(
              'Toque para detalhar',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: narrow ? 140 : 160,
        maxWidth: narrow ? width * 0.46 : 220,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: card,
        ),
      ),
    );
  }
}

/// Barra superior padrão dos previews/sheets do módulo Financeiro.
///
/// Pedido do usuário: cada preview tem **«Voltar»** à esquerda (paridade
/// total iPhone / iOS / Android / Web, sem depender de botão físico) +
/// atalho **«Fechar» (X)** à direita. Mesmo visual usado nos previews do
/// Painel Inicial e demais módulos (Audiências/Compromissos, Produtividade,
/// Meta, Escalas).
Widget buildFinancePreviewTopBar(BuildContext ctx) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
    child: Row(
      children: [
        Material(
          color: AppColors.primary.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(ctx).pop(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_rounded,
                color: AppColors.primary,
                size: 22,
                semanticLabel: 'Voltar',
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            foregroundColor: AppColors.primary,
          ),
          child: const Text(
            'Voltar',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const Spacer(),
        Material(
          color: Colors.grey.shade100,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(ctx).pop(),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.close_rounded,
                size: 22,
                color: Color(0xFF1A237E),
                semanticLabel: 'Fechar',
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}


